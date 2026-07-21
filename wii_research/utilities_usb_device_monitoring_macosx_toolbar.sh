#!/bin/bash
# build-usb-monitor-toolbar.sh - macOS Menu Bar App for USB Device Monitoring
# Shows USB device count with ▫️0 or 🟦{n} indicators in menu bar

# ===============================================
# 1. COLOR OUTPUT & BANNER
# ===============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo -e "${PURPLE}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║         USB DEVICE MONITOR - macOS MENU BAR APP               ║"
echo "║         Shows ▫️0 or 🟦{n} for connected USB devices           ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ===============================================
# 2. CHECK REQUIREMENTS
# ===============================================
echo -e "${CYAN}🔍 Checking build requirements...${NC}"

MACOS_VERSION=$(sw_vers -productVersion)
echo -e "   macOS Version: ${CYAN}$MACOS_VERSION${NC}"

if ! xcode-select -p &> /dev/null; then
    echo -e "${RED}❌ Xcode command line tools not installed${NC}"
    echo -e "${YELLOW}   Installing...${NC}"
    xcode-select --install
    exit 1
fi

SDK_PATH=$(xcrun --show-sdk-path --sdk macosx 2>/dev/null)
if [ -z "$SDK_PATH" ]; then
    echo -e "${RED}❌ macOS SDK not found${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Build requirements met${NC}"

# ===============================================
# 3. CREATE PROJECT STRUCTURE
# ===============================================
APP_NAME="USBDeviceMonitor"
BUILD_DIR="USBDeviceMonitor_Build"
ICON_URL="https://cdn.sdappnet.cloud/rtx/images/utilities_usb_device_monitoring_macosx_toolbar.png"
TOOLBAR_ICON_URL=""

echo ""
echo -e "${CYAN}📁 Creating project structure...${NC}"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"/{src,resources,assets}
cd "$BUILD_DIR" || exit

# ===============================================
# 4. CREATE SOURCE FILES
# ===============================================
echo -e "${CYAN}📝 Creating source files...${NC}"

# AppDelegate.h
cat > "src/AppDelegate.h" << 'EOF'
#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>
@end
EOF

# USBDeviceManager.h
cat > "src/USBDeviceManager.h" << 'EOF'
#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface USBDeviceManager : NSObject

@property (nonatomic, readonly) NSInteger deviceCount;
@property (nonatomic, readonly) NSArray<NSDictionary *> *devices;
@property (nonatomic, copy) void (^onDevicesChanged)(void);

- (void)startMonitoring;
- (void)stopMonitoring;
- (NSString *)getStatusText;
- (NSString *)getStatusEmoji;
- (void)refreshDevices;

@end

NS_ASSUME_NONNULL_END
EOF

# USBDeviceManager.m
cat > "src/USBDeviceManager.m" << 'EOF'
#import "USBDeviceManager.h"
#import <Foundation/Foundation.h>

@interface USBDeviceManager ()
@property (nonatomic, assign) NSInteger deviceCount;
@property (nonatomic, strong) NSArray<NSDictionary *> *devices;
@property (nonatomic, strong) NSTimer *updateTimer;
@end

@implementation USBDeviceManager

- (instancetype)init {
    self = [super init];
    if (self) {
        _deviceCount = 0;
        _devices = @[];
        [self refreshDevices];
    }
    return self;
}

- (void)startMonitoring {
    NSLog(@"[USB] 🔍 Starting USB monitoring...");
    self.updateTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                         target:self
                                                       selector:@selector(refreshDevices)
                                                       userInfo:nil
                                                        repeats:YES];
}

- (void)stopMonitoring {
    NSLog(@"[USB] 🛑 Stopping USB monitoring");
    [self.updateTimer invalidate];
    self.updateTimer = nil;
}

- (void)refreshDevices {
    NSMutableArray *newDevices = [NSMutableArray array];
    
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/sbin/system_profiler";
    task.arguments = @[@"SPUSBDataType", @"-xml"];
    
    NSPipe *outputPipe = [NSPipe pipe];
    task.standardOutput = outputPipe;
    
    @try {
        [task launch];
        [task waitUntilExit];
        
        NSData *outputData = [outputPipe.fileHandleForReading readDataToEndOfFile];
        NSError *error = nil;
        NSArray *plist = [NSPropertyListSerialization propertyListWithData:outputData
                                                                   options:NSPropertyListImmutable
                                                                    format:NULL
                                                                     error:&error];
        
        if (!error && plist.count > 0) {
            [self parseUSBItems:plist[0] intoArray:newDevices];
        }
    } @catch (NSException *exception) {
        NSLog(@"[USB] Error scanning USB: %@", exception);
    }
    
    self.devices = [newDevices copy];
    NSInteger newCount = self.devices.count;
    
    if (newCount != self.deviceCount) {
        self.deviceCount = newCount;
        NSLog(@"[USB] 📊 Device count changed: %ld", (long)newCount);
        
        if (self.onDevicesChanged) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.onDevicesChanged();
            });
        }
    }
}

- (void)parseUSBItems:(NSDictionary *)item intoArray:(NSMutableArray *)array {
    if (item[@"_items"]) {
        for (NSDictionary *subItem in item[@"_items"]) {
            [self parseUSBItems:subItem intoArray:array];
        }
    } else {
        NSString *name = item[@"_name"] ?: @"Unknown Device";
        NSString *vendor = item[@"vendor_name"] ?: @"Unknown Vendor";
        NSString *productID = item[@"product_id"] ?: @"";
        NSString *vendorID = item[@"vendor_id"] ?: @"";
        NSString *speed = item[@"speed"] ?: @"Unknown";
        
        [array addObject:@{
            @"name": name,
            @"vendor": vendor,
            @"productID": productID,
            @"vendorID": vendorID,
            @"speed": speed
        }];
    }
}

- (NSString *)getStatusText {
    if (self.deviceCount == 0) {
        return @"▫️0";
    } else {
        return [NSString stringWithFormat:@"🟦%ld", (long)self.deviceCount];
    }
}

- (NSString *)getStatusEmoji {
    if (self.deviceCount == 0) {
        return @"▫️";
    } else {
        return @"🟦";
    }
}

@end
EOF

# AppDelegate.m
cat > "src/AppDelegate.m" << 'EOF'
#import "AppDelegate.h"
#import "USBDeviceManager.h"

@interface AppDelegate ()
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) USBDeviceManager *usbManager;
@property (nonatomic, strong) NSTimer *refreshTimer;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    NSLog(@"[USBMonitor] 🚀 ========== APPLICATION LAUNCHING ==========");
    
    self.usbManager = [[USBDeviceManager alloc] init];
    
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    
    // IMPORTANT: ONLY SHOW TEXT, NO ICON
    self.statusItem.button.image = nil;  // Ensure no image is set
    self.statusItem.button.title = @"";  // Start empty, will be set by updateStatusText
    
    // Set initial status text
    [self updateStatusText];
    
    // Create menu
    NSMenu *menu = [[NSMenu alloc] init];
    
    NSMenuItem *statusHeader = [[NSMenuItem alloc] initWithTitle:@"USB Devices"
                                                           action:nil
                                                    keyEquivalent:@""];
    statusHeader.enabled = NO;
    [menu addItem:statusHeader];
    
    [menu addItem:[NSMenuItem separatorItem]];
    
    // Dynamic device list will be populated here
    NSMenuItem *loadingItem = [[NSMenuItem alloc] initWithTitle:@"Scanning..."
                                                          action:nil
                                                   keyEquivalent:@""];
    loadingItem.enabled = NO;
    [menu addItem:loadingItem];
    
    [menu addItem:[NSMenuItem separatorItem]];
    
    NSMenuItem *refreshItem = [[NSMenuItem alloc] initWithTitle:@"Refresh Now"
                                                          action:@selector(refreshDevices:)
                                                   keyEquivalent:@"r"];
    refreshItem.target = self;
    [menu addItem:refreshItem];
    
    [menu addItem:[NSMenuItem separatorItem]];
    
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit"
                                                       action:@selector(quitApp:)
                                                keyEquivalent:@"q"];
    quitItem.target = self;
    [menu addItem:quitItem];
    
    self.statusItem.menu = menu;
    
    // Start monitoring
    __weak typeof(self) weakSelf = self;
    self.usbManager.onDevicesChanged = ^{
        [weakSelf updateStatusText];
        [weakSelf rebuildMenu];
    };
    
    [self.usbManager startMonitoring];
    [self rebuildMenu];
}

- (void)updateStatusText {
    NSString *statusText = [self.usbManager getStatusText];
    self.statusItem.button.title = statusText;
    
    // Set tooltip with device count
    if (self.usbManager.deviceCount == 0) {
        self.statusItem.button.toolTip = @"No USB devices connected";
    } else {
        self.statusItem.button.toolTip = [NSString stringWithFormat:@"%ld USB device(s) connected", 
                                          (long)self.usbManager.deviceCount];
    }
}

- (void)rebuildMenu {
    NSMenu *menu = self.statusItem.menu;
    
    // Remove all items after the first two (header and separator)
    while (menu.numberOfItems > 2) {
        [menu removeItemAtIndex:2];
    }
    
    // Add device list
    if (self.usbManager.deviceCount == 0) {
        NSMenuItem *noDevicesItem = [[NSMenuItem alloc] initWithTitle:@"▫️ No devices connected"
                                                                action:nil
                                                         keyEquivalent:@""];
        noDevicesItem.enabled = NO;
        [menu insertItem:noDevicesItem atIndex:2];
    } else {
        for (NSDictionary *device in self.usbManager.devices) {
            NSString *deviceName = device[@"name"] ?: @"Unknown Device";
            NSString *vendor = device[@"vendor"] ?: @"Unknown";
            NSString *speed = device[@"speed"] ?: @"";
            
            NSString *title = [NSString stringWithFormat:@"🟦 %@", deviceName];
            NSMenuItem *deviceItem = [[NSMenuItem alloc] initWithTitle:title
                                                                 action:nil
                                                          keyEquivalent:@""];
            
            // Create submenu with details
            NSMenu *detailMenu = [[NSMenu alloc] init];
            
            NSMenuItem *vendorItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Vendor: %@", vendor]
                                                                 action:nil
                                                          keyEquivalent:@""];
            vendorItem.enabled = NO;
            [detailMenu addItem:vendorItem];
            
            if (speed.length > 0) {
                NSMenuItem *speedItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Speed: %@", speed]
                                                                    action:nil
                                                             keyEquivalent:@""];
                speedItem.enabled = NO;
                [detailMenu addItem:speedItem];
            }
            
            NSString *productID = device[@"productID"];
            if (productID.length > 0) {
                NSMenuItem *productItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Product ID: %@", productID]
                                                                      action:nil
                                                               keyEquivalent:@""];
                productItem.enabled = NO;
                [detailMenu addItem:productItem];
            }
            
            deviceItem.submenu = detailMenu;
            deviceItem.enabled = YES;
            
            [menu insertItem:deviceItem atIndex:2];
        }
    }
    
    // Add separator and refresh/quit items back
    [menu insertItem:[NSMenuItem separatorItem] atIndex:2 + self.usbManager.deviceCount];
    
    NSMenuItem *refreshItem = [[NSMenuItem alloc] initWithTitle:@"Refresh Now"
                                                          action:@selector(refreshDevices:)
                                                   keyEquivalent:@"r"];
    refreshItem.target = self;
    [menu insertItem:refreshItem atIndex:3 + self.usbManager.deviceCount];
    
    [menu insertItem:[NSMenuItem separatorItem] atIndex:4 + self.usbManager.deviceCount];
    
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit"
                                                       action:@selector(quitApp:)
                                                keyEquivalent:@"q"];
    quitItem.target = self;
    [menu insertItem:quitItem atIndex:5 + self.usbManager.deviceCount];
}

- (void)refreshDevices:(id)sender {
    NSLog(@"[USBMonitor] 🔄 Manual refresh triggered");
    [self.usbManager refreshDevices];
}

- (void)quitApp:(id)sender {
    [self.usbManager stopMonitoring];
    [NSApp terminate:nil];
}

@end
EOF

# main.m
cat > "src/main.m" << 'EOF'
#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        return NSApplicationMain(argc, argv);
    }
}
EOF

# Info.plist
cat > "resources/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>USBDeviceMonitor</string>
    <key>CFBundleDisplayName</key>
    <string>USB Device Monitor</string>
    <key>CFBundleIdentifier</key>
    <string>com.usb.devicemonitor</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>USBDeviceMonitor</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2025</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
EOF

# Entitlements.plist
cat > "src/entitlements.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
EOF

# ===============================================
# 5. CREATE ICON
# ===============================================
echo -e "${CYAN}🎨 Creating app icon...${NC}"

# Download main icon
ICON_FILENAME="${ICON_URL##*/}"
ICON_BASENAME="${ICON_FILENAME%\?*}"
TEMP_ICON="/tmp/${ICON_BASENAME}"
echo -e "${CYAN}   📥 Downloading main icon: ${ICON_URL}${NC}"
curl -s -L "$ICON_URL" -o "$TEMP_ICON"

# Download toolbar icon
TOOLBAR_TEMP_ICON="/tmp/toolbar_icon.png"
echo -e "${CYAN}   📥 Downloading toolbar icon: ${TOOLBAR_ICON_URL}${NC}"
curl -s -L "$TOOLBAR_ICON_URL" -o "$TOOLBAR_TEMP_ICON"

# Create iconset directory
ICONSET_DIR="$APP_NAME.iconset"
mkdir -p "$ICONSET_DIR"

if [ -f "$TEMP_ICON" ] && [ -s "$TEMP_ICON" ]; then
    echo -e "${GREEN}   ✅ Main icon downloaded, converting...${NC}"
    
    for SIZE in 16 32 64 128 256 512; do
        sips -z $SIZE $SIZE "$TEMP_ICON" --out "$ICONSET_DIR/icon_${SIZE}x${SIZE}.png" 2>/dev/null
        RETINA=$((SIZE * 2))
        sips -z $RETINA $RETINA "$TEMP_ICON" --out "$ICONSET_DIR/icon_${SIZE}x${SIZE}@2x.png" 2>/dev/null
    done
else
    echo -e "${YELLOW}   ⚠ Download failed, creating simple icon...${NC}"
    # Create simple USB icon
    for SIZE in 16 32 64 128 256 512; do
        printf "P6\n%d %d\n255\n" $SIZE $SIZE > "$ICONSET_DIR/temp_${SIZE}.ppm"
        perl -e "print pack('C*', (0,122,255) x ($SIZE*$SIZE))" >> "$ICONSET_DIR/temp_${SIZE}.ppm" 2>/dev/null
        sips -s format png "$ICONSET_DIR/temp_${SIZE}.ppm" --out "$ICONSET_DIR/icon_${SIZE}x${SIZE}.png" 2>/dev/null
        rm -f "$ICONSET_DIR/temp_${SIZE}.ppm"
    done
fi

# Convert iconset to icns
iconutil -c icns "$ICONSET_DIR" -o "resources/AppIcon.icns" 2>/dev/null

if [ -f "resources/AppIcon.icns" ]; then
    echo -e "${GREEN}   ✅ App icon created: resources/AppIcon.icns${NC}"
else
    echo -e "${YELLOW}   ⚠ Icon creation failed, continuing without icon${NC}"
    touch "resources/AppIcon.icns"
fi

# Save toolbar icon to assets
mkdir -p "assets"
if [ -f "$TOOLBAR_TEMP_ICON" ] && [ -s "$TOOLBAR_TEMP_ICON" ]; then
    cp "$TOOLBAR_TEMP_ICON" "assets/toolbar_icon.png"
    echo -e "${GREEN}   ✅ Toolbar icon saved to assets${NC}"
else
    # Create a simple toolbar icon
    echo -e "${YELLOW}   ⚠ Creating simple toolbar icon${NC}"
    # Create a small colored square for toolbar
    printf "P6\n18 18\n255\n" > "assets/temp_icon.ppm"
    perl -e "print pack('C*', (0,122,255) x 324)" >> "assets/temp_icon.ppm" 2>/dev/null
    sips -s format png "assets/temp_icon.ppm" --out "assets/toolbar_icon.png" 2>/dev/null
    rm -f "assets/temp_icon.ppm"
fi

# Clean up
rm -rf "$ICONSET_DIR" "$TEMP_ICON" 2>/dev/null

# ===============================================
# 6. COMPILE APP
# ===============================================
echo ""
echo -e "${CYAN}🔨 Compiling USB Device Monitor...${NC}"

APP_BUNDLE="$APP_NAME.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/"{MacOS,Resources}

cp "resources/Info.plist" "$APP_BUNDLE/Contents/"
[ -f "resources/AppIcon.icns" ] && cp "resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"

echo -e "${CYAN}   Compiling source code...${NC}"

clang -framework Cocoa \
      -framework Foundation \
      -framework AppKit \
      -fobjc-arc \
      -Wno-deprecated-declarations \
      -mmacosx-version-min=11.0 \
      -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
      src/*.m 2> build_errors.log

if [ $? -eq 0 ]; then
    echo -e "${GREEN}   ✅ Compilation successful${NC}"
else
    echo -e "${RED}   ❌ Compilation failed${NC}"
    cat build_errors.log
    exit 1
fi

# ===============================================
# 7. COPY RESOURCES TO APP BUNDLE
# ===============================================
echo ""
echo -e "${CYAN}📦 Copying resources to app bundle...${NC}"

if [ -f "assets/toolbar_icon.png" ]; then
    cp "assets/toolbar_icon.png" "$APP_BUNDLE/Contents/Resources/"
    echo -e "${GREEN}   ✅ Toolbar icon copied to bundle${NC}"
fi

if [ -d "resources" ]; then
    cp -R resources/* "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || true
    echo -e "${GREEN}   ✅ Other resources copied${NC}"
fi

# ===============================================
# 8. SIGN THE APP
# ===============================================
echo ""
echo -e "${CYAN}🔏 Signing app...${NC}"

codesign --force --deep --sign - --entitlements src/entitlements.plist "$APP_BUNDLE" 2> sign_errors.log

if [ $? -eq 0 ]; then
    echo -e "${GREEN}   ✅ Code signing successful${NC}"
else
    echo -e "${YELLOW}   ⚠ Code signing failed (non-critical)${NC}"
fi

# ===============================================
# 9. INSTALL
# ===============================================
echo ""
echo -e "${CYAN}📋 Installing application...${NC}"

DESKTOP_APP="$HOME/Desktop/$APP_BUNDLE"
rm -rf "$DESKTOP_APP"
cp -R "$APP_BUNDLE" "$DESKTOP_APP"
echo -e "${GREEN}✅ Copied to Desktop${NC}"

mkdir -p "$HOME/Applications"
APP_PATH="$HOME/Applications/$APP_BUNDLE"
rm -rf "$APP_PATH"
cp -R "$APP_BUNDLE" "$APP_PATH"
echo -e "${GREEN}✅ Installed to ~/Applications${NC}"

# ===============================================
# 10. CREATE LAUNCH SCRIPTS
# ===============================================
cat > "Launch USB Monitor.command" << EOF
#!/bin/bash
echo "================================================"
echo "🚀 Launching USB Device Monitor"
echo "================================================"
echo ""
echo "Opening app from Applications folder..."
open "$HOME/Applications/$APP_BUNDLE"
echo ""
echo "✅ App launched! Check menu bar for 🔌 icon"
EOF
chmod +x "Launch USB Monitor.command"
cp "Launch USB Monitor.command" "$HOME/Desktop/"

cat > "Debug USB Monitor.command" << EOF
#!/bin/bash
echo "================================================"
echo "🐛 DEBUG MODE - USB Device Monitor"
echo "================================================"
echo ""
echo "📱 Launching with console output..."
echo "Press Ctrl+C to stop"
echo ""
echo "================================================"
"$HOME/Applications/$APP_BUNDLE/Contents/MacOS/$APP_NAME"
EOF
chmod +x "Debug USB Monitor.command"
cp "Debug USB Monitor.command" "$HOME/Desktop/"

# ===============================================
# 11. ADD TO DOCK
# ===============================================
echo -e "${CYAN}📌 Adding to Dock...${NC}"

DOCK_APPS=$(defaults read com.apple.dock persistent-apps 2>/dev/null || echo "[]")
if ! echo "$DOCK_APPS" | grep -q "$APP_NAME"; then
    defaults write com.apple.dock persistent-apps -array-add "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$APP_PATH</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"
    killall Dock 2>/dev/null &
    echo -e "${GREEN}   ✅ Added to Dock${NC}"
else
    echo -e "${YELLOW}   ⚠ App already in Dock${NC}"
fi

# ===============================================
# 12. SUMMARY
# ===============================================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     ✅ USB DEVICE MONITOR BUILT!                         ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}📍 LOCATIONS:${NC}"
echo -e "   Desktop app:     ${GREEN}$HOME/Desktop/$APP_BUNDLE${NC}"
echo -e "   Applications:    ${GREEN}$HOME/Applications/$APP_BUNDLE${NC}"
echo ""
echo -e "${CYAN}🔌 FEATURES:${NC}"
echo -e "   • Menu bar shows: ${GREEN}▫️0${NC} (no devices) or ${GREEN}🟦{n}${NC} (n devices connected)"
echo -e "   • Click for detailed device list"
echo -e "   • Real-time updates every 2 seconds"
echo -e "   • Device details in submenus"
echo ""
echo -e "${CYAN}🚀 TO USE:${NC}"
echo -e "   1. Launch the app from menu bar"
echo -e "   2. Look for 🔌 icon or device count in menu bar"
echo -e "   3. Click to see connected USB devices"
echo ""
echo -e "${GREEN}✅ Build complete!${NC}"

# This creates a proper macOS menu bar app that:
#     Shows ▫️0 in the menu bar when no USB devices are connected
#     Shows 🟦{n} (like 🟦3, 🟦5) when devices are connected
#     Updates in real-time every 2 seconds
#     Click to see detailed device list with submenus for each device
#     Follows the exact same structure as your Wiimote app with toolbar icons, proper bundling, and installation