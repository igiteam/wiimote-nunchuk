#!/bin/bash
# Wiimote - BATTERY WITH EXTENSION EVENT HANDLING

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║              WIIMOTE - BATTERY + EXTENSION EVENT              ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

APP_NAME="Wiimote"
BUNDLE_ID="com.github.wiimote"

rm -rf "$APP_NAME"
mkdir -p "$APP_NAME"/src
cd "$APP_NAME" || exit

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

cat > "src/WiimoteManager.m" << 'EOF'
#import "WiimoteManager.h"
#import <IOBluetooth/IOBluetooth.h>
#import <AppKit/AppKit.h>

#define PSM_CTRL 0x11
#define PSM_INTR 0x13
#define PRINT(...) fprintf(stderr, __VA_ARGS__)

@interface WiimoteManager () <IOBluetoothDeviceInquiryDelegate, IOBluetoothL2CAPChannelDelegate>
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
@property (nonatomic, assign) int lastLf;
@property (nonatomic, assign) int buttons;
@property (nonatomic, assign) BOOL extConnected;
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
        _lastLf = -1;
        _buttons = 0;
        _extConnected = NO;
        PRINT("[Wiimote] Init\n");
        fflush(stderr);
    }
    return self;
}

- (void)start {
    if (self.running) return;
    self.running = YES;
    PRINT("[Wiimote] Starting...\n");
    fflush(stderr);
    [self startDiscovery];
}

- (void)stop {
    self.running = NO;
    [self.timer invalidate];
    self.timer = nil;
    [self disconnect];
    PRINT("[Wiimote] Stopped\n");
    fflush(stderr);
}

- (void)startDiscovery {
    self.inquiry = [IOBluetoothDeviceInquiry inquiryWithDelegate:self];
    self.inquiry.inquiryLength = 10;
    self.inquiry.updateNewDeviceNames = YES;
    [self.inquiry start];
    PRINT("[Wiimote] Press 1+2\n");
    fflush(stderr);
}

- (void)deviceInquiryDeviceFound:(IOBluetoothDeviceInquiry *)sender device:(IOBluetoothDevice *)device {
    NSString *name = device.name;
    if ([name containsString:@"Nintendo"] || [name containsString:@"RVL"]) {
        PRINT("[Wiimote] Found: %s\n", [name UTF8String]);
        fflush(stderr);
        [sender stop];
        [self connectTo:device];
    }
}

- (void)connectTo:(IOBluetoothDevice *)device {
    if (self.connecting) return;
    self.connecting = YES;
    self.device = device;
    PRINT("[Wiimote] Connecting...\n");
    fflush(stderr);
    
    IOBluetoothL2CAPChannel *ch = nil;
    IOReturn r = [device openL2CAPChannelAsync:&ch withPSM:PSM_CTRL delegate:self];
    if (r == kIOReturnSuccess) {
        self.ctrl = ch;
    } else {
        PRINT("[Wiimote] Control failed: %d\n", r);
        fflush(stderr);
        self.connecting = NO;
    }
}

- (void)l2capChannelOpenComplete:(IOBluetoothL2CAPChannel *)ch status:(IOReturn)err {
    if (err != kIOReturnSuccess) {
        PRINT("[Wiimote] Channel failed: %d\n", err);
        fflush(stderr);
        self.connecting = NO;
        return;
    }
    
    if (ch.PSM == PSM_CTRL) {
        self.ctrl = ch;
        PRINT("[Wiimote] Control opened\n");
        fflush(stderr);
        uint8_t h[] = {0x43, 0x00};
        [self.ctrl writeAsync:h length:2 refcon:nil];
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            IOBluetoothL2CAPChannel *ic = nil;
            IOReturn r = [self.device openL2CAPChannelAsync:&ic withPSM:PSM_INTR delegate:self];
            if (r == kIOReturnSuccess) {
                self.intr = ic;
                PRINT("[Wiimote] Interrupt opening...\n");
                fflush(stderr);
            }
        });
    }
    else if (ch.PSM == PSM_INTR) {
        self.intr = ch;
        self.connecting = NO;
        PRINT("[Wiimote] Interrupt opened!\n");
        fflush(stderr);
        dispatch_async(dispatch_get_main_queue(), ^{ [self onConnected]; });
    }
}

- (void)onConnected {
    PRINT("[Wiimote] CONNECTED!\n");
    fflush(stderr);
    
    // LED 1
    [self setLED:0x10];
    usleep(50000);
    
    // Set reporting mode 0x37
    [self setReportingMode:0x37];
    usleep(50000);
    
    // Request status
    [self requestStatus];
    usleep(50000);
    
    // Rumble
    [self setRumble:YES];
    usleep(200000);
    [self setRumble:NO];
    
    [self showBattery];
    
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                   target:self
                                                 selector:@selector(checkStatus)
                                                 userInfo:nil
                                                  repeats:YES];
}

- (void)setLED:(int)mask {
    uint8_t led[] = {0xA2, 0x11, (uint8_t)mask};
    [self.ctrl writeAsync:led length:3 refcon:nil];
}

- (void)setReportingMode:(uint8_t)mode {
    uint8_t report[] = {0xA2, 0x12, 0x04, mode};
    [self.ctrl writeAsync:report length:4 refcon:nil];
    PRINT("[Wiimote] Reporting mode set to 0x%02X\n", mode);
    fflush(stderr);
}

- (void)requestStatus {
    uint8_t status[] = {0xA2, 0x15, 0x00};
    [self.ctrl writeAsync:status length:3 refcon:nil];
}

- (void)setRumble:(BOOL)enable {
    uint8_t rumble[] = {0xA2, 0x10, enable ? 0x01 : 0x00};
    [self.ctrl writeAsync:rumble length:3 refcon:nil];
}

- (void)checkStatus {
    [self requestStatus];
}

- (void)showBattery {
    PRINT("\033[2J\033[H");
    PRINT("╔══════════════════════════════════════════════════════════════╗\n");
    PRINT("║                    BATTERY STATUS                          ║\n");
    PRINT("╠══════════════════════════════════════════════════════════════╣\n");
    
    int bars = self.battery / 10;
    PRINT("║  BATTERY:  ");
    for (int i = 0; i < 10; i++) {
        PRINT("%s", i < bars ? "█" : "░");
    }
    PRINT(" %3d%%", self.battery);
    for (int i = 0; i < 30; i++) PRINT(" ");
    PRINT("║\n");
    
    PRINT("║  RAW VV:   0x%02X (%d)", self.batteryRaw, self.batteryRaw);
    for (int i = 0; i < 35; i++) PRINT(" ");
    PRINT("║\n");
    
    PRINT("║  LF FLAG:  0x%02X (ext:%d, LED1:%d)", 
          self.lf, (self.lf & 0x02) ? 1 : 0, (self.lf & 0x10) ? 1 : 0);
    for (int i = 0; i < 25; i++) PRINT(" ");
    PRINT("║\n");
    
    PRINT("║  UPDATES:  %d", self.statusCount);
    for (int i = 0; i < 43; i++) PRINT(" ");
    PRINT("║\n");
    
    if (self.extConnected) {
        PRINT("║  EXTENSION: ✅ CONNECTED");
    } else {
        PRINT("║  EXTENSION: ❌ DISCONNECTED");
    }
    for (int i = 0; i < 34; i++) PRINT(" ");
    PRINT("║\n");
    
    PRINT("╚══════════════════════════════════════════════════════════════╝\n");
    PRINT("\n");
    PRINT("  💡 LED1: %s\n", (self.lf & 0x10) ? "ON" : "OFF");
    PRINT("  🔌 Nunchuk: %s\n", self.extConnected ? "CONNECTED" : "DISCONNECTED");
    PRINT("  📊 Status reports: %d\n", self.statusCount);
    PRINT("\n");
    PRINT("  ⚡ Plug/unplug Nunchuk to test extension detection\n");
    fflush(stderr);
}

- (void)l2capChannelData:(IOBluetoothL2CAPChannel *)ch data:(void *)dp length:(size_t)len {
    uint8_t *d = (uint8_t *)dp;
    if (len < 2) return;
    
    if (d[0] != 0xA1) return;
    uint8_t id = d[1];
    
    // Status report 0x20
    if (id == 0x20 && len >= 8) {
        self.buttons = (d[2] << 8) | d[3];
        self.lf = d[4];
        self.batteryRaw = d[7];
        self.battery = (self.batteryRaw * 100) / 0xC0;
        self.statusCount++;
        
        BOOL extConnected = (self.lf & 0x02) != 0;
        
        // Check if extension status changed
        if (extConnected != self.extConnected) {
            self.extConnected = extConnected;
            PRINT("\n[Wiimote] 🔄 EXTENSION STATUS CHANGED: %s\n", 
                  extConnected ? "CONNECTED" : "DISCONNECTED");
            PRINT("  Re-sending reporting mode...\n");
            fflush(stderr);
            
            // CRITICAL: Re-send reporting mode after extension event
            [self setReportingMode:0x37];
            usleep(50000);
            
            // Request status again
            [self requestStatus];
        }
        
        [self showBattery];
        return;
    }
    
    // Data report 0x37
    if (id == 0x37 && len >= 21) {
        static int dataCount = 0;
        if (dataCount++ % 50 == 0) {
            PRINT("\n[Wiimote] 0x37 data flowing (report %d)\n", dataCount);
            PRINT("  Raw first 8 bytes: ");
            for (int i = 0; i < 8 && i < len; i++) {
                PRINT("%02X ", d[i]);
            }
            PRINT("\n");
            fflush(stderr);
        }
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

echo -e "${GREEN}✅ Installed!${NC}"
echo ""
echo -e "${CYAN}📱 Run:${NC}"
echo -e "   $HOME/Applications/$APP_BUNDLE/Contents/MacOS/$APP_NAME"
echo ""
echo -e "${CYAN}📺 Shows:${NC}"
echo -e "   BATTERY:  ██████░░░░  66%"
echo -e "   LF FLAG:  0x12 (ext:1, LED1:1)"
echo -e "   EXTENSION: ✅ CONNECTED / ❌ DISCONNECTED"
echo ""
echo -e "${GREEN}✅ Done!${NC}"