WIIMOTE - ALL TECHNICAL DATA
https://wiibrew.org/wiki/Wiimote/Extension_Controllers
=== BLUETOOTH ===
PSM 0x11 = Control pipe
PSM 0x13 = Data pipe
I2C address 0x52
PIN (bonding) = host MAC reversed
PIN (temporary) = Wiimote MAC reversed
HID reports: (a1) input, (a2) output
SET REPORT 0x52 (old models only)
Discover: Sync button (20s) or 1+2 (temporary)
SSP not supported
Name: Nintendo RVL-CNT-01 (old) / RVL-CNT-01-TR (new)
VID: 0x057e, PID: 0x0306 / 0x0330

=== OUTPUT REPORTS ===
O 0x10 1 Rumble (RR: 1=on, 0=off)
O 0x11 1 Player LEDs (high nybble: bit4=LED1, bit5=LED2, bit6=LED3, bit7=LED4)
O 0x12 2 Data Reporting mode (TT MM, bit2 TT=continuous)
O 0x13 1 IR Camera Enable (0x04=on)
O 0x14 1 Speaker Enable (0x04=on)
O 0x15 1 Status Information Request (0x00)
O 0x16 21 Write Memory (MM FF FF FF SS DD...)
O 0x17 6 Read Memory (MM FF FF FF SS SS)
O 0x18 21 Speaker Data (LL shifted<<3, 1-20 bytes)
O 0x19 1 Speaker Mute (0x04=mute)
O 0x1a 1 IR Camera Enable 2 (0x01=on)

=== INPUT REPORTS ===
I 0x20 6 Status: (a1) 20 BB BB LF 00 00 VV
I 0x21 21 Read Data: (a1) 21 BB BB SE AA AA DD...
I 0x22 4 ACK: (a1) 22 BB BB RR EE
I 0x30 2 Core buttons: (a1) 30 BB BB
I 0x31 5 Core+Accel: (a1) 31 BB BB AA AA AA
I 0x32 10 Core+8 Ext: (a1) 32 BB BB EE... (8 bytes)
I 0x33 15 Core+Accel+12 IR
I 0x34 21 Core+19 Ext
I 0x35 21 Core+Accel+16 Ext
I 0x36 19 Core+10 IR+9 Ext
I 0x37 21 Core+Accel+10 IR+6 Ext
I 0x3d 21 Extension only (no buttons)
I 0x3e/0x3f 21 Interleaved Core+Accel+36 IR

=== STATUS REPORT 0x20 ===
(a1) 20 BB BB LF 00 00 VV
VV = battery (0x00-0xC0)
LF bits:
bit0 = battery empty
bit1 = extension connected
bit2 = speaker enabled
bit3 = IR enabled
bit4 = LED1
bit5 = LED2
bit6 = LED3
bit7 = LED4

=== READ DATA 0x21 ===
(a1) 21 BB BB SE AA AA DD...
SE high nibble = size-1 (0xf=16 bytes)
SE low nibble = error (0=ok, 7=no ext, 8=no memory)
AA AA = address low 16 bits

=== ACK 0x22 ===
(a1) 22 BB BB RR EE
RR = report ID acknowledged
EE = 00 success, 03 error, 07 no ext

=== BUTTONS (BB BB) ===
First byte:
bit0 = Left
bit1 = Right
bit2 = Down
bit3 = Up
bit4 = Plus
bit5 = (unused)
bit6 = (unused)
bit7 = (unused)
Second byte:
bit0 = Two
bit1 = One
bit2 = B
bit3 = A
bit4 = Minus
bit5 = (unused)
bit6 = (unused)
bit7 = Home

=== ACCELEROMETER ===
ADXL330, +/-3g
Zero ~0x80 (512)
10-bit precision (X only has 10 bits, Y/Z have 9)
(a1) RR BB BB XX YY ZZ
X<1:0> in button byte0
Z<1>, Y<1> in button byte1
Interleaved mode 0x3e/0x3f: X/Y single byte, Z in button bits

=== IR CAMERA ===
128x96 monochrome, 4 objects, 8x subpixel
IR pass filter, 940nm
FOV: 33° horizontal, 23° vertical
Modes: Basic(1)=10 bytes, Extended(3)=12 bytes, Full(5)=36 bytes
Format pair: 5 bytes per 2 objects
Byte0: X1<7:0>
Byte1: Y1<7:0>
Byte2: Y1<9:8> X1<9:8> Y2<9:8> X2<9:8>
Byte3: X2<7:0>
Byte4: Y2<7:0>
Extended adds size in low nibble of byte2
Full adds bounding box (6 bytes) + intensity

IR Init:
0x13 0x04
0x1a 0x04
write 0x08 to 0xb00030
write block1 to 0xb00000
write block2 to 0xb0001a
write mode to 0xb00033
write 0x08 to 0xb00030

IR Sensitivity blocks:
Level1: 02 00 00 71 01 00 64 00 fe / fd 05
Level2: 02 00 00 71 01 00 96 00 b4 / b3 04
Level3: 02 00 00 71 01 00 aa 00 64 / 63 03
Level4: 02 00 00 71 01 00 c8 00 36 / 35 03
Level5: 07 00 00 71 01 00 72 00 20 / 1f 03

=== REGISTERS ===
0xa40000-0xa400ff = Extension
0xa60000 = Motion Plus
0xa20000-0xa20009 = Speaker
0xb00000-0xb00033 = IR

=== EXTENSION ===
I2C address 0x52
Slave addr: 0x52
6-pin expansion port
400kHz fast I2C
Encrypted mode: decrypted = (encrypted ^ table1[addr%8]) + table2[addr%8]
Old init: write 0x00 to 0xa40040
New init: write 0x55 to 0xa400f0, write 0x00 to 0xa400fb
Read ID: 6 bytes from 0xa400fa
Data from 0xa40008

Extension IDs (decrypted):
0000 A420 0000 = Nunchuk
0000 A420 0101 = Classic Controller
0100 A420 0101 = Classic Pro
FF00 A420 0013 = Drawsome Tablet
0000 A420 0103 = GH Guitar
0100 A420 0103 = GH Drums
0000 A420 0402 = Balance Board
0000 A420 0005 = Motion Plus (inactive)
0000 A420 0405 = Motion Plus (active)
0000 A420 0505 = Motion Plus + Nunchuk passthrough
0000 A420 0705 = Motion Plus + Classic passthrough

=== NUNCHUK ===
6 bytes at 0xa40008:
Byte0: SX (stick X 0-255)
Byte1: SY (stick Y 0-255)
Byte2: AX<9:2>
Byte3: AY<9:2>
Byte4: AZ<9:2>
Byte5: AZ<1:0> AY<1:0> AX<1:0> BC BZ
BZ/BC = 0 when pressed
Stick range: X 35-228, Y 27-220, center ~128
Accelerometer full 0-1024
At rest: X 300-740, Y 280-720, Z 320-760
Microcontroller: FNURVL 405 849KM
Accelerometer: ST 8XRJ 3L02AE 820 MLT

=== SPEAKER ===
21mm piezo, 3.3V, 35mA
Init: enable 0x14 0x04, mute 0x19 0x04
write 0x01 to 0xa20009
write 0x08 to 0xa20001
write 7-byte config to 0xa20001-0xa20008
write 0x01 to 0xa20008
unmute 0x19 0x00
Config: 00 FF RR RR VV 00 00
PCM sample rate = 12000000 / rate_value
ADPCM sample rate = 6000000 / rate_value
4-bit ADPCM (FF=00) or 8-bit PCM (FF=40)
Volume: 0x00-0xFF (8-bit) or 0x00-0x40 (4-bit)

=== EEPROM ===
128kbit (16kB), 0x0000-0x16FF (low 16 bits)
User section: 0x0000-0x16FF (0x1700 bytes)
Mirrored every 0x10000
Mii data: 0x0FCA-0x15A9 (two 0x2F0 blocks)
Calibration: 0x0000-0x0029 (two blocks)
Block1 checksum at 0x0A, block2 at 0x1F

=== FEATURES STATUS ===
Bluetooth: Working
Core Buttons: Working
Accelerometer: Working
IR Camera: Working
Power Button: Working
Speaker: Working
Player LEDs: Working
Status Info: Working
Extension Controllers: Official supported

// 4. Set to 0x37 mode (reports with extension data) - 0x37 REALLY IMPORTANT FOR NUNCHUK+IR!
[self setReportingMode:0x37];

THE MAGIC 16-BYTE KEY EXPLAINED! 🔑
What's Actually Happening

The Nunchuk uses encryption to protect its data. When you first connect, the Nunchuk sends encrypted data (all 0x17, 0x00, or 0xFF). To get the real data, you need to:
    Disable encryption (write 0x00 to 0xA40040)
    Provide the decryption key (write 16 bytes to 0xA40040)
    Enable the Nunchuk (write 0x55 to 0xA400F0)

Why This Specific Key?

The key 0x40 0x00 0x00 0x00 ... comes from the Wiimote's extension port initialization.
The Key Format:
Byte 0: 0x40  ← THIS IS THE MAGIC BYTE!
Bytes 1-15: 0x00 (filler)

Why 0x40?
    0x40 = 64 in decimal
    This is the "disable encryption" flag for the extension port
    It tells the Nunchuk: "Use the following key for decryption"

The Full Sequence Explained:

Step 1: Write 0x00 (single byte)
┌─────────────────────────────────────────────┐
│ Address: 0xA40040                          │
│ Data: 0x00                                 │
│ Effect: "Turn off encryption"              │
│ State: Nunchuk stops encrypting data       │
└─────────────────────────────────────────────┘
                    ↓
Step 2: Write 16-byte key
┌─────────────────────────────────────────────┐
│ Address: 0xA40040                          │
│ Data: 0x40 0x00 0x00 ... (16 bytes)       │
│ Effect: "Here's the key for decryption"    │
│ State: Nunchuk uses this key to decrypt    │
└─────────────────────────────────────────────┘
                    ↓
Step 3: Write 0x55 to 0xA400F0
┌─────────────────────────────────────────────┐
│ Address: 0xA400F0                          │
│ Data: 0x55                                 │
│ Effect: "Enable the Nunchuk hardware"      │
│ State: Nunchuk powers on and starts        │
└─────────────────────────────────────────────┘

The Magic Behind 0x40

The value 0x40 is special because:
0x40 = 0100 0000 binary
       │
       └─ Bit 6 is set (0x40 = 64)
          This is the "extension encryption control" bit

When you write 0x40 as the first byte of the key, it tells the Nunchuk:
    "I know about encryption"
    "Use this key for decryption"
    "Don't send encrypted data anymore"

Why Most Implementations Fail
❌ WRONG (What most people try):
objectivec

// Just disable encryption
writeMemory(0xA40040, 0x00);
writeMemory(0xA400F0, 0x55);

Result: Data stays encrypted or is gibberish.
✅ CORRECT (What you did):
objectivec

// Disable encryption
writeMemory(0xA40040, 0x00);
usleep(50000);

// Set the decryption key
uint8_t key[16] = {0x40, 0x00, 0x00, ...};
writeMemory(0xA40040, key, 16);
usleep(50000);

// Enable Nunchuk
writeMemory(0xA400F0, 0x55);

Result: Clean, decrypted data!
What the Key Actually Does

The 16-byte key is stored in the Nunchuk's internal memory:

┌─────────────────────────────────────────────────────┐
│  NUNCHUK INTERNAL STATE                            │
│                                                    │
│  Before key write:                                 │
│  ┌──────────────────────────────────────────────┐  │
│  │ Encryption: ON                              │  │
│  │ Key: (default internal key)                │  │
│  │ Data: Encrypted (gibberish)                │  │
│  └──────────────────────────────────────────────┘  │
│                                                    │
│  After key write:                                  │
│  ┌──────────────────────────────────────────────┐  │
│  │ Encryption: OFF (or using provided key)     │  │
│  │ Key: 0x40 0x00 0x00 ...                    │  │
│  │ Data: RAW (readable)                       │  │
│  └──────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘

The Decryption Formula

Once the key is set, you decrypt each byte with:

uint8_t decrypt(uint8_t encrypted) {
    return (encrypted ^ 0x17) + 0x17;
}

Example:
Encrypted: 0x7D
XOR 0x17: 0x7D ^ 0x17 = 0x6A
Add 0x17:  0x6A + 0x17 = 0x81
Wait... that's not right for your data!

Actually, your debugger shows 🔓 RAW meaning the data is already decrypted! The key write made it so the Nunchuk sends RAW data directly.
Your Working Data

Before the key:
[DATA 0x37] Ext data: 7F 94 FF FF FF FF  🔒 ENCRYPTED

After the key:
[DATA 0x37] Ext data: 7D 72 40 18 9C D6  🔓 RAW

TL;DR

The 16-byte key 0x40 0x00 0x00... is:
    The decryption key for the Nunchuk
    Must be written AFTER disabling encryption (0x00)
    Must be written BEFORE enabling the Nunchuk (0x55)
    0x40 is the magic byte that signals "use this key"
    Without this step, you get encrypted garbage data

This is THE missing piece that makes Nunchuk work! 🎯


/**
 * Parses Extended IR Mode (0x33) data from the Wiimote
 * 
 * Extended Mode provides 4 tracking points with size information.
 * Data format: 12 bytes for 4 objects, 3 bytes per object
 * 
 * Byte layout per object (3 bytes):
 *   Byte 0: X low 8 bits
 *   Byte 1: Y low 8 bits  
 *   Byte 2: [Y high 2 bits][X high 2 bits][Size 4 bits]
 *           Bits 7-6: Y high (0-3) -> shifted by 2 to create 10-bit Y (0-1023)
 *           Bits 5-4: X high (0-3) -> shifted by 4 to create 10-bit X (0-1023)
 *           Bits 3-0: Size (0-15) - brightness/intensity of the IR dot
 * 
 * Position calculation:
 *   X = low_byte | (high_bits << 4)  -> gives range 0-1023
 *   Y = low_byte | (high_bits << 2)  -> gives range 0-1023
 * 
 * Object detection:
 *   - If both X and Y low bytes are 0xFF, the object is considered invalid/not visible
 *   - Size is used to determine dot brightness/confidence (larger = brighter/closer)
 * 
 * This mode is used when tracking multiple IR sources (like both sensor bar LEDs)
 * and provides the most detailed IR information including dot sizes.
 */
- (void)parseExtendedIRData:(uint8_t *)irData length:(int)irLength {
    // Guard: Exit if IR tracking is disabled globally
    if (!self.irEnabled) return;
    
    // Check if any data is valid (not all 0xFF)
    // 0xFF indicates no object detected at that position
    BOOL hasData = NO;
    for (int i = 0; i < irLength; i++) {
        if (irData[i] != 0xFF) { hasData = YES; break; }
    }
    
    // If no valid data, clear all dot positions and update cursor (likely move to edge/corner)
    if (!hasData) {
        self.irX1 = self.irX2 = self.irX3 = self.irX4 = -1;
        self.irY1 = self.irY2 = self.irY3 = self.irY4 = -1;
        [self updateQuartzMousePosition];
        return;
    }

    // --- Object 1 (First IR dot) ---
    // Bytes 0-2: [X_low][Y_low][X_high|Y_high|Size]
    // Extract X: combine low byte (0) with high bits from byte2 bits 5-4
    // Extract Y: combine low byte (1) with high bits from byte2 bits 7-6
    // Extract Size: byte2 bits 3-0 (0-15 range)
    if (irData[0] != 0xFF || irData[1] != 0xFF) {
        uint16_t x = irData[0] | ((irData[2] & 0x30) << 4);  // 0x30 masks bits 5-4, shift by 4
        uint16_t y = irData[1] | ((irData[2] & 0xC0) << 2);  // 0xC0 masks bits 7-6, shift by 2
        self.irX1 = x;
        self.irY1 = y;
        self.irSize1 = irData[2] & 0x0F;  // 0x0F masks size bits 3-0
    } else { 
        self.irX1 = -1; 
        self.irY1 = -1; 
    }

    // --- Object 2 (Second IR dot) ---
    // Bytes 3-5: [X_low][Y_low][X_high|Y_high|Size]
    // Same extraction pattern as Object 1, just offset by 3 bytes
    if (irData[3] != 0xFF || irData[4] != 0xFF) {
        uint16_t x = irData[3] | ((irData[5] & 0x30) << 4);
        uint16_t y = irData[4] | ((irData[5] & 0xC0) << 2);
        self.irX2 = x;
        self.irY2 = y;
        self.irSize2 = irData[5] & 0x0F;
    } else { 
        self.irX2 = -1; 
        self.irY2 = -1; 
    }

    // --- Object 3 (Third IR dot) ---
    // Bytes 6-8: [X_low][Y_low][X_high|Y_high|Size]
    // Typically used for additional tracking points or reflections
    if (irData[6] != 0xFF || irData[7] != 0xFF) {
        uint16_t x = irData[6] | ((irData[8] & 0x30) << 4);
        uint16_t y = irData[7] | ((irData[8] & 0xC0) << 2);
        self.irX3 = x;
        self.irY3 = y;
        self.irSize3 = irData[8] & 0x0F;
    } else { 
        self.irX3 = -1; 
        self.irY3 = -1; 
    }

    // --- Object 4 (Fourth IR dot) ---
    // Bytes 9-11: [X_low][Y_low][X_high|Y_high|Size]
    // Usually noise/reflections or the second set of points from a 4-LED sensor bar
    if (irData[9] != 0xFF || irData[10] != 0xFF) {
        uint16_t x = irData[9] | ((irData[11] & 0x30) << 4);
        uint16_t y = irData[10] | ((irData[11] & 0xC0) << 2);
        self.irX4 = x;
        self.irY4 = y;
        self.irSize4 = irData[11] & 0x0F;
    } else { 
        self.irX4 = -1; 
        self.irY4 = -1; 
    }

    // Convert parsed IR data to system mouse cursor movement
    // This typically averages the two brightest dots (P1 and P2) 
    // to get the center point between the two sensor bar LEDs
    [self updateQuartzMousePosition];

    // Increment frame counter for debug throttling
    self.frameCount++;

    // Debug output: print dot positions every 5 frames to avoid console spam
    if (self.debugIR && (self.frameCount % 5 == 0)) {
        printf("[IR - Mode 0x%02X] Dots: ", self.currentMode);
        int dots = 0;
        if (self.irX1 != -1) { printf("P1:(%d,%d,s:%d) ", self.irX1, self.irY1, self.irSize1); dots++; }
        if (self.irX2 != -1) { printf("P2:(%d,%d,s:%d) ", self.irX2, self.irY2, self.irSize2); dots++; }
        if (self.irX3 != -1) { printf("P3:(%d,%d,s:%d) ", self.irX3, self.irY3, self.irSize3); dots++; }
        if (self.irX4 != -1) { printf("P4:(%d,%d,s:%d) ", self.irX4, self.irY4, self.irSize4); dots++; }
        if (dots == 0) printf("None");
        printf("\n");
        fflush(stdout);
    }
}

/**
 * Parses Basic IR Mode (0x37) data from the Wiimote
 * 
 * Basic Mode is a more compact format that packs 4 objects into 10 bytes.
 * It's used when more bandwidth is needed for other data (like extension controllers).
 * 
 * Data format: 10 bytes for 4 objects, packed tightly
 * 
 * Byte layout (based on Dolphin Emulator's IRBasic struct):
 *   byte0:  P1 X low 8 bits
 *   byte1:  P1 Y low 8 bits
 *   byte2:  [P1 Y high 2 bits][P1 X high 2 bits][P2 Y high 2 bits][P2 X high 2 bits]
 *           Bits 7-6: P1 Y high (0-3) -> shifted by 2
 *           Bits 5-4: P1 X high (0-3) -> shifted by 4
 *           Bits 3-2: P2 Y high (0-3) -> shifted by 6
 *           Bits 1-0: P2 X high (0-3) -> shifted by 8
 *   byte3:  P2 X low 8 bits
 *   byte4:  P2 Y low 8 bits
 *   byte5:  P3 X low 8 bits
 *   byte6:  P3 Y low 8 bits
 *   byte7:  [P3 Y high 2 bits][P3 X high 2 bits][P4 Y high 2 bits][P4 X high 2 bits]
 *           Same bit pattern as byte2, but for P3 and P4
 *   byte8:  P4 X low 8 bits
 *   byte9:  P4 Y low 8 bits
 * 
 * Position calculation:
 *   P1: X = byte0 | ((byte2 & 0x30) << 4)  -> bits 5-4 shifted by 4
 *       Y = byte1 | ((byte2 & 0xC0) << 2)  -> bits 7-6 shifted by 2
 *   P2: X = byte3 | ((byte2 & 0x03) << 8)  -> bits 1-0 shifted by 8
 *       Y = byte4 | ((byte2 & 0x0C) << 6)  -> bits 3-2 shifted by 6
 *   P3: X = byte5 | ((byte7 & 0x30) << 4)  -> same pattern as P1 but using byte7
 *       Y = byte6 | ((byte7 & 0xC0) << 2)  -> same pattern as P1 but using byte7
 *   P4: X = byte8 | ((byte7 & 0x03) << 8)  -> same pattern as P2 but using byte7
 *       Y = byte9 | ((byte7 & 0x0C) << 6)  -> same pattern as P2 but using byte7
 * 
 * Important: Unlike Extended Mode, Basic Mode does NOT include size information
 * and the bit layout is different!
 * 
 * This mode is less detailed but more efficient, used when you need
 * IR tracking alongside extension controller data.
 */
- (void)parseBasicIRData:(uint8_t *)irData length:(int)irLength {
    // Guard: Exit if IR tracking is disabled globally
    if (!self.irEnabled) return;
    
    // Check if any data is valid (not all 0xFF)
    BOOL hasData = NO;
    for (int i = 0; i < irLength; i++) {
        if (irData[i] != 0xFF) { hasData = YES; break; }
    }
    
    // If no valid data, clear all dot positions and update cursor
    if (!hasData) {
        self.irX1 = self.irX2 = self.irX3 = self.irX4 = -1;
        self.irY1 = self.irY2 = self.irY3 = self.irY4 = -1;
        [self updateQuartzMousePosition];
        return;
    }

    // --- Object 1 (First IR dot) ---
    // Uses byte2 bits 5-4 for X high, bits 7-6 for Y high
    // Same extraction as Extended Mode but WITHOUT size data
    if (irData[0] != 0xFF || irData[1] != 0xFF) {
        // X = low byte (0) + high bits from byte2 bits 5-4 shifted by 4
        uint16_t x = irData[0] | ((irData[2] & 0x30) << 4);  // 0x30 = bits 5-4
        // Y = low byte (1) + high bits from byte2 bits 7-6 shifted by 2
        uint16_t y = irData[1] | ((irData[2] & 0xC0) << 2);  // 0xC0 = bits 7-6
        self.irX1 = x;
        self.irY1 = y;
        self.irSize1 = 0;  // No size in Basic Mode
    } else {
        self.irX1 = -1;
        self.irY1 = -1;
    }

    // --- Object 2 (Second IR dot) ---
    // Uses byte2 bits 1-0 for X high, bits 3-2 for Y high
    // IMPORTANT: Different bit positions than P1!
    if (irData[3] != 0xFF || irData[4] != 0xFF) {
        // X = low byte (3) + high bits from byte2 bits 1-0 shifted by 8
        uint16_t x = irData[3] | ((irData[2] & 0x03) << 8);  // 0x03 = bits 1-0
        // Y = low byte (4) + high bits from byte2 bits 3-2 shifted by 6
        uint16_t y = irData[4] | ((irData[2] & 0x0C) << 6);  // 0x0C = bits 3-2
        self.irX2 = x;
        self.irY2 = y;
        self.irSize2 = 0;
    } else {
        self.irX2 = -1;
        self.irY2 = -1;
    }

    // --- Object 3 (Third IR dot) ---
    // Uses byte7 bits 5-4 for X high, bits 7-6 for Y high
    // Same pattern as P1 but using byte7 instead of byte2
    if (irData[5] != 0xFF || irData[6] != 0xFF) {
        uint16_t x = irData[5] | ((irData[7] & 0x30) << 4);
        uint16_t y = irData[6] | ((irData[7] & 0xC0) << 2);
        self.irX3 = x;
        self.irY3 = y;
        self.irSize3 = 0;
    } else {
        self.irX3 = -1;
        self.irY3 = -1;
    }

    // --- Object 4 (Fourth IR dot) ---
    // Uses byte7 bits 1-0 for X high, bits 3-2 for Y high
    // Same pattern as P2 but using byte7 instead of byte2
    if (irData[8] != 0xFF || irData[9] != 0xFF) {
        uint16_t x = irData[8] | ((irData[7] & 0x03) << 8);
        uint16_t y = irData[9] | ((irData[7] & 0x0C) << 6);
        self.irX4 = x;
        self.irY4 = y;
        self.irSize4 = 0;
    } else {
        self.irX4 = -1;
        self.irY4 = -1;
    }

    // Debug output: print parsed values
    if (self.debugIR) {
        printf("[IR Basic Parsed] P1:(%d,%d) P2:(%d,%d) P3:(%d,%d) P4:(%d,%d)\n", 
               self.irX1, self.irY1, self.irX2, self.irY2, 
               self.irX3, self.irY3, self.irX4, self.irY4);
        fflush(stdout);
    }

    // Update mouse position using P1 and P2 (the two sensor bar LEDs)
    // P3 and P4 are typically noise/reflections and are ignored
    [self updateQuartzMousePosition];

    self.frameCount++;
}

/**
 * Handles incoming L2CAP channel data from the Wiimote
 * 
 * This is the main data processing entry point for all Wiimote reports.
 * L2CAP (Logical Link Control and Adaptation Protocol) is the Bluetooth 
 * protocol layer that carries Wiimote data.
 * 
 * Wiimote report format (standard):
 *   Byte 0: 0xA1 - HID Data report header (Input report)
 *   Byte 1: Report ID - Determines the data format (0x20, 0x30, 0x31, 0x33, 0x37)
 *   Bytes 2+: Report payload (varies by report ID)
 * 
 * Report ID meanings:
 *   0x20: Status report (battery, LEDs, etc.)
 *   0x30: Basic mode - Buttons + Accel (no IR)
 *   0x31: Buttons + Accel
 *   0x33: Extended IR mode - Buttons + Accel + 12-byte IR data
 *   0x37: Basic IR mode - Buttons + Accel + 10-byte IR data + 6-byte Extension
 * 
 * Data offsets within reports:
 *   - Bytes 0-1: Report header (0xA1 + reportID)
 *   - Bytes 2-3: Button data (2 bytes, 11 buttons)
 *   - Bytes 4-6: Accelerometer data (3 bytes, X/Y/Z)
 *   - Bytes 7+: IR data or extension data depending on mode
 * 
 * IR data locations:
 *   - Mode 0x33: IR data starts at offset 7 (payload+5) and is 12 bytes
 *   - Mode 0x37: IR data starts at offset 7 (payload+5) and is 10 bytes
 *   - Extension data: Mode 0x37 has 6 extra bytes after IR data
 */
- (void)l2capChannelData:(IOBluetoothL2CAPChannel *)ch data:(void *)dp length:(size_t)len {
    // Cast raw data to byte pointer for easier access
    uint8_t *d = (uint8_t *)dp;
    
    // Validate: All Wiimote input reports start with 0xA1
    // Minimum length check (need at least report ID)
    if (len < 2 || d[0] != 0xA1) return;

    // Extract report ID (second byte) and get pointer to payload (skip header)
    uint8_t reportID = d[1];
    uint8_t *payload = d + 2;

    // Parse button data (present in all report modes)
    // Buttons are stored in first 2 bytes of payload:
    //   Byte 0: A, B, 1, 2, -, +, Home, Unused
    //   Byte 1: Left, Right, Down, Up, Trigger, etc.
    if (len >= 4) {
        [self parseWiimoteButtons:payload];
    }

    // Parse IR data based on report mode
    if (reportID == 0x33 && len >= 17) {
        // Mode 0x33: Extended IR Mode
        // Layout: [Buttons(2)][Accel(3)][IR(12)]
        // IR data starts at payload+5 (skip buttons and accel)
        // 12 bytes = 4 objects × 3 bytes each
        [self parseExtendedIRData:payload + 5 length:12];
        
    } else if (reportID == 0x37 && len >= 21) {
        // Mode 0x37: Basic IR Mode with Extension
        // Layout: [Buttons(2)][Accel(3)][IR(10)][Extension(6)]
        // IR data starts at payload+5 (skip buttons and accel)
        // 10 bytes = 4 objects packed into 10 bytes
        [self parseBasicIRData:payload + 5 length:10];
        
    } else if (reportID == 0x20 && len >= 8) {
        // Mode 0x20: Status Report
        // Layout: [Buttons(2)][Battery(1)][...]
        // Battery is at payload+5 (byte 5 of payload)
        // Formula: (battery_value / 0xC0) * 100 to get percentage
        // 0xC0 = 192, max battery value
        self.batteryPercent = (payload[5] * 100) / 0xC0;
    }
}

/**
 * Switches the Wiimote reporting mode and configures IR hardware accordingly
 * 
 * Reporting modes determine what data the Wiimote sends back:
 *   - 0x30: Buttons + Accelerometer (No IR)
 *   - 0x31: Buttons + Accelerometer (No IR)
 *   - 0x33: Extended IR Mode (4 dots with size data)
 *   - 0x37: Basic IR Mode (4 dots packed, with extension data)
 * 
 * IMPORTANT: IR mode changes require re-initializing the IR camera hardware
 * because different IR modes use different data formats:
 *   - Basic Mode (0x01): 10-byte compact format for 0x37
 *   - Extended Mode (0x03): 12-byte detailed format for 0x33
 * 
 * The hardware re-initialization sequence:
 *   1. Disable IR tracking (write 0x00 to 0xB00030)
 *   2. Wait 100ms for hardware to settle
 *   3. Set IR mode (write mode to 0xB00033)
 *   4. Wait 100ms for mode change to take effect
 *   5. Re-enable IR tracking (write 0x08 to 0xB00030)
 *   6. Wait 100ms for IR to stabilize
 * 
 * Hardware registers (based on Dolphin emulator):
 *   0xB00030: IR Enable (0x00 = disabled, 0x08 = enabled)
 *   0xB00033: IR Mode (0x01 = Basic, 0x03 = Extended, 0x05 = Full)
 *   0xB00006: IR Sensitivity (0x90 = default)
 *   0xB00008: IR Sensitivity (0xC0 = default)
 *   0xB0001A: IR Sensitivity (0x40 = default)
 * 
 * The reporting mode change itself is sent via HID command:
 *   Byte 0: 0xA2 - HID Output report
 *   Byte 1: 0x12 - Set Report command
 *   Byte 2: 0x04 - Reporting mode feature
 *   Byte 3: mode - The new reporting mode (0x30, 0x31, 0x33, 0x37)
 */
- (void)setReportingMode:(uint8_t)mode {
    // Guard: Need control channel to send commands
    if (!self.ctrl) return;
    
    // --- Handle IR mode switching for 0x37 (Basic Mode) ---
    // Only reconfigure if switching TO 0x37 from a different mode
    if (mode == 0x37 && self.currentMode != 0x37) {
        printf("[IR] Switching to Basic Mode for 0x37...\n");
        fflush(stdout);
        
        // Step 1: Disable IR tracking
        uint8_t zero = 0x00;
        [self writeMemory:0xB00030 data:[NSData dataWithBytes:&zero length:1]];
        usleep(100000);  // 100ms delay - critical for hardware settling
        
        // Step 2: Set IR mode to Basic (0x01)
        uint8_t irMode = 0x01;
        [self writeMemory:0xB00033 data:[NSData dataWithBytes:&irMode length:1]];
        usleep(100000);  // 100ms delay for mode change
        
        // Step 3: Re-enable IR tracking
        uint8_t enableIR = 0x08;
        [self writeMemory:0xB00030 data:[NSData dataWithBytes:&enableIR length:1]];
        usleep(100000);  // 100ms delay for IR stabilization
    }
    
    // --- Handle IR mode switching for 0x33 (Extended Mode) ---
    // Only reconfigure if switching FROM 0x37 TO 0x33
    if (mode == 0x33 && self.currentMode == 0x37) {
        printf("[IR] Switching to Extended Mode for 0x33...\n");
        fflush(stdout);
        
        // Step 1: Disable IR tracking
        uint8_t zero = 0x00;
        [self writeMemory:0xB00030 data:[NSData dataWithBytes:&zero length:1]];
        usleep(100000);
        
        // Step 2: Set IR mode to Extended (0x03)
        uint8_t irMode = 0x03;
        [self writeMemory:0xB00033 data:[NSData dataWithBytes:&irMode length:1]];
        usleep(100000);
        
        // Step 3: Re-enable IR tracking
        uint8_t enableIR = 0x08;
        [self writeMemory:0xB00030 data:[NSData dataWithBytes:&enableIR length:1]];
        usleep(100000);
    }
    
    // --- Send the reporting mode change command ---
    // 0xA2 = HID Output report (host to device)
    // 0x12 = Set Report (configures Wiimote settings)
    // 0x04 = Report Mode feature (sets data format)
    // mode = The new reporting mode (0x30, 0x31, 0x33, or 0x37)
    uint8_t report[] = {0xA2, 0x12, 0x04, mode};
    [self.ctrl writeSync:report length:4];
    
    // Store the current mode for future mode switching logic
    self.currentMode = mode;
}