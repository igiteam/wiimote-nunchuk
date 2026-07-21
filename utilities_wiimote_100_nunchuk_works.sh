#!/bin/bash
# Wiimote - RAW DATA DEBUGGER

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║              WIIMOTE - RAW DATA DEBUGGER                     ║"
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

@interface WiimoteManager ()
@property (nonatomic, strong) IOBluetoothDeviceInquiry *inquiry;
@property (nonatomic, strong) IOBluetoothDevice *device;
@property (nonatomic, strong) IOBluetoothL2CAPChannel *ctrl;
@property (nonatomic, strong) IOBluetoothL2CAPChannel *intr;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) BOOL connecting;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) int battery;
@property (nonatomic, assign) int batteryRaw;
@property (nonatomic, assign) int statusCount;
@property (nonatomic, assign) int lf;
@property (nonatomic, assign) BOOL extConnected;
@property (nonatomic, assign) int joyX, joyY;
@property (nonatomic, assign) BOOL cPressed, zPressed;
@property (nonatomic, assign) BOOL initDone;
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
        _battery = 0;
        _batteryRaw = 0;
        _statusCount = 0;
        _lf = 0;
        _extConnected = NO;
        _joyX = _joyY = 0;
        _cPressed = _zPressed = NO;
        _initDone = NO;
        _calibrated = NO;
        _calibrating = NO;
        _joyXCenter = 128;
        _joyYCenter = 128;
        _calSamples = 0;
        _calXSum = 0;
        _calYSum = 0;
        printf("[Wiimote] Init\n");
        fflush(stdout);
    }
    return self;
}

- (void)start {
    if (self.running) return;
    self.running = YES;
    printf("[Wiimote] Starting...\n");
    fflush(stdout);
    [self startDiscovery];
}

- (void)stop {
    self.running = NO;
    [self.timer invalidate];
    self.timer = nil;
    [self disconnect];
    printf("[Wiimote] Stopped\n");
    fflush(stdout);
}

- (void)updateDisplay {
    printf("\r[Wiimote] Battery: %d%%  Nunchuk: %s  Joy: (%3d, %3d)  C:%d Z:%d   ",
           self.battery,
           self.extConnected ? "CONNECTED" : "DISCONNECTED",
           self.joyX, self.joyY,
           self.cPressed, self.zPressed);
    fflush(stdout);
}

- (void)startDiscovery {
    self.inquiry = [IOBluetoothDeviceInquiry inquiryWithDelegate:self];
    self.inquiry.inquiryLength = 10;
    self.inquiry.updateNewDeviceNames = YES;
    [self.inquiry start];
    printf("[Wiimote] Press 1+2\n");
    fflush(stdout);
}

- (void)deviceInquiryDeviceFound:(IOBluetoothDeviceInquiry *)sender device:(IOBluetoothDevice *)device {
    NSString *name = device.name;
    if ([name containsString:@"Nintendo"] || [name containsString:@"RVL"]) {
        printf("[Wiimote] Found: %s\n", [name UTF8String]);
        fflush(stdout);
        [sender stop];
        [self connectTo:device];
    }
}

- (void)connectTo:(IOBluetoothDevice *)device {
    if (self.connecting) return;
    self.connecting = YES;
    self.device = device;
    printf("[Wiimote] Connecting...\n");
    fflush(stdout);
    
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
            [self onConnected];
        } else {
            printf("[Wiimote] Interrupt failed: %d\n", r);
            fflush(stdout);
            self.connecting = NO;
        }
    } else {
        printf("[Wiimote] Control failed: %d\n", r);
        fflush(stdout);
        self.connecting = NO;
    }
}

- (void)onConnected {
    printf("[Wiimote] CONNECTED!\n");
    fflush(stdout);
    
    [self setLED:0x10];
    usleep(50000);
    
    [self setRumble:YES];
    usleep(300000);
    [self setRumble:NO];
    printf("[Wiimote] Rumble test complete\n");
    fflush(stdout);
    
    [self setReportingMode:0x37];
    usleep(50000);
    
    [self initNunchuk];
    
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.05
                                                   target:self
                                                 selector:@selector(pollStatus)
                                                 userInfo:nil
                                                  repeats:YES];
}

- (void)initNunchuk {
    printf("\n========== INIT NUNCHUK ==========\n");
    fflush(stdout);
    
    [self writeMemory:0xA40040 data:[NSData dataWithBytes:"\x00" length:1]];
    usleep(50000);
    
    uint8_t key[] = {0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00};
    [self writeMemory:0xA40040 data:[NSData dataWithBytes:key length:16]];
    usleep(50000);
    
    [self writeMemory:0xA400F0 data:[NSData dataWithBytes:"\x55" length:1]];
    usleep(50000);
    
    [self setReportingMode:0x37];
    usleep(50000);
    
    [self requestStatus];
    
    self.initDone = YES;
    printf("[INIT] Nunchuk init complete\n");
    printf("==================================\n\n");
    fflush(stdout);
    
    // Start calibration
    self.calibrated = NO;
    self.calibrating = YES;
    self.calSamples = 0;
    self.calXSum = 0;
    self.calYSum = 0;
    printf("🔧 AUTO-CALIBRATING NUNCHUK...\n");
    printf("   DON'T TOUCH THE JOYSTICK!\n\n");
    fflush(stdout);
}

- (void)setIREnable:(BOOL)enable {
    NSMutableData *report = [NSMutableData data];
    uint8_t flags = 0x04;
    [report appendBytes:&flags length:1];
    
    uint8_t addrBytes[3] = {
        0xb0, 0x00, 0x30
    };
    [report appendBytes:addrBytes length:3];
    
    uint8_t size = 1;
    [report appendBytes:&size length:1];
    uint8_t data = enable ? 0x04 : 0x00;
    [report appendBytes:&data length:1];
    
    [self sendOutputReport:0x16 dataWithData:report];
}

- (void)pollStatus {
    [self readMemory:0xA40008 size:6];
    self.statusCount++;
    if (self.statusCount % 10 == 0) {
        [self requestStatus];
    }
}

- (void)writeMemory:(uint32_t)address data:(NSData *)data {
    if (!self.ctrl || data.length > 16) return;
    
    NSMutableData *report = [NSMutableData data];
    uint8_t flags = 0x04;
    [report appendBytes:&flags length:1];
    
    uint8_t addrBytes[3] = {
        (address >> 16) & 0xFF,
        (address >> 8) & 0xFF,
        address & 0xFF
    };
    [report appendBytes:addrBytes length:3];
    
    uint8_t size = data.length;
    [report appendBytes:&size length:1];
    [report appendData:data];
    
    [self sendOutputReport:0x16 dataWithData:report];
}

- (void)readMemory:(uint32_t)address size:(uint16_t)size {
    if (!self.ctrl) return;
    
    NSMutableData *report = [NSMutableData data];
    uint8_t space = 0x04;
    [report appendBytes:&space length:1];
    
    uint8_t slaveAddr = 0x00;
    [report appendBytes:&slaveAddr length:1];
    
    uint8_t addrBytes[2] = { (address >> 8) & 0xFF, address & 0xFF };
    [report appendBytes:addrBytes length:2];
    
    uint8_t sizeBytes[2] = { (size >> 8) & 0xFF, size & 0xFF };
    [report appendBytes:sizeBytes length:2];
    
    [self sendOutputReport:0x17 dataWithData:report];
}

- (void)sendOutputReport:(uint8_t)reportID dataWithData:(NSData *)data {
    if (!self.ctrl) return;
    
    NSMutableData *report = [NSMutableData data];
    uint8_t header = 0xA2;
    [report appendBytes:&header length:1];
    [report appendBytes:&reportID length:1];
    [report appendData:data];
    
    [self.ctrl writeSync:(void *)report.bytes length:report.length];
}

- (void)setLED:(int)mask {
    uint8_t led[] = {0xA2, 0x11, (uint8_t)mask};
    [self.ctrl writeSync:led length:3];
}

- (void)setReportingMode:(uint8_t)mode {
    uint8_t report[] = {0xA2, 0x12, 0x04, mode};
    [self.ctrl writeSync:report length:4];
    printf("[Wiimote] Mode: 0x%02X\n", mode);
    fflush(stdout);
}

- (void)requestStatus {
    uint8_t status[] = {0xA2, 0x15, 0x00};
    [self.ctrl writeSync:status length:3];
}

- (void)setRumble:(BOOL)enable {
    uint8_t rumble[] = {0xA2, 0x10, enable ? 0x01 : 0x00};
    [self.ctrl writeSync:rumble length:3];
}

- (void)parseNunchukData:(uint8_t *)decrypted withID:(uint8_t)id {
    int rawX = decrypted[0];
    int rawY = decrypted[1];
    
    // Handle calibration
    if (self.calibrating && self.extConnected) {
        self.calXSum += rawX;
        self.calYSum += rawY;
        self.calSamples++;
        
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
    
    if (!self.calibrated) return;
    
    // BUTTONS - ALWAYS CHECK (even when idle!)
    self.cPressed = ((decrypted[5] & 0x02) == 0);
    self.zPressed = !((decrypted[5] & 0x01) == 0);
    
    // JOYSTICK - Invert Y
    int centeredX = rawX - self.joyXCenter;
    int centeredY = -(rawY - self.joyYCenter);  // FIX: Invert Y
    
    int deadzone = 15;
    
    if (abs(centeredX) < deadzone) {
        centeredX = 0;
    }
    if (abs(centeredY) < deadzone) {
        centeredY = 0;
    }
    
    self.joyX = centeredX;
    self.joyY = centeredY;
    
    // DISPLAY - Always show buttons
    if (centeredX != 0 || centeredY != 0) {
        char *direction;
        if (abs(centeredX) > abs(centeredY)) {
            direction = (centeredX > 0) ? "RIGHT" : "LEFT";
        } else {
            direction = (centeredY > 0) ? "DOWN" : "UP";
        }
        
        double magnitude = sqrt(centeredX*centeredX + centeredY*centeredY);
        printf("\r[DATA 0x%02X] X:%+4d Y:%+4d | Dir: %-8s | Mag: %6.0f | C:%d Z:%d   ",
               id, centeredX, centeredY, direction, magnitude, self.cPressed, self.zPressed);
    } else {
        // Show buttons even when idle
        printf("\r[DATA 0x%02X] IDLE                          | C:%d Z:%d   ",
               id, self.cPressed, self.zPressed);
    }
    fflush(stdout);
}

- (void)l2capChannelData:(IOBluetoothL2CAPChannel *)ch data:(void *)dp length:(size_t)len {
    uint8_t *d = (uint8_t *)dp;
    if (len < 2) return;
    if (d[0] != 0xA1) return;
    
    uint8_t id = d[1];
    
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
                self.initDone = NO;
                self.calibrated = NO;
                self.calibrating = YES;
                self.calSamples = 0;
                self.calXSum = 0;
                self.calYSum = 0;
                [self initNunchuk];
                [self requestStatus];
            } else {
                self.initDone = NO;
                self.joyX = 0;
                self.joyY = 0;
                self.calibrated = NO;
                self.calibrating = NO;
            }
        }
        return;
    }
    
    if (id == 0x21 && len >= 10) {
        if (d[5] == 0xA4 && d[6] == 0x00 && d[7] == 0xFE) {
            if (d[8] == 0x00 && d[9] == 0x00) {
                self.extConnected = YES;
                printf("\n[READ 0x21] ✅ NUNCHUK CONFIRMED! (Type: 0x0000)\n");
                fflush(stdout);
            }
            return;
        }
        
        if (d[5] == 0xA4 && d[6] == 0x00 && d[7] == 0x08 && len >= 13) {
            uint8_t *data = d + 8;
            
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
            
            [self parseNunchukData:decrypted withID:id];
            return;
        }
        
        if (d[5] == 0xA4 && d[6] == 0x00 && d[7] == 0x40 && len >= 16) {
            printf("\n[READ 0x21] Extension key written\n");
            fflush(stdout);
            return;
        }
        return;
    }
    
    if (id == 0x22) {
        printf("[ACK 0x22] Report 0x%02X %s\n", d[2], d[3] == 0 ? "✅ OK" : "❌ ERROR");
        fflush(stdout);
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
        
        [self parseNunchukData:decrypted withID:id];
    }
}

- (void)disconnect {
    if (self.ctrl) {
        [self setRumble:NO];
    }
    [self.ctrl closeChannel];
    [self.intr closeChannel];
    self.ctrl = nil;
    self.intr = nil;
    [self.device closeConnection];
    self.device = nil;
    self.connecting = NO;
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
echo -e "${CYAN}📱 Run and look at the RAW data:${NC}"
echo -e "   $APP_BUNDLE/Contents/MacOS/$APP_NAME"