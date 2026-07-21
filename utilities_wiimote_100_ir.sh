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
        printf("[Wiimote] IR Debugger Init\n");
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
    
    // Clean up any stale connections first
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
            
            // Try to remove pairing if available
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
    
    // Use a slightly different approach - try to open the channels with a small delay
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
    
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.05
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
    printf("║  IR DEBUGGER STATUS                                        ║\n");
    printf("╠══════════════════════════════════════════════════════════════╣\n");
    printf("║  IR Enabled:   YES                                         ║\n");
    printf("║  IR Mode:      Basic (0x01)                                ║\n");
    printf("║  IR Bottom:    %-3s                                          ║\n", self.irBottom ? "YES" : "NO");
    printf("║  Sensitivity:  Level %d                                     ║\n", self.sensitivityLevel);
    printf("║  Debug Output: %-3s                                          ║\n", self.debugIR ? "YES" : "NO");
    printf("║  Battery:      %d%%                                         ║\n", self.batteryPercent);
    printf("╚══════════════════════════════════════════════════════════════╝\n");
    printf("\n");
    fflush(stdout);
}

- (void)initIR {
    printf("\n========== INIT IR ==========\n");
    fflush(stdout);
    
    // STEP 1: Enable IR with 0x06 (both pixel clock and enable)
    uint8_t irEnable[] = {0xA2, 0x13, 0x06};
    [self.ctrl writeSync:irEnable length:3];
    usleep(50000);
    
    // STEP 2: Enable IR 2 with 0x06
    uint8_t irEnable2[] = {0xA2, 0x1A, 0x06};
    [self.ctrl writeSync:irEnable2 length:3];
    usleep(50000);
    
    // STEP 3: Write 0x01 to 0xB00030 (enable IR sensor)
    [self writeMemory:0xB00030 data:[NSData dataWithBytes:"\x01" length:1]];
    usleep(50000);
    
    // STEP 4: Write sensitivity blocks (using Level 3 which is standard)
    // Block 1: 9 bytes at 0xB00000
    uint8_t block1[] = {0x02, 0x00, 0x00, 0x71, 0x01, 0x00, 0xAA, 0x00, 0x64};
    [self writeMemory:0xB00000 data:[NSData dataWithBytes:block1 length:9]];
    usleep(50000);
    
    // Block 2: 2 bytes at 0xB0001A
    uint8_t block2[] = {0x63, 0x03};
    [self writeMemory:0xB0001A data:[NSData dataWithBytes:block2 length:2]];
    usleep(50000);
    
    // STEP 5: Write IR mode (0x03 for Extended Mode - needed for 12 bytes)
    uint8_t irMode = 0x03;  // 0x01 = Basic (10 bytes), 0x03 = Extended (12 bytes)
    [self writeMemory:0xB00033 data:[NSData dataWithBytes:&irMode length:1]];
    usleep(50000);
    
    // STEP 6: Write 0x08 to 0xB00030 (enable IR with 8-bit mode)
    [self writeMemory:0xB00030 data:[NSData dataWithBytes:"\x08" length:1]];
    usleep(50000);
    
    // STEP 7: Set reporting mode to 0x33
    [self setReportingMode:0x33];
    usleep(50000);
    
    printf("[IR] Enabled (Bottom: %s, Mode: Extended (0x03), Sens: Level 3)\n", 
           self.irBottom ? "YES" : "NO");
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
    
    // For register writes (address >= 0xA00000), we need 0x04
    // For EEPROM writes (address < 0xA00000), we need 0x00
    uint8_t flags = 0x04;  // Always use 0x04 for registers
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
    
    // Pad to 16 bytes
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
    
    // Pad to proper length if needed
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
    
    // Wait for data to come through
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        // Check if we're getting IR data with dots
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

- (void)parseIRData:(uint8_t *)data {
    self.frameCount++;
    
    if (self.frameCount % 5 != 0) return;
    
    // In report mode 0x33:
    // data[0-1] = Buttons
    // data[2-4] = Accelerometer
    // data[5-16] = IR data (12 bytes)
    
    uint16_t buttons = (data[1] << 8) | data[0];
    
    printf("[RAW IR] ");
    for (int i = 0; i < 12; i++) {
        printf("%02X ", data[i]);
    }
    printf("| \n");
    
    // Extract IR data starting at offset 5
    uint8_t *irData = data + 5;
    
    printf("  Buttons: 0x%04X\n", buttons);
    printf("  Accel: %02X %02X %02X\n", data[2], data[3], data[4]);
    printf("  IR Bytes: ");
    for (int i = 0; i < 12; i++) {
        printf("[%d]=%02X ", i, irData[i]);
    }
    printf("\n");
    
    // Check if we have any IR data
    BOOL hasData = NO;
    for (int i = 0; i < 12; i++) {
        if (irData[i] != 0xFF) { hasData = YES; break; }
    }
    
    if (!hasData) {
        printf("  NO IR DATA DETECTED\n");
        fflush(stdout);
        return;
    }
    
    printf("  IR Format: Extended Mode (12 bytes)\n");
    printf("  Dot1: X,Y,Size | Dot2: X,Y,Size | Dot3: X,Y,Size | Dot4: X,Y,Size\n");
    
    int dotCount = 0;
    
    // Parse 4 dots, each with 3 bytes (X, Y, Size)
    for (int dot = 0; dot < 4; dot++) {
        int offset = dot * 3;
        uint8_t xLow = irData[offset];
        uint8_t yLow = irData[offset + 1];
        uint8_t high = irData[offset + 2];
        
        // Skip if this dot is empty (all 0xFF)
        if (xLow == 0xFF && yLow == 0xFF && high == 0xFF) {
            continue;
        }
        
        // Extract 10-bit X and Y values
        uint16_t x = xLow | ((high & 0x03) << 8);
        uint16_t y = yLow | ((high & 0x0C) << 6);
        uint8_t size = (high & 0xF0) >> 4;
        
        printf("  Dot%d: X=%04d (0x%04X), Y=%04d (0x%04X), Size=%d", 
               dot + 1, x, x, y, y, size);
        
        if (self.irBottom) {
            y = 1023 - y;
            printf(" (flipped Y to %04d)", y);
        }
        printf("\n");
        dotCount++;
    }
    
    printf("  Total dots detected: %d\n", dotCount);
    fflush(stdout);
}

- (void)l2capChannelData:(IOBluetoothL2CAPChannel *)ch data:(void *)dp length:(size_t)len {
    uint8_t *d = (uint8_t *)dp;
    if (len < 2) return;
    if (d[0] != 0xA1) return;
    
    uint8_t id = d[1];
    
    if (id == 0x33 && len >= 17) {
        // Parse ALL data as IR - ignore extension
        [self parseIRData:d + 5];
    } else if (id == 0x20) {
        if (len >= 8) {
            self.batteryPercent = (d[7] * 100) / 0xC0;
            
            // Check if extension is connected
            BOOL extConnected = (d[4] & 0x02) != 0;
            
            if (extConnected) {
                // EXTENSION DETECTED - DISABLE IT!
                static BOOL extensionDisabled = NO;
                if (!extensionDisabled) {
                    printf("[Wii] Extension detected! Disabling...\n");
                    fflush(stdout);
                    
                    // Disable extension
                    [self writeMemory:0xA40040 data:[NSData dataWithBytes:"\x00" length:1]];
                    usleep(50000);
                    
                    extensionDisabled = YES;
                    
                    // Re-init IR after disabling extension
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