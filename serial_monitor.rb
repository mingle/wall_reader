require 'rubygems'
require 'serialport'
require 'yaml'

require 'date'

require "net/https"
require "uri"
require "sqlite3"

class Storage
  
  class << self
  
    def init_db
      @@db = SQLite3::Database.new "cards.db"
      @@db.execute <<-SQL
        create table IF NOT EXISTS cards (
          num TEXT,
          rfid TEXT,
          current_done_value INTEGER
        );
      SQL
    end
  
    def create_card(card)
      @@db.execute("INSERT INTO cards (num, rfid, current_done_value) VALUES (?, ?, ?)", [card.card_number, card.rfid, card.current_done_value])
    end
    
    def destroy_card(card)
      @@db.execute("DELETE FROM cards WHERE num = ? and rfid = ?", [card.card_number, card.rfid])
    end
    
    def update_card(card)
      @@db.execute("UPDATE cards set rfid = ?, current_done_value = ? where num = #{card.card_number}", [card.rfid, card.current_done_value])
    end
    
    def load_cards(values)
       cards = []
       puts "loading cards..."
       @@db.execute("select * from cards" ) do |row|
         c = CardRFID.new(row[1], row[0], values)
         c.current_done_value = row[2]
         puts "    ##{c.card_number}(#{c.rfid}) => #{c.status}"
         cards << c
       end       
       cards
     end

     def delete_cards
       @@db.execute("delete from cards;")
     end
    
  end
  
end

class CardRFID 
  
  attr_reader :card_number, :rfid
  attr_accessor :current_done_value
  
  def initialize(rfid, card_number, values)
    @rfid = rfid
    @card_number = card_number
    @current_done_value = 0
    @values = values
  end
  
  def next_property_value
    @values[@current_done_value]
  end
  
  def read?(read_rfid)
    if @rfid == read_rfid.to_s
      @current_done_value = @current_done_value + 1
      Storage.update_card(self)
      true
    end
  end
  
  def done?
    @values.last == @values[@current_done_value]
  end
  
  def status
    @values[@current_done_value]
  end
  
  def create 
    Storage.create_card(self)
  end
  
  def destroy
    Storage.destroy_card(self)
  end
  
end

class Request

  def initialize(options)
    @username = options[:username] 
    @password = options[:password]
    @protocol = options[:protocol]
    @base_url = "#{@protocol}://#{options[:host]}:#{options[:port]}"
  end
  
  def put(url, data)
    uri = URI.parse("#{@base_url}#{url}")
    http = configure_http(uri, @protocol)
    request = Net::HTTP::Put.new(uri.request_uri)
    request.basic_auth(@username, @password)
    request.set_form_data(data)
    http.request(request)
  end
  
  def post(url, data)
    uri = URI.parse("#{@base_url}#{url}")
    http = configure_http(uri, @protocol)    
    request = Net::HTTP::Post.new(uri.request_uri)
    request.basic_auth(@username, @password)
    request.set_form_data(data)
    http.request(request)
  end
  
  private
  
  def configure_http(uri, protocol)
    http = Net::HTTP.new(uri.host, uri.port)
    if(protocol == "https")
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end
    http
  end
  
end

class Mingle
  
  attr_reader :values, :serial_port
  
  def initialize
    config = YAML.load(File.read("./config.yml")).first
    
    @request = Request.new(:username => config["username"], :password => config["password"], 
                           :host => config["host"], :port => config["port"] || 80, :protocol => config["protocol"])
    @project = config["project"]
    
    @property_name = config["property"]
    @serial_port = config["serial_port"]
    @values = config["values"]
  end
  
  def update_status(card)
    @request.put("/api/v2/projects/#{@project}/cards/#{card.card_number}.xml", {"card[properties][][name]" => @property_name, 
                    "card[properties][][value]" => card.next_property_value })
  end

  def create_card
    create_card_type = "Story"
    create_card_name = "CREATED BY THE READER"
    
    response = @request.post("/api/v2/projects/#{@project}/cards.xml", {  "card[name]" => create_card_name, 
                                      "card[card_type_name]" => create_card_type, 
                                      "card[properties][][name]" => @property_name, 
                                      "card[properties][][value]" => @values.first 
                                    })
    /cards\/(.*)\.xml/.match(response['Location'])[1]
  end
  
end

class MingleCardReader
  
  def initialize 
    @mingle = Mingle.new
    @sp = SerialPort.new(@mingle.serial_port, 9600, 8, 1, SerialPort::NONE)
    @cards = Storage.load_cards(@mingle.values)
  end
  
  def monitor
    while (i = @sp.gets.chomp) do
      i.strip!
      puts "Read RFID: #{i}"
      
      if(i.length >= 10)
        
        read_card = @cards.find { |c| c.read?(i) }

        unless read_card.nil?
          update_card(read_card)
        else
          associate_card(i)
        end
      
        print_to_reader("scan a card...")
        
      end        
    end
  end
  
  private
  
  def print_busy_tone
    print_to_reader("please wait ...")
  end
  
  def update_card(read_card)
    print_busy_tone
    @mingle.update_status(read_card)
    print_to_reader("updated card #{read_card.card_number}")
    print_to_reader("to #{read_card.next_property_value.slice(0..12)}")
    
   if read_card.done?
      read_card.destroy
      @cards.delete(read_card)
      print_to_reader("reuse card", 5)
    end
  end
  
  def associate_card(rfid)
    print_to_reader "UNKNOWN"
    new_card_number = @sp.gets.chomp
    
    if(new_card_number == "0")
      print_busy_tone
      new_card_number = @mingle.create_card
      print_to_reader "created #{new_card_number}", 3
    else
      print_to_reader "set to #{new_card_number}", 3
    end
    c = CardRFID.new(rfid.to_s, new_card_number, @mingle.values)
    c.create
    @cards << c
  end
  
  def print_to_reader(message, delay=1)
    @sp.print(message)
    sleep delay
  end

end 

Storage.init_db
  
begin     
  while TRUE do
    reader = MingleCardReader.new
    reader.monitor        
  end     
rescue Exception => e
  puts "ERROR: #{e.inspect}"
  puts e.backtrace
end