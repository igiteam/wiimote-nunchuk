#!/bin/bash
# Wiimote - IR ONLY DEBUGGER (BASIC MODE)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║              WIIMOTE - IR ONLY DEBUGGER                      ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

APP_NAME="Wiimote"
BUNDLE_ID="com.github.wiimote"

rm -rf "$APP_NAME"
mkdir -p "$APP_NAME"/src
cd "$APP_NAME" || exit

cat > "src/WiimoteManager.m" << 'EOF'
#import "WiimoteManager.h"
#import <IOBluetooth/IOBluetooth.h>
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>

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

// Mouse control properties
@property (nonatomic, assign) BOOL mouseControlEnabled;
@property (nonatomic, assign) float mouseSensitivity;
@property (nonatomic, assign) float mouseSmoothing;
@property (nonatomic, assign) CGPoint lastMousePos;
@property (nonatomic, assign) float smoothX;
@property (nonatomic, assign) float smoothY;
@property (nonatomic, assign) BOOL buttonAPressed;
@property (nonatomic, assign) BOOL buttonBPressed;
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
        
        // Mouse control defaults
        _mouseControlEnabled = YES;
        _mouseSensitivity = 1.5;
        _mouseSmoothing = 0.7;
        _smoothX = 0;
        _smoothY = 0;
        _buttonAPressed = NO;
        _buttonBPressed = NO;
        
        printf("[Wiimote] IR Mouse Controller Init\n");
        printf("  Mouse Control: %s\n", _mouseControlEnabled ? "ENABLED" : "DISABLED");
        printf("  Sensitivity: %.1f\n", _mouseSensitivity);
        printf("  Smoothing: %.1f\n", _mouseSmoothing);
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
            printf("[Wiimote] Found stale device: %s\n", [name UTF8String]);
            fflush(stdout);
            
            if (dev.isConnected) {
                printf("[Wiimote] Disconnecting...\n");
                fflush(stdout);
                [dev closeConnection];
                usleep(500000);
            }
            
            if ([dev respondsToSelector:@selector(removePairing)]) {
                printf("[Wiimote] Removing pairing...\n");
                fflush(stdout);
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
    if (!self.running) return;
    if (self.connected) return;
    
    if (isRetry) {
        self.retryCount++;
        if (self.retryCount > MAX_RETRIES) {
            printf("[Wiimote] Max retries reached.\n");
            printf("[Wiimote] Press the red Sync button on the back of the Wiimote.\n");
            printf("[Wiimote] Or restart the app.\n");
            fflush(stdout);
            return;
        }
        printf("[Wiimote] Retry %d/%d in %.1f seconds...\n", 
               self.retryCount, MAX_RETRIES, RETRY_DELAY);
        fflush(stdout);
        
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
    if (!self.running) return;
    if (self.inquiryActive) return;
    if (self.connected) return;
    
    self.inquiryActive = YES;
    self.inquiry = [IOBluetoothDeviceInquiry inquiryWithDelegate:self];
    self.inquiry.inquiryLength = 10;
    self.inquiry.updateNewDeviceNames = YES;
    
    printf("[Wiimote] Press 1+2 on the Wiimote\n");
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
    if (!self.running) return;
    if (!self.inquiryActive) return;
    if (self.connected) return;
    
    printf("[Wiimote] Inquiry timeout - no devices found.\n");
    fflush(stdout);
    
    [self.inquiry stop];
    self.inquiry = nil;
    self.inquiryActive = NO;
    
    [self startDiscoveryWithRetry:YES];
}

- (void)deviceInquiryDeviceFound:(IOBluetoothDeviceInquiry *)sender device:(IOBluetoothDevice *)device {
    NSString *name = device.name;
    if ([name containsString:@"Nintendo"] || [name containsString:@"RVL"]) {
        printf("[Wiimote] Found: %s\n", [name UTF8String]);
        fflush(stdout);
        
        [self.inquiryTimer invalidate];
        self.inquiryTimer = nil;
        self.inquiryActive = NO;
        
        [sender stop];
        self.inquiry = nil;
        
        if (device.isConnected) {
            printf("[Wiimote] Device already connected, disconnecting...\n");
            fflush(stdout);
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
        printf("[Wiimote] No devices found.\n");
        fflush(stdout);
        [self startDiscoveryWithRetry:YES];
    }
}

- (void)connectTo:(IOBluetoothDevice *)device {
    if (self.connecting) return;
    if (self.connected) return;
    self.connecting = YES;
    self.device = device;
    printf("[Wiimote] Connecting...\n");
    fflush(stdout);
    
    self.retryCount = 0;
    [self.retryTimer invalidate];
    self.retryTimer = nil;
    
    if (device.isConnected) {
        printf("[Wiimote] Device already connected, disconnecting first...\n");
        fflush(stdout);
        [device closeConnection];
        usleep(500000);
    }
    
    usleep(200000);
    
    IOBluetoothL2CAPChannel *c = nil;
    IOReturn r = [device openL2CAPChannelSync:&c withPSM:PSM_CTRL delegate:self];
    if (r == kIOReturnSuccess && c) {
        self.ctrl = c;
        printf("[Wiimote] Control opened\n");
        fflush(stdout);
        
        uint8_t h[] = {0x43, 0x00};
        [self.ctrl writeSync:h length:2];
        usleep(100000);
        
        IOBluetoothL2CAPChannel *ic = nil;
        r = [device openL2CAPChannelSync:&ic withPSM:PSM_INTR delegate:self];
        if (r == kIOReturnSuccess && ic) {
            self.intr = ic;
            printf("[Wiimote] Interrupt opened!\n");
            fflush(stdout);
            self.connecting = NO;
            self.connected = YES;
            self.reconnecting = NO;
            [self onConnected];
        } else {
            printf("[Wiimote] Interrupt failed: %d\n", r);
            fflush(stdout);
            self.connecting = NO;
            [self connectionFailed];
        }
    } else {
        printf("[Wiimote] Control failed: %d\n", r);
        fflush(stdout);
        self.connecting = NO;
        [self connectionFailed];
    }
}

- (void)connectionFailed {
    self.connected = NO;
    [self disconnect];
    usleep(500000);
    [self startDiscoveryWithRetry:YES];
}

- (void)onConnected {
    printf("[Wiimote] CONNECTED!\n");
    printf("[Wiimote] IR Mouse Controller Active\n");
    printf("[Wiimote] Controls:\n");
    printf("  - Aim at sensor bar to move mouse\n");
    printf("  - Press A to left-click\n");
    printf("  - Press B to right-click\n");
    printf("  - Press Home to toggle mouse control\n");
    fflush(stdout);
    
    self.retryCount = 0;
    [self.retryTimer invalidate];
    self.retryTimer = nil;
    
    [self setLED:0x10];
    usleep(50000);
    
    [self setRumble:YES];
    usleep(300000);
    [self setRumble:NO];
    printf("[Wiimote] Rumble test complete\n");
    fflush(stdout);
    
    [self setReportingMode:0x33];
    usleep(50000);
    
    [self initIRWithRetry:0];
    
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.02  // 50Hz for smoother mouse
                                                   target:self
                                                 selector:@selector(pollIR)
                                                 userInfo:nil
                                                  repeats:YES];
}

- (void)showStatusHeader {
    if (self.statusHeaderShown) return;
    self.statusHeaderShown = YES;
    printf("\n");
    printf("╔══════════════════════════════════════════════════════════════╗\n");
    printf("║  IR MOUSE CONTROLLER STATUS                                 ║\n");
    printf("╠══════════════════════════════════════════════════════════════╣\n");
    printf("║  Mouse Control: %-3s                                        ║\n", self.mouseControlEnabled ? "ON " : "OFF");
    printf("║  Sensitivity:   %.1f                                        ║\n", self.mouseSensitivity);
    printf("║  Smoothing:     %.1f                                        ║\n", self.mouseSmoothing);
    printf("║  IR Bottom:     %-3s                                        ║\n", self.irBottom ? "YES" : "NO");
    printf("║  Battery:       %d%%                                         ║\n", self.batteryPercent);
    printf("╚══════════════════════════════════════════════════════════════╝\n");
    printf("\n");
    fflush(stdout);
}

- (void)initIR {
    printf("\n========== INIT IR ==========\n");
    fflush(stdout);
    
    uint8_t irEnable[] = {0xA2, 0x13, 0x06};
    [self.ctrl writeSync:irEnable length:3];
    usleep(50000);
    
    uint8_t irEnable2[] = {0xA2, 0x1A, 0x06};
    [self.ctrl writeSync:irEnable2 length:3];
    usleep(50000);
    
    [self writeMemory:0xB00030 data:[NSData dataWithBytes:"\x01" length:1]];
    usleep(50000);
    
    uint8_t block1[] = {0x02, 0x00, 0x00, 0x71, 0x01, 0x00, 0xAA, 0x00, 0x64};
    [self writeMemory:0xB00000 data:[NSData dataWithBytes:block1 length:9]];
    usleep(50000);
    
    uint8_t block2[] = {0x63, 0x03};
    [self writeMemory:0xB0001A data:[NSData dataWithBytes:block2 length:2]];
    usleep(50000);
    
    uint8_t irMode = 0x03;
    [self writeMemory:0xB00033 data:[NSData dataWithBytes:&irMode length:1]];
    usleep(50000);
    
    [self writeMemory:0xB00030 data:[NSData dataWithBytes:"\x08" length:1]];
    usleep(50000);
    
    [self setReportingMode:0x33];
    usleep(50000);
    
    printf("[IR] Enabled (Mode: Extended, Sens: Level 3)\n");
    printf("==================================\n\n");
    fflush(stdout);
    
    [self showStatusHeader];
}

- (void)pollIR {
    if (!self.connected) {
        [self reconnect];
        return;
    }
    [self requestStatus];
}

- (void)reconnect {
    if (self.reconnecting) return;
    if (self.connected) return;
    self.reconnecting = YES;
    
    printf("[Wiimote] Reconnecting...\n");
    fflush(stdout);
    
    [self disconnect];
    self.retryCount = 0;
    [self startDiscoveryWithRetry:NO];
}

- (void)writeMemory:(uint32_t)address data:(NSData *)data {
    if (!self.ctrl) return;
    if (data.length > 16) return;
    
    NSMutableData *report = [NSMutableData data];
    uint8_t flags = 0x04;
    [report appendBytes:&flags length:1];
    
    uint8_t addrBytes[3] = {
        (address >> 16) & 0xFF,
        (address >> 8) & 0xFF,
        address & 0xFF
    };
    [report appendBytes:addrBytes length:3];
    
    uint8_t size = data.length & 0x0F;
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
    
    NSUInteger totalLen = report.length;
    if (totalLen < 21) {
        uint8_t padding[21] = {0};
        [report appendBytes:padding length:21 - totalLen];
    }
    
    [self.ctrl writeSync:(void *)report.bytes length:report.length];
}

- (void)setLED:(int)mask {
    uint8_t led[] = {0xA2, 0x11, (uint8_t)mask};
    [self.ctrl writeSync:led length:3];
}

- (void)setReportingMode:(uint8_t)mode {
    if (!self.ctrl) return;
    uint8_t report[] = {0xA2, 0x12, 0x04, mode};
    [self.ctrl writeSync:report length:4];
}

- (void)initIRWithRetry:(int)retryCount {
    if (retryCount > 3) {
        printf("[IR] Failed to initialize after 3 attempts\n");
        fflush(stdout);
        return;
    }
    
    printf("[IR] Init attempt %d\n", retryCount + 1);
    fflush(stdout);
    
    [self initIR];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (self.frameCount < 5) {
            printf("[IR] No data received, retrying...\n");
            fflush(stdout);
            [self initIRWithRetry:retryCount + 1];
        } else {
            printf("[IR] Initialized successfully!\n");
            fflush(stdout);
        }
    });
}

- (void)requestStatus {
    if (!self.ctrl) return;
    uint8_t status[] = {0xA2, 0x15, 0x00};
    [self.ctrl writeSync:status length:3];
}

- (void)setRumble:(BOOL)enable {
    if (!self.ctrl) return;
    uint8_t rumble[] = {0xA2, 0x10, enable ? 0x01 : 0x00};
    [self.ctrl writeSync:rumble length:3];
}

- (void)handleMouseMovement:(uint16_t)x withY:(uint16_t)y {
    if (!self.mouseControlEnabled) return;
    if (x == 0xFFFF || y == 0xFFFF) return;
    
    // Get screen dimensions
    CGDirectDisplayID displayID = CGMainDisplayID();
    CGFloat screenWidth = CGDisplayPixelsWide(displayID);
    CGFloat screenHeight = CGDisplayPixelsHigh(displayID);
    
    // Map IR coordinates (0-1023) to screen coordinates
    // Center the cursor in the middle of the screen
    float targetX = (x / 1023.0) * screenWidth;
    float targetY = screenHeight - ((y / 1023.0) * screenHeight); // Flip Y
    
    // Apply sensitivity
    float centerX = screenWidth / 2;
    float centerY = screenHeight / 2;
    float deltaX = (targetX - centerX) * self.mouseSensitivity;
    float deltaY = (targetY - centerY) * self.mouseSensitivity;
    targetX = centerX + deltaX;
    targetY = centerY + deltaY;
    
    // Clamp to screen bounds
    targetX = MAX(0, MIN(screenWidth, targetX));
    targetY = MAX(0, MIN(screenHeight, targetY));
    
    // Apply smoothing (exponential moving average)
    if (self.smoothX == 0 && self.smoothY == 0) {
        self.smoothX = targetX;
        self.smoothY = targetY;
    } else {
        float alpha = 1.0 - self.mouseSmoothing;
        self.smoothX = self.smoothX * self.mouseSmoothing + targetX * alpha;
        self.smoothY = self.smoothY * self.mouseSmoothing + targetY * alpha;
    }
    
    // Move mouse
    CGPoint newPos = CGPointMake(self.smoothX, self.smoothY);
    CGEventMove(CGEventCreate(NULL), newPos.x, newPos.y);
}

- (void)handleButtons:(uint16_t)buttons {
    // Button A (bit 3 in second byte)
    BOOL aPressed = (buttons & 0x0800) != 0;
    // Button B (bit 4 in first byte)
    BOOL bPressed = (buttons & 0x0010) != 0;
    // Home button (bit 7 in second byte)
    BOOL homePressed = (buttons & 0x8000) != 0;
    
    // Handle Home button - toggle mouse control
    if (homePressed && !self.buttonAPressed) {  // Use button state to detect edge
        self.mouseControlEnabled = !self.mouseControlEnabled;
        printf("[Wiimote] Mouse control: %s\n", self.mouseControlEnabled ? "ENABLED" : "DISABLED");
        fflush(stdout);
        
        // Update LED to show status
        if (self.mouseControlEnabled) {
            [self setLED:0x10];  // LED 1
        } else {
            [self setLED:0x40];  // LED 3
        }
    }
    
    // Handle A button (left click)
    if (aPressed && !self.buttonAPressed) {
        [self simulateClick:kCGMouseButtonLeft down:YES];
        printf("[Mouse] Left click DOWN\n");
        fflush(stdout);
    } else if (!aPressed && self.buttonAPressed) {
        [self simulateClick:kCGMouseButtonLeft down:NO];
        printf("[Mouse] Left click UP\n");
        fflush(stdout);
    }
    
    // Handle B button (right click)
    if (bPressed && !self.buttonBPressed) {
        [self simulateClick:kCGMouseButtonRight down:YES];
        printf("[Mouse] Right click DOWN\n");
        fflush(stdout);
    } else if (!bPressed && self.buttonBPressed) {
        [self simulateClick:kCGMouseButtonRight down:NO];
        printf("[Mouse] Right click UP\n");
        fflush(stdout);
    }
    
    self.buttonAPressed = aPressed;
    self.buttonBPressed = bPressed;
}

- (void)simulateClick:(CGMouseButton)button down:(BOOL)down {
    CGEventRef event = CGEventCreateMouseEvent(
        NULL,
        down ? kCGEventLeftMouseDown : kCGEventLeftMouseUp,
        CGEventGetLocation(CGEventCreate(NULL)),
        button
    );
    
    // For right button, need to adjust event type
    if (button == kCGMouseButtonRight) {
        CGEventSetType(event, down ? kCGEventRightMouseDown : kCGEventRightMouseUp);
    }
    
    CGEventPost(kCGHIDEventTap, event);
    CFRelease(event);
}

- (void)parseIRData:(uint8_t *)data {
    self.frameCount++;
    
    // In report mode 0x33:
    // data[0-1] = Buttons
    // data[2-4] = Accelerometer
    // data[5-16] = IR data (12 bytes)
    
    uint16_t buttons = (data[1] << 8) | data[0];
    uint8_t *irData = data + 5;
    
    // Handle button presses
    [self handleButtons:buttons];
    
    // Check if we have any IR data
    BOOL hasData = NO;
    for (int i = 0; i < 12; i++) {
        if (irData[i] != 0xFF) { hasData = YES; break; }
    }
    
    if (!hasData) {
        if (self.debugIR && self.frameCount % 20 == 0) {
            printf("[IR] No dots detected\n");
            fflush(stdout);
        }
        return;
    }
    
    // Parse dots and find the best one for mouse control
    // Use the first valid dot with good size
    BOOL foundDot = NO;
    uint16_t bestX = 0;
    uint16_t bestY = 0;
    uint8_t bestSize = 0;
    
    for (int dot = 0; dot < 4; dot++) {
        int offset = dot * 3;
        uint8_t xLow = irData[offset];
        uint8_t yLow = irData[offset + 1];
        uint8_t high = irData[offset + 2];
        
        if (xLow == 0xFF && yLow == 0xFF && high == 0xFF) {
            continue;
        }
        
        uint16_t x = xLow | ((high & 0x03) << 8);
        uint16_t y = yLow | ((high & 0x0C) << 6);
        uint8_t size = (high & 0xF0) >> 4;
        
        // Prefer larger size (closer to sensor bar)
        if (!foundDot || size > bestSize) {
            bestX = x;
            bestY = y;
            bestSize = size;
            foundDot = YES;
        }
    }
    
    if (foundDot) {
        // Apply IR bottom flip if enabled
        if (self.irBottom) {
            bestY = 1023 - bestY;
        }
        
        // Move mouse
        [self handleMouseMovement:bestX withY:bestY];
        
        if (self.debugIR && self.frameCount % 5 == 0) {
            printf("[IR] Dot: X=%04d Y=%04d Size=%d | Mouse: %s\n", 
                   bestX, bestY, bestSize, 
                   self.mouseControlEnabled ? "ACTIVE" : "PAUSED");
            fflush(stdout);
        }
    }
}

- (void)l2capChannelData:(IOBluetoothL2CAPChannel *)ch data:(void *)dp length:(size_t)len {
    uint8_t *d = (uint8_t *)dp;
    if (len < 2) return;
    if (d[0] != 0xA1) return;
    
    uint8_t id = d[1];
    
    if (id == 0x33 && len >= 17) {
        [self parseIRData:d + 5];
    } else if (id == 0x20) {
        if (len >= 8) {
            self.batteryPercent = (d[7] * 100) / 0xC0;
            
            BOOL extConnected = (d[4] & 0x02) != 0;
            if (extConnected) {
                static BOOL extensionDisabled = NO;
                if (!extensionDisabled) {
                    printf("[Wii] Extension detected! Disabling...\n");
                    fflush(stdout);
                    [self writeMemory:0xA40040 data:[NSData dataWithBytes:"\x00" length:1]];
                    usleep(50000);
                    extensionDisabled = YES;
                    [self initIRWithRetry:0];
                }
            }
        }
    }
}

- (void)disconnect {
    self.connected = NO;
    self.connecting = NO;
    
    if (self.ctrl) {
        [self setRumble:NO];
        [self.ctrl closeChannel];
        self.ctrl = nil;
    }
    if (self.intr) {
        [self.intr closeChannel];
        self.intr = nil;
    }
    if (self.device) {
        [self.device closeConnection];
        self.device = nil;
    }
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

cat > "src/WiimoteManager.h" << 'EOF'
#import <Foundation/Foundation.h>
@interface WiimoteManager : NSObject
- (void)start;
- (void)stop;
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

# Compile
echo -e "${CYAN}🔨 Compiling...${NC}"

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
    echo -e "${GREEN}✅ Compilation successful${NC}"
else
    echo -e "${RED}❌ Compilation failed${NC}"
    cat build_errors.log
    exit 1
fi

codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true
xattr -cr "$APP_BUNDLE"

cp -R "$APP_BUNDLE" "$HOME/Applications/" 2>/dev/null || true
cp -R "$APP_BUNDLE" "$HOME/Desktop/" 2>/dev/null || true

echo -e "${GREEN}✅ Done!${NC}"
echo -e "${CYAN}📱 IR Debugger (BASIC MODE):${NC}"
echo -e "   $APP_BUNDLE/Contents/MacOS/$APP_NAME"
echo ""
echo -e "${YELLOW}📝 Features:${NC}"
echo -e "   ✅ Clean up stale connections on start"
echo -e "   ✅ Proper device disconnection before reconnect"
echo -e "   ✅ Auto-retry with cleanup between attempts"
echo -e "   ✅ 8 second inquiry timeout"
echo -e "   ✅ Status header with IR settings"
echo ""
echo -e "${CYAN}🔧 If connection hangs:${NC}"
echo -e "   1. Manually unpair from System Preferences > Bluetooth"
echo -e "   2. Press the red Sync button on the back of the Wiimote"
echo -e "   3. Restart the app"