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

@property (nonatomic, assign) int battery;
@property (nonatomic, assign) int batteryRaw;



// IR properties
@property (nonatomic, assign) BOOL irEnabled;
@property (nonatomic, assign) int irX1, irY1, irX2, irY2, irX3, irY3, irX4, irY4;
@property (nonatomic, assign) int irSize1, irSize2, irSize3, irSize4;

// Mouse Tracking (Quartz)
@property (nonatomic, assign) CGFloat smoothedX;
@property (nonatomic, assign) CGFloat smoothedY;
@property (nonatomic, assign) BOOL hasSmoothedPos;
@property (nonatomic, assign) CGRect screenBounds;

// Last display to prevent flicker
@property (nonatomic, strong) NSString *lastDisplay;

// Wiimote Button States
@property (nonatomic, assign) BOOL btnLeft, btnRight, btnDown, btnUp;
@property (nonatomic, assign) BOOL btnPlus, btnMinus, btnHome, btnA, btnB, btn1, btn2;

// Wiimote Button Long Press Tracking
@property (nonatomic, assign) NSTimeInterval btn1PressTime;
@property (nonatomic, assign) BOOL btn1WasPressed;
@property (nonatomic, assign) BOOL btn1Handled;

@property (nonatomic, assign) NSTimeInterval btn2PressTime;
@property (nonatomic, assign) BOOL btn2WasPressed;
@property (nonatomic, assign) BOOL btn2Handled;

@property (nonatomic, assign) NSTimeInterval btnAPressTime;
@property (nonatomic, assign) BOOL btnAWasPressed;
@property (nonatomic, assign) BOOL btnAHandled;

@property (nonatomic, assign) NSTimeInterval btnBPressTime;
@property (nonatomic, assign) BOOL btnBWasPressed;
@property (nonatomic, assign) BOOL btnBHandled;

@property (nonatomic, assign) NSTimeInterval btnHomePressTime;
@property (nonatomic, assign) BOOL btnHomeWasPressed;
@property (nonatomic, assign) BOOL btnHomeHandled;

@property (nonatomic, assign) NSTimeInterval btnPlusPressTime;
@property (nonatomic, assign) BOOL btnPlusWasPressed;
@property (nonatomic, assign) BOOL btnPlusHandled;

@property (nonatomic, assign) NSTimeInterval btnMinusPressTime;
@property (nonatomic, assign) BOOL btnMinusWasPressed;
@property (nonatomic, assign) BOOL btnMinusHandled;

@property (nonatomic, assign) NSTimeInterval btnLeftPressTime;
@property (nonatomic, assign) BOOL btnLeftWasPressed;
@property (nonatomic, assign) BOOL btnLeftHandled;

@property (nonatomic, assign) NSTimeInterval btnRightPressTime;
@property (nonatomic, assign) BOOL btnRightWasPressed;
@property (nonatomic, assign) BOOL btnRightHandled;

@property (nonatomic, assign) NSTimeInterval btnUpPressTime;
@property (nonatomic, assign) BOOL btnUpWasPressed;
@property (nonatomic, assign) BOOL btnUpHandled;

@property (nonatomic, assign) NSTimeInterval btnDownPressTime;
@property (nonatomic, assign) BOOL btnDownWasPressed;
@property (nonatomic, assign) BOOL btnDownHandled;

// Nunchuk Button States
@property (nonatomic, assign) BOOL cPressed;
@property (nonatomic, assign) BOOL zPressed;

// Nunchuk Button Long Press Tracking
@property (nonatomic, assign) NSTimeInterval cPressTime;
@property (nonatomic, assign) BOOL cWasPressed;
@property (nonatomic, assign) BOOL cHandled;

@property (nonatomic, assign) NSTimeInterval zPressTime;
@property (nonatomic, assign) BOOL zWasPressed;
@property (nonatomic, assign) BOOL zHandled;

// Extension
@property (nonatomic, assign) int statusCount;
@property (nonatomic, assign) int lf;
@property (nonatomic, assign) BOOL extConnected;
@property (nonatomic, assign) BOOL extInitialized;
@property (nonatomic, assign) int joyX, joyY;
@property (nonatomic, assign) int joyXCenter;
@property (nonatomic, assign) int joyYCenter;
@property (nonatomic, assign) BOOL calibrated;
@property (nonatomic, assign) int calSamples;
@property (nonatomic, assign) int calXSum;
@property (nonatomic, assign) int calYSum;
@property (nonatomic, assign) BOOL calibrating;
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
        _battery = 0;
        _batteryRaw = 0;
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
    printf("\n========== INIT NUNCHUK ==========\n");
    fflush(stdout);
    
    // Disable encryption
    [self writeMemory:0xA40040 data:[NSData dataWithBytes:"\x00" length:1]];
    usleep(50000);
    
    // Write encryption key
    uint8_t key[] = {0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 
                     0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00};
    [self writeMemory:0xA40040 data:[NSData dataWithBytes:key length:16]];
    usleep(50000);
    
    // Enable extension
    [self writeMemory:0xA400F0 data:[NSData dataWithBytes:"\x55" length:1]];
    usleep(50000);
    
    // Force mode 0x37 to enable extension data
    [self setReportingMode:0x37];
    usleep(50000);
    
    [self requestStatus];
    
    self.extInitialized = YES;
    printf("[INIT] Nunchuk init complete - Ready for mode switching\n");
    printf("   Mode 0x33: Extended IR (12-byte) - No Extension\n");
    printf("   Mode 0x37: Basic IR (10-byte) + Extension\n");
    printf("==================================\n\n");
    fflush(stdout);
}

- (NSString *)buttonString {
    NSMutableString *str = [NSMutableString string];
    if (self.btnA) [str appendString:@"A"];
    if (self.btnB) [str appendString:@"B"];
    if (self.btn1) [str appendString:@"1"];
    if (self.btn2) [str appendString:@"2"];
    if (self.btnPlus) [str appendString:@"+"];
    if (self.btnMinus) [str appendString:@"-"];
    if (self.btnHome) [str appendString:@"H"];
    if (self.btnUp) [str appendString:@"↑"];
    if (self.btnDown) [str appendString:@"↓"];
    if (self.btnLeft) [str appendString:@"←"];
    if (self.btnRight) [str appendString:@"→"];
    if (str.length == 0) [str appendString:@"-"];
    return str;
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

- (void)simulateKeyPress:(CGKeyCode)keyCode down:(BOOL)down {
    [self simulateKeyPress:keyCode down:down withRumble:NO];
}

- (void)simulateKeyPress:(CGKeyCode)keyCode down:(BOOL)down withRumble:(BOOL)withRumble {
    // Rumble feedback if requested
    if (withRumble && down) {
        [self setRumble:YES];
        usleep(50000);  // 50ms rumble
        [self setRumble:NO];
    }
    
    // Send the key event
    CGEventRef event = CGEventCreateKeyboardEvent(NULL, keyCode, down);
    if (event) {
        CGEventPost(kCGHIDEventTap, event);
        CFRelease(event);
    }
}

- (void)centerMouse {
    // Get the main display bounds
    CGRect screenBounds = CGDisplayBounds(CGMainDisplayID());
    
    // Calculate center point
    CGPoint centerPoint = CGPointMake(
        screenBounds.origin.x + screenBounds.size.width / 2,
        screenBounds.origin.y + screenBounds.size.height / 2
    );
    
    // Move cursor using Quartz
    CGWarpMouseCursorPosition(centerPoint);
    
    // Post OS event so hover effects and UI track smoothly
    CGEventRef moveEvent = CGEventCreateMouseEvent(
        NULL,
        kCGEventMouseMoved,
        centerPoint,
        kCGMouseButtonLeft
    );
    if (moveEvent) {
        CGEventPost(kCGHIDEventTap, moveEvent);
        CFRelease(moveEvent);
    }
    
    printf("\n🎯 Mouse centered at (%.0f, %.0f)\n", centerPoint.x, centerPoint.y);
    fflush(stdout);
}

- (void)parseWiimoteButtons:(uint8_t *)data {
    static BOOL prevBtn1 = NO, prevBtn2 = NO;
    static BOOL prevBtnPlus = NO, prevBtnMinus = NO;
    static BOOL prevBtnHome = NO, prevBtnA = NO, prevBtnB = NO;
    static BOOL prevBtnUp = NO, prevBtnDown = NO, prevBtnLeft = NO, prevBtnRight = NO;
    
    // Read current button states
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
    
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    const NSTimeInterval LONG_PRESS_THRESHOLD = 0.5; // 500ms
    
    // ============================================
    // BUTTON 1: Short = key_w (Watch), Long = key_n (Nightvision hold)
    // ============================================
    if (self.btn1 && !prevBtn1) {
        self.btn1PressTime = now;
        self.btn1Handled = NO;
        self.btn1WasPressed = YES;
    } else if (self.btn1 && self.btn1WasPressed && !self.btn1Handled) {
        NSTimeInterval duration = now - self.btn1PressTime;
        if (duration >= LONG_PRESS_THRESHOLD) {
            // LONG PRESS: HOLD key_n (Nightvision)
            printf("\n🌙 Nightvision ON (1 Hold)\n");
            fflush(stdout);
            [self simulateKeyPress:0x2D down:YES withRumble:YES]; // N down (hold)
            self.btn1Handled = YES;
        }
    } else if (!self.btn1 && self.btn1WasPressed) {
        if (!self.btn1Handled) {
            // SHORT PRESS: key_w (Watch)
            printf("\n⌚ Watch (1 Short)\n");
            fflush(stdout);
            [self simulateKeyPress:0x0D down:YES withRumble:YES]; // W down
            usleep(50000);
            [self simulateKeyPress:0x0D down:NO withRumble:NO];   // W up
        } else {
            // Release N from long press
            [self simulateKeyPress:0x2D down:NO withRumble:NO];   // N up
            printf("🌙 Nightvision OFF\n");
            fflush(stdout);
        }
        self.btn1WasPressed = NO;
        self.btn1Handled = NO;
    }
    prevBtn1 = self.btn1;
    
    // ============================================
    // BUTTON 2: Short = key_g (Compass), Long = key_f (Flashlight hold)
    // ============================================
    if (self.btn2 && !prevBtn2) {
        self.btn2PressTime = now;
        self.btn2Handled = NO;
        self.btn2WasPressed = YES;
    } else if (self.btn2 && self.btn2WasPressed && !self.btn2Handled) {
        NSTimeInterval duration = now - self.btn2PressTime;
        if (duration >= LONG_PRESS_THRESHOLD) {
            // LONG PRESS: HOLD key_f (Flashlight)
            printf("\n🔦 Flashlight ON (2 Hold)\n");
            fflush(stdout);
            [self simulateKeyPress:0x03 down:YES withRumble:YES]; // F down (hold)
            self.btn2Handled = YES;
        }
    } else if (!self.btn2 && self.btn2WasPressed) {
        if (!self.btn2Handled) {
            // SHORT PRESS: key_g (Compass)
            printf("\n🧭 Compass (2 Short)\n");
            fflush(stdout);
            [self simulateKeyPress:0x05 down:YES withRumble:YES]; // G down
            usleep(50000);
            [self simulateKeyPress:0x05 down:NO withRumble:NO];   // G up
        } else {
            // Release F from long press
            [self simulateKeyPress:0x03 down:NO withRumble:NO];   // F up
            printf("🔦 Flashlight OFF\n");
            fflush(stdout);
        }
        self.btn2WasPressed = NO;
        self.btn2Handled = NO;
    }
    prevBtn2 = self.btn2;
    
    // ============================================
    // PLUS: Short = Toggle IR Debug, Long = nothing
    // ============================================
    if (self.btnPlus && !prevBtnPlus) {
        self.btnPlusPressTime = now;
        self.btnPlusHandled = NO;
        self.btnPlusWasPressed = YES;
    } else if (self.btnPlus && self.btnPlusWasPressed && !self.btnPlusHandled) {
        NSTimeInterval duration = now - self.btnPlusPressTime;
        if (duration >= LONG_PRESS_THRESHOLD) {
            // LONG PRESS: Do nothing
            self.btnPlusHandled = YES;
        }
    } else if (!self.btnPlus && self.btnPlusWasPressed) {
        if (!self.btnPlusHandled) {
            // SHORT PRESS: Toggle IR Debug
            self.debugIR = !self.debugIR;
            printf("\n🔍 IR Debug: %s\n", self.debugIR ? "ON" : "OFF");
            fflush(stdout);
            [self setRumble:YES]; usleep(100000); [self setRumble:NO];
        }
        self.btnPlusWasPressed = NO;
        self.btnPlusHandled = NO;
    }
    prevBtnPlus = self.btnPlus;
    
    // ============================================
    // MINUS: Short = Center Mouse, Long = key_~ (Tactical view hold)
    // ============================================
    if (self.btnMinus && !prevBtnMinus) {
        self.btnMinusPressTime = now;
        self.btnMinusHandled = NO;
        self.btnMinusWasPressed = YES;
    } else if (self.btnMinus && self.btnMinusWasPressed && !self.btnMinusHandled) {
        NSTimeInterval duration = now - self.btnMinusPressTime;
        if (duration >= LONG_PRESS_THRESHOLD) {
            // LONG PRESS: HOLD key_~ (Tactical view)
            printf("\n🎯 Tactical View ON (Minus Hold)\n");
            fflush(stdout);
            [self simulateKeyPress:0x35 down:YES withRumble:YES]; // ~ down (hold)
            self.btnMinusHandled = YES;
        }
    } else if (!self.btnMinus && self.btnMinusWasPressed) {
        if (!self.btnMinusHandled) {
            // SHORT PRESS: Center Mouse
            [self centerMouse];
            [self setRumble:YES]; usleep(100000); [self setRumble:NO];
        } else {
            // Release ~ from long press
            [self simulateKeyPress:0x35 down:NO withRumble:NO];   // ~ up
            printf("🎯 Tactical View OFF\n");
            fflush(stdout);
        }
        self.btnMinusWasPressed = NO;
        self.btnMinusHandled = NO;
    }
    prevBtnMinus = self.btnMinus;
    
    // ============================================
    // HOME: Short = Toggle IR Inversion, Long = nothing
    // ============================================
    if (self.btnHome && !prevBtnHome) {
        self.btnHomePressTime = now;
        self.btnHomeHandled = NO;
        self.btnHomeWasPressed = YES;
    } else if (self.btnHome && self.btnHomeWasPressed && !self.btnHomeHandled) {
        NSTimeInterval duration = now - self.btnHomePressTime;
        if (duration >= LONG_PRESS_THRESHOLD) {
            // LONG PRESS: Do nothing
            self.btnHomeHandled = YES;
        }
    } else if (!self.btnHome && self.btnHomeWasPressed) {
        if (!self.btnHomeHandled) {
            // SHORT PRESS: Toggle IR Inversion
            self.irBottom = !self.irBottom;
            printf("\n🔄 IR Inversion: %s\n", self.irBottom ? "BOTTOM" : "TOP");
            fflush(stdout);
            [self setRumble:YES]; usleep(100000); [self setRumble:NO];
        }
        self.btnHomeWasPressed = NO;
        self.btnHomeHandled = NO;
    }
    prevBtnHome = self.btnHome;
    
    // ============================================
    // A: HOLD key_q (Zoom weapon)
    // ============================================
    if (self.btnA && !prevBtnA) {
        // A pressed - HOLD Q down
        printf("\n🔭 Zoom ON (A Hold)\n");
        fflush(stdout);
        [self simulateKeyPress:0x0C down:YES withRumble:YES]; // Q DOWN (hold)
        self.btnAWasPressed = YES;
    } else if (!self.btnA && prevBtnA) {
        // A released - Release Q
        printf("\n🔭 Zoom OFF (A Release)\n");
        fflush(stdout);
        [self simulateKeyPress:0x0C down:NO withRumble:NO];   // Q UP (release)
        self.btnAWasPressed = NO;
    }
    prevBtnA = self.btnA;
    
    // ============================================
    // B: HOLD Left Mouse Click (Fire - Continuous)
    // ============================================
    if (self.btnB && !prevBtnB) {
        // B pressed - HOLD left mouse button DOWN
        printf("\n🔫 FIRE ON (B Hold)\n");
        fflush(stdout);
        
        // Get current mouse position
        CGEventRef event = CGEventCreate(NULL);
        CGPoint currentPos = CGEventGetLocation(event);
        CFRelease(event);
        
        // Create mouse down event (hold)
        CGEventRef mouseDown = CGEventCreateMouseEvent(
            NULL,
            kCGEventLeftMouseDown,
            currentPos,
            kCGMouseButtonLeft
        );
        if (mouseDown) {
            CGEventPost(kCGHIDEventTap, mouseDown);
            CFRelease(mouseDown);
        }
        
        // Rumble feedback
        [self setRumble:YES];
        usleep(50000);
        [self setRumble:NO];
        
        self.btnBWasPressed = YES;
    } else if (!self.btnB && prevBtnB) {
        // B released - Release left mouse button UP
        printf("\n🔫 FIRE OFF (B Release)\n");
        fflush(stdout);
        
        // Get current mouse position
        CGEventRef event = CGEventCreate(NULL);
        CGPoint currentPos = CGEventGetLocation(event);
        CFRelease(event);
        
        // Create mouse up event (release)
        CGEventRef mouseUp = CGEventCreateMouseEvent(
            NULL,
            kCGEventLeftMouseUp,
            currentPos,
            kCGMouseButtonLeft
        );
        if (mouseUp) {
            CGEventPost(kCGHIDEventTap, mouseUp);
            CFRelease(mouseUp);
        }
        
        [self setRumble:YES];
        usleep(50000);
        [self setRumble:NO];
        
        self.btnBWasPressed = NO;
    }
    prevBtnB = self.btnB;
    
    // ============================================
    // DPAD UP: Short = key_e (Action), Long = key_b (Binocular hold)
    // ============================================
    if (self.btnUp && !prevBtnUp) {
        self.btnUpPressTime = now;
        self.btnUpHandled = NO;
        self.btnUpWasPressed = YES;
    } else if (self.btnUp && self.btnUpWasPressed && !self.btnUpHandled) {
        NSTimeInterval duration = now - self.btnUpPressTime;
        if (duration >= LONG_PRESS_THRESHOLD) {
            // LONG PRESS: HOLD key_b (Binocular)
            printf("\n🔭 Binocular ON (Up Hold)\n");
            fflush(stdout);
            [self simulateKeyPress:0x0B down:YES withRumble:YES]; // B down (hold)
            self.btnUpHandled = YES;
        }
    } else if (!self.btnUp && self.btnUpWasPressed) {
        if (!self.btnUpHandled) {
            // SHORT PRESS: key_e (Action)
            printf("\n⚡ Action (Up Short)\n");
            fflush(stdout);
            [self simulateKeyPress:0x0E down:YES withRumble:YES]; // E down
            usleep(50000);
            [self simulateKeyPress:0x0E down:NO withRumble:NO];   // E up
        } else {
            // Release B from long press
            [self simulateKeyPress:0x0B down:NO withRumble:NO];   // B up
            printf("🔭 Binocular OFF\n");
            fflush(stdout);
        }
        self.btnUpWasPressed = NO;
        self.btnUpHandled = NO;
    }
    prevBtnUp = self.btnUp;
    
    // ============================================
    // DPAD DOWN: Short = key_v (Scope), Long = key_m (Map hold)
    // ============================================
    if (self.btnDown && !prevBtnDown) {
        self.btnDownPressTime = now;
        self.btnDownHandled = NO;
        self.btnDownWasPressed = YES;
    } else if (self.btnDown && self.btnDownWasPressed && !self.btnDownHandled) {
        NSTimeInterval duration = now - self.btnDownPressTime;
        if (duration >= LONG_PRESS_THRESHOLD) {
            // LONG PRESS: HOLD key_m (Map)
            printf("\n🗺️ Map ON (Down Hold)\n");
            fflush(stdout);
            [self simulateKeyPress:0x2E down:YES withRumble:YES]; // M down (hold)
            self.btnDownHandled = YES;
        }
    } else if (!self.btnDown && self.btnDownWasPressed) {
        if (!self.btnDownHandled) {
            // SHORT PRESS: key_v (Scope weapon)
            printf("\n🎯 Scope (Down Short)\n");
            fflush(stdout);
            [self simulateKeyPress:0x09 down:YES withRumble:YES]; // V down
            usleep(50000);
            [self simulateKeyPress:0x09 down:NO withRumble:NO];   // V up
        } else {
            // Release M from long press
            [self simulateKeyPress:0x2E down:NO withRumble:NO];   // M up
            printf("🗺️ Map OFF\n");
            fflush(stdout);
        }
        self.btnDownWasPressed = NO;
        self.btnDownHandled = NO;
    }
    prevBtnDown = self.btnDown;
    
    // ============================================
    // DPAD LEFT: Short = key_tab (Toggle weapon), Long = key_* (Command menu hold)
    // ============================================
    if (self.btnLeft && !prevBtnLeft) {
        self.btnLeftPressTime = now;
        self.btnLeftHandled = NO;
        self.btnLeftWasPressed = YES;
    } else if (self.btnLeft && self.btnLeftWasPressed && !self.btnLeftHandled) {
        NSTimeInterval duration = now - self.btnLeftPressTime;
        if (duration >= LONG_PRESS_THRESHOLD) {
            // LONG PRESS: HOLD key_* (Command menu)
            printf("\n📋 Command Menu ON (Left Hold)\n");
            fflush(stdout);
            [self simulateKeyPress:0x1F down:YES withRumble:YES]; // * down (hold) - multiply key
            self.btnLeftHandled = YES;
        }
    } else if (!self.btnLeft && self.btnLeftWasPressed) {
        if (!self.btnLeftHandled) {
            // SHORT PRESS: key_tab (Toggle weapon)
            printf("\n🔁 Toggle Weapon (Left Short)\n");
            fflush(stdout);
            [self simulateKeyPress:0x30 down:YES withRumble:YES]; // Tab down
            usleep(50000);
            [self simulateKeyPress:0x30 down:NO withRumble:NO];   // Tab up
        } else {
            // Release * from long press
            [self simulateKeyPress:0x1F down:NO withRumble:NO];   // * up
            printf("📋 Command Menu OFF\n");
            fflush(stdout);
        }
        self.btnLeftWasPressed = NO;
        self.btnLeftHandled = NO;
    }
    prevBtnLeft = self.btnLeft;
    
    // ============================================
    // DPAD RIGHT: Short = key_space (Freelook), Long = key_z (1st/3rd toggle)
    // ============================================
    if (self.btnRight && !prevBtnRight) {
        self.btnRightPressTime = now;
        self.btnRightHandled = NO;
        self.btnRightWasPressed = YES;
    } else if (self.btnRight && self.btnRightWasPressed && !self.btnRightHandled) {
        NSTimeInterval duration = now - self.btnRightPressTime;
        if (duration >= LONG_PRESS_THRESHOLD) {
            // LONG PRESS: key_z (1st/3rd person toggle)
            printf("\n👤 1st/3rd Person Toggle (Right Hold)\n");
            fflush(stdout);
            [self simulateKeyPress:0x06 down:YES withRumble:YES]; // Z down
            usleep(50000);
            [self simulateKeyPress:0x06 down:NO withRumble:NO];   // Z up
            self.btnRightHandled = YES;
        }
    } else if (!self.btnRight && self.btnRightWasPressed) {
        if (!self.btnRightHandled) {
            // SHORT PRESS: key_space (Freelook)
            printf("\n👁️ Freelook (Right Short)\n");
            fflush(stdout);
            [self simulateKeyPress:0x31 down:YES withRumble:YES]; // Space down
            usleep(50000);
            [self simulateKeyPress:0x31 down:NO withRumble:NO];   // Space up
        }
        self.btnRightWasPressed = NO;
        self.btnRightHandled = NO;
    }
    prevBtnRight = self.btnRight;
}


- (void)parseNunchukData:(uint8_t *)decrypted withID:(uint8_t)id andCoreData:(uint8_t *)coreData {
    // Nunchuk data format:
    // Byte 0: Joystick X (0-255)
    // Byte 1: Joystick Y (0-255)
    // Byte 2: Accel X
    // Byte 3: Accel Y  
    // Byte 4: Accel Z
    // Byte 5: Button bits (bit 0 = Z, bit 1 = C)
    
    int rawX = decrypted[0];
    int rawY = decrypted[1];
    
    // PARSE BUTTON STATES FIRST - this is what was missing!
    BOOL cPressed = ((decrypted[5] & 0x02) == 0);  // C button (bit 1)
    BOOL zPressed = ((decrypted[5] & 0x01) == 0);  // Z button (bit 0)
    
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    const NSTimeInterval LONG_PRESS_THRESHOLD = 0.5;
    
    // ============================================
    // NUNCHUK C: HOLD key_lshift (Run)
    // ============================================
    if (cPressed && !self.cWasPressed) {
        // C pressed - HOLD Shift down
        printf("\n🏃 Run ON (C Hold)\n");
        fflush(stdout);
        [self simulateKeyPress:0x38 down:YES withRumble:YES]; // Shift DOWN (hold)
        self.cWasPressed = YES;
    } else if (!cPressed && self.cWasPressed) {
        // C released - Release Shift
        printf("\n🏃 Run OFF (C Release)\n");
        fflush(stdout);
        [self simulateKeyPress:0x38 down:NO withRumble:NO];   // Shift UP (release)
        self.cWasPressed = NO;
    }
    self.cPressed = cPressed;
    
    // ============================================
    // NUNCHUK Z: SHORT = key_k (Kick), LONG = nothing
    // ============================================
    if (zPressed && !self.zWasPressed) {
        self.zPressTime = now;
        self.zHandled = NO;
        self.zWasPressed = YES;
    } else if (zPressed && self.zWasPressed && !self.zHandled) {
        NSTimeInterval duration = now - self.zPressTime;
        if (duration >= LONG_PRESS_THRESHOLD) {
            // LONG PRESS: Do nothing
            self.zHandled = YES;
        }
    } else if (!zPressed && self.zWasPressed) {
        if (!self.zHandled) {
            // SHORT PRESS: key_k (Kick)
            printf("\n🦶 Kick (Z Short)\n");
            fflush(stdout);
            [self simulateKeyPress:0x28 down:YES withRumble:YES]; // K down
            usleep(50000);
            [self simulateKeyPress:0x28 down:NO withRumble:NO];   // K up
        }
        self.zWasPressed = NO;
        self.zHandled = NO;
    }
    self.zPressed = zPressed;

    // Handle Nunchuk calibration
    if (self.calibrating && self.extConnected) {
        // Skip extreme values during calibration (joystick at rest should be around 128)
        if (rawX > 20 && rawX < 235 && rawY > 20 && rawY < 235) {
            self.calXSum += rawX;
            self.calYSum += rawY;
            self.calSamples++;
        }
        
        printf("\r🔧 Calibrating... %d/30", self.calSamples);
        fflush(stdout);
        
        if (self.calSamples >= 30) {
            self.joyXCenter = self.calXSum / 30;
            self.joyYCenter = self.calYSum / 30;
            self.calibrated = YES;
            self.calibrating = NO;
            printf("\n✅ Calibration complete!\n");
            printf("   X Center: %d  Y Center: %d\n\n", self.joyXCenter, self.joyYCenter);
            fflush(stdout);
        }
        return;
    }
    
    if (!self.calibrated) {
        // If not calibrated, use default center
        self.joyXCenter = 128;
        self.joyYCenter = 128;
        self.calibrated = YES;
    }
    
    if (coreData) {
        [self parseWiimoteButtons:coreData];
    }
    
    // Calculate centered values (raw - center)
    // Nunchuk Y is inverted (up is low values, down is high values)
    int centeredX = rawX - self.joyXCenter;
    //int centeredY = -(rawY - self.joyYCenter);  // Invert Y
    // NEW (correct - no inversion)
    int centeredY = rawY - self.joyYCenter;

    // Apply deadzone
    int deadzone = 12;
    if (abs(centeredX) < deadzone) centeredX = 0;
    if (abs(centeredY) < deadzone) centeredY = 0;
    
    // Normalize to -100 to +100 range (instead of raw values)
    int maxRange = 110;  // Max expected deflection from center
    self.joyX = (centeredX * 100) / maxRange;
    self.joyY = (centeredY * 100) / maxRange;
    
    // Clamp to -100/+100
    self.joyX = MAX(-100, MIN(100, self.joyX));
    self.joyY = MAX(-100, MIN(100, self.joyY));
    
    // Determine direction with proper 8-way handling
    NSString *direction = @"IDLE";
    if (abs(self.joyX) > 15 || abs(self.joyY) > 15) {
        float angle = atan2(self.joyY, self.joyX) * 180 / M_PI;
        
        // Convert angle to 8 directions
        if (angle >= -22.5 && angle < 22.5) {
            direction = @"RIGHT";
            [self simulateKeyPress:0x02 down:YES];  // D
            [self simulateKeyPress:0x00 down:NO];   // A off
            [self simulateKeyPress:0x0D down:NO];   // W off
            [self simulateKeyPress:0x01 down:NO];   // S off
        } else if (angle >= 22.5 && angle < 67.5) {
            direction = @"UP-RIGHT";
            [self simulateKeyPress:0x0D down:YES];  // W
            [self simulateKeyPress:0x02 down:YES];  // D
            [self simulateKeyPress:0x00 down:NO];   // A off
            [self simulateKeyPress:0x01 down:NO];   // S off
        } else if (angle >= 67.5 && angle < 112.5) {
            direction = @"UP";
            [self simulateKeyPress:0x0D down:YES];  // W
            [self simulateKeyPress:0x01 down:NO];   // S off
            [self simulateKeyPress:0x00 down:NO];   // A off
            [self simulateKeyPress:0x02 down:NO];   // D off
        } else if (angle >= 112.5 && angle < 157.5) {
            direction = @"UP-LEFT";
            [self simulateKeyPress:0x0D down:YES];  // W
            [self simulateKeyPress:0x00 down:YES];  // A
            [self simulateKeyPress:0x01 down:NO];   // S off
            [self simulateKeyPress:0x02 down:NO];   // D off
        } else if ((angle >= 157.5 && angle <= 180) || (angle >= -180 && angle < -157.5)) {
            direction = @"LEFT";
            [self simulateKeyPress:0x00 down:YES];  // A
            [self simulateKeyPress:0x02 down:NO];   // D off
            [self simulateKeyPress:0x0D down:NO];   // W off
            [self simulateKeyPress:0x01 down:NO];   // S off
        } else if (angle >= -157.5 && angle < -112.5) {
            direction = @"DOWN-LEFT";
            [self simulateKeyPress:0x01 down:YES];  // S
            [self simulateKeyPress:0x00 down:YES];  // A
            [self simulateKeyPress:0x0D down:NO];   // W off
            [self simulateKeyPress:0x02 down:NO];   // D off
        } else if (angle >= -112.5 && angle < -67.5) {
            direction = @"DOWN";
            [self simulateKeyPress:0x01 down:YES];  // S
            [self simulateKeyPress:0x0D down:NO];   // W off
            [self simulateKeyPress:0x00 down:NO];   // A off
            [self simulateKeyPress:0x02 down:NO];   // D off
        } else if (angle >= -67.5 && angle < -22.5) {
            direction = @"DOWN-RIGHT";
            [self simulateKeyPress:0x01 down:YES];  // S
            [self simulateKeyPress:0x02 down:YES];  // D
            [self simulateKeyPress:0x0D down:NO];   // W off
            [self simulateKeyPress:0x00 down:NO];   // A off
        }
    } else {
        // IMPORTANT: Release ALL keys when joystick is centered/idle
        direction = @"IDLE";
        [self simulateKeyPress:0x0D down:NO];  // W off
        [self simulateKeyPress:0x00 down:NO];  // A off
        [self simulateKeyPress:0x01 down:NO];  // S off
        [self simulateKeyPress:0x02 down:NO];  // D off
    }
    
    NSString *buttons = [self buttonString];
    
    // Build display with normalized values
    NSMutableString *display = [NSMutableString string];
    [display appendFormat:@"[Nunchuk] X:%+3d%% Y:%+3d%% | Dir: %-8@ | Wii: %@ | C:%d Z:%d",
     self.joyX, self.joyY, direction, buttons, self.cPressed, self.zPressed];
    
    // Only update if changed
    if (![display isEqualToString:self.lastDisplay]) {
        printf("\r%s   ", [display UTF8String]);
        fflush(stdout);
        self.lastDisplay = display;
    }
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
    uint8_t id = d[1];

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

    if (id == 0x20 && len >= 8) {
        self.lf = d[4];
        self.batteryRaw = d[7];
        self.battery = (self.batteryRaw * 100) / 0xC0;
        self.statusCount++;
        
        BOOL extConnected = (self.lf & 0x02) != 0;
        if (extConnected != self.extConnected) {
            self.extConnected = extConnected;
            printf("\n[STATUS] NUNCHUK %s (LF:0x%02X, Battery:%d%%)\n", 
                   extConnected ? "CONNECTED" : "DISCONNECTED", self.lf, self.battery);
            fflush(stdout);
            
            if (extConnected) {
                [self initExtension];
                [self requestStatus];
            }

        }
        return;
    }
    

    if (id == 0x35 || id == 0x37) {
        uint8_t *data;
        int extOffset;
        
        if (id == 0x35) {
            extOffset = 5;
        } else {
            extOffset = 17;
        }
        
        if (len < extOffset + 6) return;
        
        uint8_t *coreData = d + 2;
        data = d + extOffset;
        
        
        int encrypted = 1;
        for (int i = 0; i < 6; i++) {
            if (data[i] != 0x17 && data[i] != 0x00 && data[i] != 0xFF) {
                encrypted = 0;
                break;
            }
        }
        
        uint8_t decrypted[6];
        for (int i = 0; i < 6; i++) {
            decrypted[i] = data[i];
        }
        if (encrypted) {
            for (int i = 0; i < 6; i++) {
                decrypted[i] = (data[i] ^ 0x17) + 0x17;
            }
        }
        
        [self parseNunchukData:decrypted withID:id andCoreData:coreData];
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