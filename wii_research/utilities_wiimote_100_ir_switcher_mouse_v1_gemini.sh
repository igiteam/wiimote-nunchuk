#!/bin/bash
# Wiimote - IR DEBUGGER WITH DYNAMIC MODE SWITCHING & QUARTZ MOUSE MOVEMENT

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║      WIIMOTE - DYNAMIC MODE SWITCHER & QUARTZ MOUSE MOVE       ║"
echo "║            HOT-SWAP REPORT MODES (1, 2, +, -, Home, A)        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

APP_NAME="Wiimote"
BUNDLE_ID="com.github.wiimote"

rm -rf "$APP_NAME"
mkdir -p "$APP_NAME"/src
cd "$APP_NAME" || exit

cat > "src/WiimoteManager.h" << 'EOF'
#import <Foundation/Foundation.h>

@interface WiimoteManager : NSObject
@property (nonatomic, assign) uint8_t currentMode;
- (void)start;
- (void)stop;
@end
EOF

cat > "src/WiimoteManager.m" << 'EOF'
#import "WiimoteManager.h"
#import <IOBluetooth/IOBluetooth.h>
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>

#define PSM_CTRL 0x11
#define PSM_INTR 0x13
#define MAX_RETRIES 5
#define RETRY_DELAY 2.0
#define INQUIRY_TIMEOUT 8.0

@interface WiimoteManager ()
@property (nonatomic, strong) IOBluetoothDeviceInquiry *inquiry;
@property (nonatomic, strong) IOBluetoothDevice *device;
@property (nonatomic, strong) IOBluetoothL2CAPChannel *ctrl;
@property (nonatomic, strong) IOBluetoothL2CAPChannel *intr;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) BOOL connecting;
@property (nonatomic, assign) BOOL connected;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) BOOL irBottom;
@property (nonatomic, assign) BOOL debugIR;
@property (nonatomic, assign) int sensitivityLevel;
@property (nonatomic, assign) int frameCount;
@property (nonatomic, assign) int batteryPercent;
@property (nonatomic, assign) BOOL statusHeaderShown;
@property (nonatomic, assign) int retryCount;
@property (nonatomic, strong) NSTimer *retryTimer;
@property (nonatomic, strong) NSTimer *inquiryTimer;
@property (nonatomic, assign) BOOL inquiryActive;
@property (nonatomic, assign) BOOL reconnecting;

// Button States
@property (nonatomic, assign) BOOL btnLeft, btnRight, btnDown, btnUp;
@property (nonatomic, assign) BOOL btnPlus, btnMinus, btnHome, btnA, btnB, btn1, btn2;

// IR properties
@property (nonatomic, assign) BOOL irEnabled;
@property (nonatomic, assign) int irX1, irY1, irX2, irY2, irX3, irY3, irX4, irY4;
@property (nonatomic, assign) int irSize1, irSize2, irSize3, irSize4;

// Mouse Tracking (Quartz)
@property (nonatomic, assign) CGFloat smoothedX;
@property (nonatomic, assign) CGFloat smoothedY;
@property (nonatomic, assign) BOOL hasSmoothedPos;
@property (nonatomic, assign) CGRect screenBounds;

// Extension
@property (nonatomic, assign) BOOL extInitialized;
@end

@implementation WiimoteManager

- (instancetype)init {
    self = [super init];
    if (self) {
        _running = NO;
        _connecting = NO;
        _connected = NO;
        _reconnecting = NO;
        _irBottom = YES;
        _debugIR = YES;
        _sensitivityLevel = 3;
        _frameCount = 0;
        _batteryPercent = 0;
        _statusHeaderShown = NO;
        _retryCount = 0;
        _retryTimer = nil;
        _inquiryTimer = nil;
        _inquiryActive = NO;
        _irEnabled = YES;
        _extInitialized = NO;
        _currentMode = 0x33; // Default to working mode (Buttons + Accel + 12-byte IR)
        
        _irX1 = _irY1 = _irX2 = _irY2 = _irX3 = _irY3 = _irX4 = _irY4 = -1;
        _irSize1 = _irSize2 = _irSize3 = _irSize4 = 0;

        _hasSmoothedPos = NO;
        _screenBounds = CGDisplayBounds(CGMainDisplayID());
        
        printf("[Wiimote] IR Switcher Init (Default Mode: 0x%02X)\n", _currentMode);
        fflush(stdout);
    }
    return self;
}

- (void)start {
    if (self.running) return;
    self.running = YES;
    self.reconnecting = NO;
    printf("[Wiimote] Starting...\n");
    fflush(stdout);
    
    [self cleanupStaleConnections];
    [self startDiscoveryWithRetry:NO];
}

- (void)cleanupStaleConnections {
    NSArray *devices = [IOBluetoothDevice pairedDevices];
    for (IOBluetoothDevice *dev in devices) {
        NSString *name = dev.name;
        if ([name containsString:@"Nintendo"] || [name containsString:@"RVL"]) {
            if (dev.isConnected) {
                [dev closeConnection];
                usleep(500000);
            }
            if ([dev respondsToSelector:@selector(removePairing)]) {
                [dev performSelector:@selector(removePairing)];
                usleep(500000);
            }
        }
    }
}

- (void)stop {
    self.running = NO;
    self.reconnecting = NO;
    [self.timer invalidate];
    self.timer = nil;
    [self.retryTimer invalidate];
    self.retryTimer = nil;
    [self.inquiryTimer invalidate];
    self.inquiryTimer = nil;
    self.inquiryActive = NO;
    [self disconnect];
    printf("[Wiimote] Stopped\n");
    fflush(stdout);
}

- (void)startDiscoveryWithRetry:(BOOL)isRetry {
    if (!self.running || self.connected) return;
    
    if (isRetry) {
        self.retryCount++;
        if (self.retryCount > MAX_RETRIES) {
            printf("[Wiimote] Max retries reached. Press Sync button or restart.\n");
            fflush(stdout);
            return;
        }
        self.retryTimer = [NSTimer scheduledTimerWithTimeInterval:RETRY_DELAY
                                                           target:self
                                                         selector:@selector(doDiscovery)
                                                         userInfo:nil
                                                          repeats:NO];
        return;
    }
    [self doDiscovery];
}

- (void)doDiscovery {
    if (!self.running || self.inquiryActive || self.connected) return;
    
    self.inquiryActive = YES;
    self.inquiry = [IOBluetoothDeviceInquiry inquiryWithDelegate:self];
    self.inquiry.inquiryLength = 10;
    self.inquiry.updateNewDeviceNames = YES;
    
    printf("[Wiimote] Press 1+2 on the Wiimote...\n");
    fflush(stdout);
    
    [self.inquiry start];
    
    [self.inquiryTimer invalidate];
    self.inquiryTimer = [NSTimer scheduledTimerWithTimeInterval:INQUIRY_TIMEOUT
                                                         target:self
                                                       selector:@selector(inquiryTimeout)
                                                       userInfo:nil
                                                        repeats:NO];
}

- (void)inquiryTimeout {
    if (!self.running || !self.inquiryActive || self.connected) return;
    [self.inquiry stop];
    self.inquiry = nil;
    self.inquiryActive = NO;
    [self startDiscoveryWithRetry:YES];
}

- (void)deviceInquiryDeviceFound:(IOBluetoothDeviceInquiry *)sender device:(IOBluetoothDevice *)device {
    NSString *name = device.name;
    if ([name containsString:@"Nintendo"] || [name containsString:@"RVL"]) {
        printf("[Wiimote] Found device: %s\n", [name UTF8String]);
        fflush(stdout);
        
        [self.inquiryTimer invalidate];
        self.inquiryTimer = nil;
        self.inquiryActive = NO;
        [sender stop];
        self.inquiry = nil;
        
        if (device.isConnected) {
            [device closeConnection];
            usleep(500000);
        }
        [self connectTo:device];
    }
}

- (void)deviceInquiryComplete:(IOBluetoothDeviceInquiry *)sender error:(IOReturn)error {
    self.inquiryActive = NO;
    [self.inquiryTimer invalidate];
    self.inquiryTimer = nil;
    self.inquiry = nil;
    
    if (error == kIOReturnSuccess && !self.connected) {
        [self startDiscoveryWithRetry:YES];
    }
}

- (void)connectTo:(IOBluetoothDevice *)device {
    if (self.connecting || self.connected) return;
    self.connecting = YES;
    self.device = device;
    printf("[Wiimote] Connecting...\n");
    fflush(stdout);
    
    IOBluetoothL2CAPChannel *c = nil;
    IOReturn r = [device openL2CAPChannelSync:&c withPSM:PSM_CTRL delegate:self];
    if (r == kIOReturnSuccess && c) {
        self.ctrl = c;
        uint8_t h[] = {0x43, 0x00};
        [self.ctrl writeSync:h length:2];
        usleep(100000);
        
        IOBluetoothL2CAPChannel *ic = nil;
        r = [device openL2CAPChannelSync:&ic withPSM:PSM_INTR delegate:self];
        if (r == kIOReturnSuccess && ic) {
            self.intr = ic;
            self.connecting = NO;
            self.connected = YES;
            self.reconnecting = NO;
            [self onConnected];
        } else {
            self.connecting = NO;
            [self connectionFailed];
        }
    } else {
        self.connecting = NO;
        [self connectionFailed];
    }
}

- (void)connectionFailed {
    self.connected = NO;
    [self disconnect];
    usleep(50000);
    [self startDiscoveryWithRetry:YES];
}

- (void)onConnected {
    printf("\n[Wiimote] CONNECTED SUCCESSFULLY!\n");
    fflush(stdout);
    
    [self setLED:0x10];
    usleep(50000);
    
    [self setRumble:YES];
    usleep(200000);
    [self setRumble:NO];
    
    // Configure initial reporting mode
    [self setReportingMode:self.currentMode];
    usleep(50000);
    
    // Enable IR Camera
    if (self.irEnabled) {
        printf("[IR] Initializing IR Camera...\n");
        uint8_t irEnable[] = {0xA2, 0x13, 0x06};
        [self.ctrl writeSync:irEnable length:3];
        usleep(50000);
        
        uint8_t irEnable2[] = {0xA2, 0x1A, 0x06};
        [self.ctrl writeSync:irEnable2 length:3];
        usleep(50000);
        
        [self initIR];
    }
    
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.05
                                                   target:self
                                                 selector:@selector(pollStatus)
                                                 userInfo:nil
                                                  repeats:YES];
}

- (void)initIR {
    // 1. Enable IR Block
    [self writeMemory:0xB00030 data:[NSData dataWithBytes:"\x01" length:1]];
    usleep(50000);
    
    // 2. Write Sensitivity Blocks (Level 3)
    uint8_t block1[] = {0x02, 0x00, 0x00, 0x71, 0x01, 0x00, 0xAA, 0x00, 0x64};
    uint8_t block2[] = {0x63, 0x03};
    [self writeMemory:0xB00000 data:[NSData dataWithBytes:block1 length:9]];
    usleep(50000);
    [self writeMemory:0xB0001A data:[NSData dataWithBytes:block2 length:2]];
    usleep(50000);
    
    // 3. Mode 0x03 -> EXTENDED MODE (12 bytes IR format)
    uint8_t irMode = 0x03;
    [self writeMemory:0xB00033 data:[NSData dataWithBytes:&irMode length:1]];
    usleep(50000);
    
    // 4. Enable IR with Extended Mode
    [self writeMemory:0xB00030 data:[NSData dataWithBytes:"\x08" length:1]];
    usleep(50000);
    
    // 5. Init Extension
    [self initExtension];
    usleep(50000);
    
    // 6. Set mode
    [self setReportingMode:self.currentMode];
    
    printf("============================================================\n");
    printf("🎮 WIIMOTE READY FOR MODE SWITCHING & QUARTZ MOUSE MOVE!\n");
    printf("   Press 1    → Mode 0x30 (Buttons)\n");
    printf("   Press 2    → Mode 0x31 (Buttons + Accel)\n");
    printf("   Press +    → Mode 0x33 (Buttons + Accel + Extended IR)\n");
    printf("   Press -    → Mode 0x37 (Buttons + Accel + IR + Extension)\n");
    printf("   Press Home → Toggle IR Inversion\n");
    printf("   Press A    → Toggle Debug Prints\n");
    printf("============================================================\n\n");
    fflush(stdout);
}

- (void)initExtension {
    if (self.extInitialized) return;
    [self writeMemory:0xA40040 data:[NSData dataWithBytes:"\x00" length:1]];
    usleep(50000);
    uint8_t key[16] = {0};
    [self writeMemory:0xA40040 data:[NSData dataWithBytes:key length:16]];
    usleep(50000);
    [self writeMemory:0xA400F0 data:[NSData dataWithBytes:"\x55" length:1]];
    usleep(50000);
    self.extInitialized = YES;
}

- (void)pollStatus {
    if (!self.connected) {
        [self reconnect];
        return;
    }
    [self requestStatus];
}

- (void)reconnect {
    if (self.reconnecting || self.connected) return;
    self.reconnecting = YES;
    [self disconnect];
    [self startDiscoveryWithRetry:NO];
}

- (void)writeMemory:(uint32_t)address data:(NSData *)data {
    if (!self.ctrl || data.length > 16) return;
    
    NSMutableData *report = [NSMutableData data];
    uint8_t flags = 0x04;
    [report appendBytes:&flags length:1];
    
    uint8_t addrBytes[3] = {
        (uint8_t)((address >> 16) & 0xFF),
        (uint8_t)((address >> 8) & 0xFF),
        (uint8_t)(address & 0xFF)
    };
    [report appendBytes:addrBytes length:3];
    
    uint8_t size = (uint8_t)(data.length & 0x0F);
    [report appendBytes:&size length:1];
    [report appendData:data];
    
    NSUInteger padding = 16 - data.length;
    for (int i = 0; i < padding; i++) {
        uint8_t zero = 0x00;
        [report appendBytes:&zero length:1];
    }
    
    [self sendOutputReport:0x16 dataWithData:report];
}

- (void)sendOutputReport:(uint8_t)reportID dataWithData:(NSData *)data {
    if (!self.ctrl) return;
    NSMutableData *report = [NSMutableData data];
    uint8_t header = 0xA2;
    [report appendBytes:&header length:1];
    [report appendBytes:&reportID length:1];
    [report appendData:data];
    
    if (report.length < 21) {
        uint8_t padding[21] = {0};
        [report appendBytes:padding length:21 - report.length];
    }
    [self.ctrl writeSync:(void *)report.bytes length:report.length];
}

- (void)setLED:(int)mask {
    uint8_t led[] = {0xA2, 0x11, (uint8_t)mask};
    [self.ctrl writeSync:led length:3];
}

- (void)setReportingMode:(uint8_t)mode {
    if (!self.ctrl) return;
    
    // If switching to mode 0x37, switch IR to Basic Mode (0x01)
    if (mode == 0x37 && self.currentMode != 0x37) {
        printf("[IR] Switching to Basic Mode for 0x37...\n");
        fflush(stdout);
        
        // Disable IR: write 0x00 to 0xB00030
        uint8_t zero = 0x00;
        [self writeMemory:0xB00030 data:[NSData dataWithBytes:&zero length:1]];
        usleep(100000);
        
        // Set IR mode to Basic (0x01) at 0xB00033
        uint8_t irMode = 0x01;
        [self writeMemory:0xB00033 data:[NSData dataWithBytes:&irMode length:1]];
        usleep(100000);
        
        // Re-enable IR: write 0x08 to 0xB00030
        uint8_t enableIR = 0x08;
        [self writeMemory:0xB00030 data:[NSData dataWithBytes:&enableIR length:1]];
        usleep(100000);
    }
    
    // If switching TO mode 0x33 FROM mode 0x37, switch IR to Extended Mode (0x03)
    if (mode == 0x33 && self.currentMode == 0x37) {
        printf("[IR] Switching to Extended Mode for 0x33...\n");
        fflush(stdout);
        
        // Disable IR: write 0x00 to 0xB00030
        uint8_t zero = 0x00;
        [self writeMemory:0xB00030 data:[NSData dataWithBytes:&zero length:1]];
        usleep(100000);
        
        // Set IR mode to Extended (0x03) at 0xB00033
        uint8_t irMode = 0x03;
        [self writeMemory:0xB00033 data:[NSData dataWithBytes:&irMode length:1]];
        usleep(100000);
        
        // Re-enable IR: write 0x08 to 0xB00030
        uint8_t enableIR = 0x08;
        [self writeMemory:0xB00030 data:[NSData dataWithBytes:&enableIR length:1]];
        usleep(100000);
    }
    
    // Send the reporting mode change
    uint8_t report[] = {0xA2, 0x12, 0x04, mode};
    [self.ctrl writeSync:report length:4];
    self.currentMode = mode;
}

- (void)requestStatus {
    if (!self.ctrl) return;
    uint8_t status[] = {0xA2, 0x15, 0x00};
    [self.ctrl writeSync:status length:3];
}

- (void)setRumble:(BOOL)enable {
    if (!self.ctrl) return;
    uint8_t rumble[] = {0xA2, 0x10, (uint8_t)(enable ? 0x01 : 0x00)};
    [self.ctrl writeSync:rumble length:3];
}

- (void)updateQuartzMousePosition {
    if (self.irX1 < 0 || self.irY1 < 0) {
        self.hasSmoothedPos = NO;
        return;
    }

    // Wiimote IR area bounds (1023 x 767)
    // Reverse X so pointing right moves cursor right
    CGFloat normX = 1.0 - ((CGFloat)self.irX1 / 1023.0);
    CGFloat normY = (CGFloat)self.irY1 / 767.0;

    // Clamp values between 0.0 and 1.0
    normX = MIN(MAX(normX, 0.0), 1.0);
    normY = MIN(MAX(normY, 0.0), 1.0);

    CGFloat targetX = self.screenBounds.origin.x + (normX * self.screenBounds.size.width);
    CGFloat targetY = self.screenBounds.origin.y + (normY * self.screenBounds.size.height);

    // Apply Exponential Low-Pass Filter for smooth tracking
    if (!self.hasSmoothedPos) {
        self.smoothedX = targetX;
        self.smoothedY = targetY;
        self.hasSmoothedPos = YES;
    } else {
        CGFloat alpha = 0.35; // Smoothing factor
        self.smoothedX = self.smoothedX + alpha * (targetX - self.smoothedX);
        self.smoothedY = self.smoothedY + alpha * (targetY - self.smoothedY);
    }

    CGPoint newPoint = CGPointMake(self.smoothedX, self.smoothedY);

    // Move cursor using Quartz CoreGraphics
    CGWarpMouseCursorPosition(newPoint);
    
    // Post OS event so hover effects and UI track smoothly
    CGEventRef moveEvent = CGEventCreateMouseEvent(
        NULL,
        kCGEventMouseMoved,
        newPoint,
        kCGMouseButtonLeft
    );
    if (moveEvent) {
        CGEventPost(kCGHIDEventTap, moveEvent);
        CFRelease(moveEvent);
    }
}

- (void)performMouseClick:(int)buttonNumber withRumble:(BOOL)rumble {
    // Rumble feedback
    if (rumble) {
        [self setRumble:YES];
        usleep(100000);
        [self setRumble:NO];
    }
    
    // Get current mouse position
    CGEventRef event = CGEventCreate(NULL);
    CGPoint currentPos = CGEventGetLocation(event);
    CFRelease(event);
    
    // Create mouse down event
    CGEventRef mouseDown = CGEventCreateMouseEvent(
        NULL,
        buttonNumber == kCGMouseButtonLeft ? kCGEventLeftMouseDown : kCGEventRightMouseDown,
        currentPos,
        buttonNumber
    );
    
    // Create mouse up event
    CGEventRef mouseUp = CGEventCreateMouseEvent(
        NULL,
        buttonNumber == kCGMouseButtonLeft ? kCGEventLeftMouseUp : kCGEventRightMouseUp,
        currentPos,
        buttonNumber
    );
    
    // Post the events
    if (mouseDown) {
        CGEventPost(kCGHIDEventTap, mouseDown);
        CFRelease(mouseDown);
    }
    
    if (mouseUp) {
        CGEventPost(kCGHIDEventTap, mouseUp);
        CFRelease(mouseUp);
    }
    
    // Small delay between clicks
    usleep(50000);
}

- (void)parseWiimoteButtons:(uint8_t *)data {
    static BOOL prevBtn1 = NO, prevBtn2 = NO, prevBtnPlus = NO, prevBtnMinus = NO;
    static BOOL prevBtnHome = NO, prevBtnA = NO, prevBtnB = NO;  // Added prevBtnB

    self.btnLeft   = (data[0] & 0x01) != 0;
    self.btnRight  = (data[0] & 0x02) != 0;
    self.btnDown   = (data[0] & 0x04) != 0;
    self.btnUp     = (data[0] & 0x08) != 0;
    self.btnPlus   = (data[0] & 0x10) != 0;

    self.btn2      = (data[1] & 0x01) != 0;
    self.btn1      = (data[1] & 0x02) != 0;
    self.btnB      = (data[1] & 0x04) != 0;
    self.btnA      = (data[1] & 0x08) != 0;
    self.btnMinus  = (data[1] & 0x10) != 0;
    self.btnHome   = (data[1] & 0x80) != 0;

    // BUTTON 1: Mode 0x30
    if (self.btn1 && !prevBtn1) {
        [self setReportingMode:0x30];
        printf("\n🔄 Switched to Mode: 0x30 (Buttons Only)\n");
        fflush(stdout);
        [self setRumble:YES]; usleep(100000); [self setRumble:NO];
    }
    prevBtn1 = self.btn1;

    // BUTTON 2: Mode 0x31
    if (self.btn2 && !prevBtn2) {
        [self setReportingMode:0x31];
        printf("\n🔄 Switched to Mode: 0x31 (Buttons + Accel)\n");
        fflush(stdout);
        [self setRumble:YES]; usleep(100000); [self setRumble:NO];
    }
    prevBtn2 = self.btn2;

    // PLUS: Mode 0x33
    if (self.btnPlus && !prevBtnPlus) {
        [self setReportingMode:0x33];
        printf("\n🔄 Switched to Mode: 0x33 (Buttons + Accel + 12-byte IR)\n");
        fflush(stdout);
        [self setRumble:YES]; usleep(200000); [self setRumble:NO];
    }
    prevBtnPlus = self.btnPlus;

    // MINUS: Mode 0x37
    if (self.btnMinus && !prevBtnMinus) {
        [self setReportingMode:0x37];
        printf("\n🔄 Switched to Mode: 0x37 (Buttons + Accel + 12-byte IR + Extension)\n");
        fflush(stdout);
        [self setRumble:YES]; usleep(200000); [self setRumble:NO];
    }
    prevBtnMinus = self.btnMinus;

    // HOME: Toggle IR Flip
    if (self.btnHome && !prevBtnHome) {
        self.irBottom = !self.irBottom;
        printf("\n🔄 IR Y-Inversion: %s\n", self.irBottom ? "YES" : "NO");
        fflush(stdout);
        [self setRumble:YES]; usleep(150000); [self setRumble:NO];
    }
    prevBtnHome = self.btnHome;

    // A: Left Mouse Click with Rumble
    if (self.btnA && !prevBtnA) {
        printf("\n🖱️ Left Mouse Click (A Button)\n");
        fflush(stdout);
        [self performMouseClick:kCGMouseButtonLeft withRumble:YES];
    }
    prevBtnA = self.btnA;

    // B: Right Mouse Click with Rumble
    if (self.btnB && !prevBtnB) {
        printf("\n🖱️ Right Mouse Click (B Button)\n");
        fflush(stdout);
        [self performMouseClick:kCGMouseButtonRight withRumble:YES];
    }
    prevBtnB = self.btnB;
}

- (void)parseExtendedIRData:(uint8_t *)irData length:(int)irLength {
    if (!self.irEnabled) return;
    
    BOOL hasData = NO;
    for (int i = 0; i < irLength; i++) {
        if (irData[i] != 0xFF) { hasData = YES; break; }
    }
    
    if (!hasData) {
        self.irX1 = self.irX2 = self.irX3 = self.irX4 = -1;
        self.irY1 = self.irY2 = self.irY3 = self.irY4 = -1;
        [self updateQuartzMousePosition];
        return;
    }

    // Extended Mode Parsing (12 bytes for 4 objects -> 3 bytes per object)
    // Object 1
    if (irData[0] != 0xFF || irData[1] != 0xFF) {
        uint16_t x = irData[0] | ((irData[2] & 0x30) << 4);
        uint16_t y = irData[1] | ((irData[2] & 0xC0) << 2);
        self.irX1 = x;
        self.irY1 = y;
        self.irSize1 = irData[2] & 0x0F;
    } else { self.irX1 = -1; self.irY1 = -1; }

    // Object 2
    if (irData[3] != 0xFF || irData[4] != 0xFF) {
        uint16_t x = irData[3] | ((irData[5] & 0x30) << 4);
        uint16_t y = irData[4] | ((irData[5] & 0xC0) << 2);
        self.irX2 = x;
        self.irY2 = y;
        self.irSize2 = irData[5] & 0x0F;
    } else { self.irX2 = -1; self.irY2 = -1; }

    // Object 3
    if (irData[6] != 0xFF || irData[7] != 0xFF) {
        uint16_t x = irData[6] | ((irData[8] & 0x30) << 4);
        uint16_t y = irData[7] | ((irData[8] & 0xC0) << 2);
        self.irX3 = x;
        self.irY3 = y;
        self.irSize3 = irData[8] & 0x0F;
    } else { self.irX3 = -1; self.irY3 = -1; }

    // Object 4
    if (irData[9] != 0xFF || irData[10] != 0xFF) {
        uint16_t x = irData[9] | ((irData[11] & 0x30) << 4);
        uint16_t y = irData[10] | ((irData[11] & 0xC0) << 2);
        self.irX4 = x;
        self.irY4 = y;
        self.irSize4 = irData[11] & 0x0F;
    } else { self.irX4 = -1; self.irY4 = -1; }

    // Update system pointer position using Quartz
    [self updateQuartzMousePosition];

    self.frameCount++;

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

- (void)parseBasicIRData:(uint8_t *)irData length:(int)irLength {
    if (!self.irEnabled) return;
    
    // Check for invalid data
    BOOL hasData = NO;
    for (int i = 0; i < irLength; i++) {
        if (irData[i] != 0xFF) { hasData = YES; break; }
    }
    
    if (!hasData) {
        self.irX1 = self.irX2 = self.irX3 = self.irX4 = -1;
        self.irY1 = self.irY2 = self.irY3 = self.irY4 = -1;
        [self updateQuartzMousePosition];
        return;
    }

    // CORRECT Basic Mode parsing based on Dolphin's IRBasic struct
    
    // Object 1 - uses x1hi (bits 4-5) and y1hi (bits 6-7)
    if (irData[0] != 0xFF || irData[1] != 0xFF) {
        uint16_t x = irData[0] | ((irData[2] & 0x30) << 4);  // 0x30 << 4 = 0x300
        uint16_t y = irData[1] | ((irData[2] & 0xC0) << 2);  // 0xC0 << 2 = 0x300
        self.irX1 = x;
        self.irY1 = y;
        self.irSize1 = 0;
    } else {
        self.irX1 = -1;
        self.irY1 = -1;
    }

    // Object 2 - uses x2hi (bits 0-1) and y2hi (bits 2-3)
    if (irData[3] != 0xFF || irData[4] != 0xFF) {
        uint16_t x = irData[3] | ((irData[2] & 0x03) << 8);  // 0x03 << 8 = 0x300
        uint16_t y = irData[4] | ((irData[2] & 0x0C) << 6);  // 0x0C << 6 = 0x300
        self.irX2 = x;
        self.irY2 = y;
        self.irSize2 = 0;
    } else {
        self.irX2 = -1;
        self.irY2 = -1;
    }

    // Object 3 - uses x1hi (bits 4-5) and y1hi (bits 6-7) of byte7
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

    // Object 4 - uses x2hi (bits 0-1) and y2hi (bits 2-3) of byte7
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

    if (self.debugIR) {
        printf("[IR Basic Parsed] P1:(%d,%d) P2:(%d,%d) P3:(%d,%d) P4:(%d,%d)\n", 
               self.irX1, self.irY1, self.irX2, self.irY2, 
               self.irX3, self.irY3, self.irX4, self.irY4);
        fflush(stdout);
    }

    // Use P1 and P2 for mouse tracking (the sensor bar dots)
    [self updateQuartzMousePosition];

    self.frameCount++;
}

- (void)l2capChannelData:(IOBluetoothL2CAPChannel *)ch data:(void *)dp length:(size_t)len {
    uint8_t *d = (uint8_t *)dp;
    if (len < 2 || d[0] != 0xA1) return;

    uint8_t reportID = d[1];
    uint8_t *payload = d + 2;

    // Parse button updates across all report modes
    if (len >= 4) {
        [self parseWiimoteButtons:payload];
    }

    // Parse Extended IR depending on active mode offsets
    if (reportID == 0x33 && len >= 17) {
        // Mode 0x33: 2-byte Buttons + 3-byte Accel + 12-byte Extended IR
        [self parseExtendedIRData:payload + 5 length:12];
    } else if (reportID == 0x37 && len >= 21) {
        // Mode 0x37: 2-byte Buttons + 3-byte Accel + 10-byte Basic IR + 6-byte Extension
        [self parseBasicIRData:payload + 5 length:10];
    } else if (reportID == 0x20 && len >= 8) {
        self.batteryPercent = (payload[5] * 100) / 0xC0;
    }
}

- (void)disconnect {
    self.connected = NO;
    self.connecting = NO;
    self.extInitialized = NO;
    
    if (self.ctrl) { [self setRumble:NO]; [self.ctrl closeChannel]; self.ctrl = nil; }
    if (self.intr) { [self.intr closeChannel]; self.intr = nil; }
    if (self.device) { [self.device closeConnection]; self.device = nil; }
}

- (void)dealloc {
    [self disconnect];
}
@end
EOF

cat > "src/AppDelegate.h" << 'EOF'
#import <Cocoa/Cocoa.h>
@interface AppDelegate : NSObject <NSApplicationDelegate>
@end
EOF

cat > "src/AppDelegate.m" << 'EOF'
#import "AppDelegate.h"
#import "WiimoteManager.h"

@interface AppDelegate ()
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) WiimoteManager *wiimoteManager;
@property (nonatomic, strong) NSMenuItem *toggleMenuItem;
@property (nonatomic, assign) BOOL isActive;
@end

@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    self.wiimoteManager = [[WiimoteManager alloc] init];
    self.isActive = NO;
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.title = @"🎮";
    
    NSMenu *menu = [[NSMenu alloc] init];
    self.toggleMenuItem = [[NSMenuItem alloc] initWithTitle:@"Start Wiimote"
                                                      action:@selector(toggleWiimote:)
                                               keyEquivalent:@"s"];
    self.toggleMenuItem.target = self;
    [menu addItem:self.toggleMenuItem];
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit"
                                                       action:@selector(quitApp:)
                                                keyEquivalent:@"q"];
    quitItem.target = self;
    [menu addItem:quitItem];
    self.statusItem.menu = menu;
    
    [self performSelector:@selector(autoStart) withObject:nil afterDelay:0.5];
}

- (void)autoStart {
    self.isActive = YES;
    [self.wiimoteManager start];
    self.toggleMenuItem.title = @"Stop Wiimote";
}

- (void)toggleWiimote:(id)sender {
    self.isActive = !self.isActive;
    if (self.isActive) {
        [self.wiimoteManager start];
        self.toggleMenuItem.title = @"Stop Wiimote";
    } else {
        [self.wiimoteManager stop];
        self.toggleMenuItem.title = @"Start Wiimote";
    }
}

- (void)quitApp:(id)sender {
    [self.wiimoteManager stop];
    [NSApp terminate:nil];
}
@end
EOF

cat > "src/main.m" << 'EOF'
#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"
int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
EOF

# Build & Package Execution
echo -e "${CYAN}🔨 Compiling App Bundle with Quartz CoreGraphics support...${NC}"

APP_BUNDLE="$APP_NAME.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/"{MacOS,Resources}

cat > "Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Wiimote needs Bluetooth</string>
</dict>
</plist>
EOF

cp "Info.plist" "$APP_BUNDLE/Contents/"

clang -framework Cocoa -framework Foundation -framework AppKit -framework CoreGraphics -framework IOBluetooth -framework Carbon -fobjc-arc -Wno-deprecated-declarations -mmacosx-version-min=11.0 -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" src/*.m 2> build_errors.log

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Compilation successful!${NC}"
else
    echo -e "${RED}❌ Compilation failed:${NC}"
    cat build_errors.log
    exit 1
fi

codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true
xattr -cr "$APP_BUNDLE"

cp -R "$APP_BUNDLE" "$HOME/Applications/" 2>/dev/null || true
cp -R "$APP_BUNDLE" "$HOME/Desktop/" 2>/dev/null || true

echo -e "\n${GREEN}🚀 Application compiled and ready with Quartz Mouse Support!${NC}"
echo -e "${CYAN}Run directly with:${NC}"
echo -e "   $APP_BUNDLE/Contents/MacOS/$APP_NAME\n"