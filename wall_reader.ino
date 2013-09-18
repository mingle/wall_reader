#include <SoftwareSerial.h>

#include <Keypad.h>

#include <LiquidCrystal.h>
#include <SPI.h>

//Parallax RFID Reader 
#define RFIDEnablePin 6 //Pin that enables reading. Set as OUTPUT and LOW to read an RFID tag
#define RFIDSerialRate 2400 //Parallax RFID Reader Serial Port Speed

//Using SoftwareSerial Library to locate the serial pins off the default set
//This allows the Arduino to be updated via USB with no conflict
#define RxPin 7 //Pin to read data from Reader 
#define TxPin 4 //Pin to write data to the Reader NOTE: The reader doesn't get written to, don't connect this line.
SoftwareSerial RFIDReader(RxPin,TxPin);

const byte ROWS = 4; // Four rows
const byte COLS = 4; // Three columns
// Define the Keymap
char keys[ROWS][COLS] = {
  {'0','1','2', '3'},
  {'4','5','6', '7'},
  {'8','9', 'E', 'F'},
};
// Connect keypad ROW0, ROW1, ROW2 and ROW3 to these Arduino pins.
byte rowPins[ROWS] = { 12, 9, 8 };
// Connect keypad COL0, COL1 and COL2 to these Arduino pins.
byte colPins[COLS] = { 5, 4, 3, 2 }; 

// Create the Keypad
Keypad kpd = Keypad( makeKeymap(keys), rowPins, colPins, ROWS, COLS );

// define´Shift Register Pins
int latchPin = 1;
int dataPin = 0;
int clockPin = 2;

struct rfid {
  String number;
};

String RFIDTAG=""; //Holds the RFID Code read from a tag
struct rfid lastReadRfid; //Holds the last displayed RFID Tag

long rfidLastReadTime = 0;    

LiquidCrystal lcd(10);

//int incomingByte = 0;   // for incoming serial data

void setup() 
{
  
  // RFID reader SOUT pin connected to Serial RX pin at 2400bps
  RFIDReader.begin(RFIDSerialRate);

//  // Set Enable pin as OUTPUT to connect it to the RFID /ENABLE pin
  pinMode(RFIDEnablePin,OUTPUT); 

  // Activate the RFID reader
  // Setting the RFIDEnablePin HIGH will deactivate the reader
  // which could be usefull if you wanted to save battery life for
  // example.
  digitalWrite(RFIDEnablePin, LOW);

  Serial.begin(9600); // set up Serial library at 9600 bps
  
  lcd.begin(16, 2);
  lcd.print("scan a card...");
}

void loop() 
{  
  char inData[20]; // Allocate some space for the string
  char inChar=-1; // Where to store the character read
  byte index = 0; // Index into array; where to store the character

  while(Serial.available() > 0) // Don't read unless
  {
    if(index < 19) // One less than the size of the array
    {
      inChar = Serial.read(); // Read a character
      inData[index] = inChar; // Store it
      index++; // Increment where to write next
      inData[index] = '\0'; // Null terminate the string
    }
    
    if(strcmp(inData, "UNKNOWN") == 0) {
      lcd.clear();
      lcd.print("set card number");
      String numberInput = GetKeyPadInput();
      Serial.println(numberInput);
      Serial.flush();
    } else {
      lcd.clear();
      lcd.print(inData);
    }    
  }
  
  if(RFIDReader.available() > 0) // If data available from reader
  { 
    ReadSerial(RFIDTAG);  //Read the tag number from the reader. Should return a 10 digit serial number
    
    if(IntervalPast(rfidLastReadTime, 4000))
    {
      lastReadRfid.number = RFIDTAG;
      Serial.println(RFIDTAG);
      Serial.flush();
      rfidLastReadTime = millis();
    }        
  }
}

String GetKeyPadInput() {
  
  boolean enter = false;
  String input = "";
  
  while(!enter) {
  
    char key = kpd.getKey();
    
    if(key)
    {
      switch (key)
      {
        case 'E':
          enter = true;
          break;
        case 'F':
          // nothing yet
          break;
        default:
          if(input.length() == 0) {
            lcd.clear();
          }
          lcd.print(key);
          input += key;
      }
    }
  }
  
  return input;
}

boolean IntervalPast(long lastReadTime, long interval) {
  return millis() - rfidLastReadTime > interval;
}

void ReadSerial(String &ReadTagString)
{
  int bytesread = 0;
  int  val = 0; 
  char code[10];
  String TagCode="";

  if(RFIDReader.available() > 0) {          // If data available from reader 
    if((val = RFIDReader.read()) == 10) {   // Check for header 
      bytesread = 0; 
      while(bytesread<10) {                 // Read 10 digit code 
        if( RFIDReader.available() > 0) { 
          val = RFIDReader.read(); 
          if((val == 10)||(val == 13)) {   // If header or stop bytes before the 10 digit reading 
            break;                         // Stop reading 
          } 
          code[bytesread] = val;           // Add the digit           
          bytesread++;                     // Ready to read next digit  
        } 
      } 
      if(bytesread == 10) {                // If 10 digit read is complete 

        for(int x=0;x<10;x++)              //Copy the Chars to a String
        {
          TagCode += code[x];
        }
        ReadTagString = TagCode;          //Update the caller
        while(RFIDReader.available() > 0) //Burn off any characters still in the buffer
        {
          RFIDReader.read();
        } 

      } 
      bytesread = 0;
      TagCode="";
    } 
  } 
}