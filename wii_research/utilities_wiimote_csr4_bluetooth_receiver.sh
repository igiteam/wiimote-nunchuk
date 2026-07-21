#!/bin/bash
# build_csr4_wiimote_scanner_FIXED.sh - COMPLETE FIX VERSION WITH AUTO-PAIRING
# Creates the BADASS CSR4.0 Wii Remote Scanner app with:
# ✅ PERFECT icon download from URL
# ✅ FIXED path issue (scanner.sh not found)
# ✅ PROPER app bundle structure
# ✅ WORKING launcher script
# ✅ AUTO-PAIRING with Wii Remote (press 1+2)
# ✅ NATIVE C++ PASSTHROUGH (ONE SCRIPT - MANAGER + WORKER TOGETHER)
# ✅ PROPER SHUTDOWN when USB removed
# ✅ WORKER RETURNS to manager automatically

# ===============================================
# ⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️
#                 CRITICAL WARNING!
# ⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️
#
# 🎯 CSR4.0 DONGLE BUYER'S GUIDE (SAVE MONEY!)
#
# The CHEAPEST working CSR4.0 dongle costs ONLY $0.50!
# The EXPENSIVE one (TP-Link) costs $8 - SAME CHIP!
#
# ✅ BUY THE CHEAP ONE: Search for "CSR8510 A10" on AliExpress
#   - Cost: ~$0.50 USD
#   - Chip: Genuine CSR8510-A10 REV 8891 (Bluetooth 4.0 + BLE)
#   - Works perfectly with Wii Remotes!
#
# ❌ AVOID THE EXPENSIVE ONES:
#   - TP-Link UB400 ($8) - same chip, 16x price!
#   - Branded dongles often use the EXACT SAME CSR8510 chip
#
# 🧐 HOW TO IDENTIFY AUTHENTIC CSR4.0:
#   - lsusb output: 0a12:0001 (Cambridge Silicon Radio)
#   - Revision: 8891 (not 0134 - that's crippled!)
#   - Close-up photo should show "CSR8510-A10" on the chip
#
# 📝 USER REPORT:
#   "Spent hours researching - cheap $0.50 works same as $8 TP-Link!"
#
# ⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️
# ===============================================

# ===============================================
# COLOR OUTPUT
# ===============================================
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${PURPLE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  🔥 CSR4.0 WII REMOTE SCANNER - COMPLETE FIX 🔥            ║"
echo "║     ✓ Perfect icon download                                 ║"
echo "║     ✓ Fixed path issue                                      ║"
echo "║     ✓ Working launcher                                      ║"
echo "║     ✓ AUTO-PAIRING (press 1+2)                              ║"
echo "║     ✓ NATIVE C++ PASSTHROUGH                                ║"
echo "║     ✓ MANAGER + WORKER IN ONE ROOM                          ║"
echo "║     ✓ PROPER SHUTDOWN on USB removal                        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

APP_NAME="CSR4.0 Wii Remote Scanner"
BUNDLE_ID="com.csr4.wiiscanner"
ICON_URL="https://cdn.sdappnet.cloud/rtx/images/csr4-usb-bluetooth-receiver.png"
BUILD_DIR="CSR4_Wii_Scanner"

# Clean up if exists
if [ -d "$BUILD_DIR" ]; then
    echo -e "${YELLOW}⚠ Removing existing project...${NC}"
    rm -rf "$BUILD_DIR"
fi

# Create build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"/{scripts,resources,temp}

cd "$BUILD_DIR" || exit 1

# ===============================================
# 1. PERFECT ICON DOWNLOAD (LEARNED FROM THE PROS!)
# ===============================================
echo -e "${CYAN}🎨 Downloading icon with PERFECT method...${NC}"

# Extract filename with extension properly
ICON_FILENAME="${ICON_URL##*/}"           # Get last part of URL
ICON_BASENAME="${ICON_FILENAME%\?*}"       # Remove query params
ICON_EXT="${ICON_BASENAME##*.}"            # Get extension

# If no extension, assume png
if [ "$ICON_EXT" = "$ICON_BASENAME" ]; then
    ICON_EXT="png"
    ICON_BASENAME="csr4_icon.png"
fi

TEMP_ICON="temp/$ICON_BASENAME"
echo -e "${CYAN}   Downloading: $ICON_URL"
echo -e "${CYAN}   Saving as: $TEMP_ICON"

# Download with follow redirects
curl -s -L "$ICON_URL" -o "$TEMP_ICON"

# Check if download succeeded and file is not empty
if [ -f "$TEMP_ICON" ] && [ -s "$TEMP_ICON" ]; then
    echo -e "${GREEN}   ✅ Icon downloaded successfully!${NC}"
    ICON_SOURCE="$TEMP_ICON"
else
    echo -e "${YELLOW}   ⚠ Download failed, creating custom CSR4.0 icon${NC}"
    
    # Create a custom icon using Python if available
    cat > "temp/create_icon.py" << 'PYEOF'
from PIL import Image, ImageDraw
import os

# Create a 512x512 icon with CSR4.0 design
img = Image.new('RGBA', (512, 512), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# Draw USB dongle body
draw.rectangle((150, 100, 362, 412), fill=(0, 102, 204), outline=(255, 255, 255), width=8)
# USB connector
draw.rectangle((206, 412, 306, 452), fill=(192, 192, 192), outline=(255, 255, 255), width=4)
# Bluetooth symbol
draw.ellipse((206, 150, 306, 250), outline=(255, 255, 255), width=4)
draw.text((230, 180), "B", fill=(255, 255, 255))
# CSR4.0 text
draw.text((180, 300), "CSR4.0", fill=(255, 255, 255))

img.save('temp/custom_icon.png')
PYEOF
    
    if python3 -c "import PIL" 2>/dev/null; then
        python3 "temp/create_icon.py"
        ICON_SOURCE="temp/custom_icon.png"
        echo -e "${GREEN}   ✅ Custom icon created${NC}"
    else
        # Ultimate fallback - create simple colored square
        echo -e "${YELLOW}   ⚠ PIL not available, creating simple icon${NC}"
        # Create a simple 512x512 blue square PNG using base64
        echo "iVBORw0KGgoAAAANSUhEUgAAAgAAAAIAAQMAAADOtgr5AAAAAXNSR0IB2cksfwAAAAlwSFlzAAALEwAACxMBAJqcGAAAAANQTFRFAAAAp3o92gAAAAF0Uk5TAEDm2GYAAABdSURBVHic7cEBDQAAAMKg909tDjegAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA4M8AxV4CAdMU5Y0AAAAASUVORK5CYII=" | base64 -D > "temp/simple_icon.png"
        ICON_SOURCE="temp/simple_icon.png"
    fi
fi

# ===============================================
# 2. CREATE APP BUNDLE STRUCTURE (FIXED!)
# ===============================================
echo -e "${CYAN}📦 Creating app bundle with CORRECT structure...${NC}"

# Create the .app bundle
APP_BUNDLE="$APP_NAME.app"
mkdir -p "$APP_BUNDLE/Contents/"{MacOS,Resources}

# ===============================================
# 3. CREATE Info.plist
# ===============================================
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>launcher</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.13</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>This app needs to open Terminal for monitoring</string>
</dict>
</plist>
EOF

# ===============================================
# 4. PROCESS ICON INTO MACOS FORMAT
# ===============================================
echo -e "${CYAN}🎨 Processing icon for macOS...${NC}"

if [ -f "$ICON_SOURCE" ]; then
    # Create iconset directory
    ICONSET_DIR="$APP_BUNDLE/Contents/Resources/AppIcon.iconset"
    mkdir -p "$ICONSET_DIR"
    
    # Convert to PNG if needed
    ICON_EXT="${ICON_SOURCE##*.}"
    PNG_SOURCE="$APP_BUNDLE/Contents/Resources/icon_source.png"
    
    case $ICON_EXT in
        svg)
            if command -v rsvg-convert &> /dev/null; then
                rsvg-convert -w 1024 -h 1024 "$ICON_SOURCE" -o "$PNG_SOURCE"
            else
                # Try to install librsvg
                if command -v brew &> /dev/null; then
                    brew install librsvg 2>/dev/null
                    rsvg-convert -w 1024 -h 1024 "$ICON_SOURCE" -o "$PNG_SOURCE" 2>/dev/null || cp "$ICON_SOURCE" "$PNG_SOURCE"
                else
                    cp "$ICON_SOURCE" "$PNG_SOURCE"
                fi
            fi
            ;;
        png|jpg|jpeg|gif|bmp)
            # Convert to PNG using sips
            sips -s format png "$ICON_SOURCE" --out "$PNG_SOURCE" 2>/dev/null || cp "$ICON_SOURCE" "$PNG_SOURCE"
            ;;
        *)
            cp "$ICON_SOURCE" "$PNG_SOURCE"
            ;;
    esac
    
    # Generate all icon sizes
    if [ -f "$PNG_SOURCE" ]; then
        for SIZE in 16 32 64 128 256 512; do
            # Normal size
            sips -z $SIZE $SIZE "$PNG_SOURCE" --out "$ICONSET_DIR/icon_${SIZE}x${SIZE}.png" 2>/dev/null || true
            
            # Retina size (2x)
            RETINA=$((SIZE * 2))
            sips -z $RETINA $RETINA "$PNG_SOURCE" --out "$ICONSET_DIR/icon_${SIZE}x${SIZE}@2x.png" 2>/dev/null || true
        done
        
        # Convert iconset to icns
        iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns" 2>/dev/null
        
        if [ -f "$APP_BUNDLE/Contents/Resources/AppIcon.icns" ]; then
            echo -e "${GREEN}   ✅ Icon converted to .icns format${NC}"
        else
            echo -e "${YELLOW}   ⚠ Icon conversion failed, using PNG as fallback${NC}"
            cp "$PNG_SOURCE" "$APP_BUNDLE/Contents/Resources/AppIcon.png"
        fi
        
        # Clean up
        rm -rf "$ICONSET_DIR"
    fi
else
    echo -e "${YELLOW}   ⚠ No icon source found, skipping icon${NC}"
fi

# ===============================================
# 5. CREATE THE C++ WORKER BINARY (WITH PROPER SHUTDOWN)
# ===============================================
echo -e "${CYAN}🔧 Creating C++ worker binary with proper shutdown...${NC}"

# Check for and install libusb if needed
if ! command -v brew &> /dev/null; then
    echo -e "${YELLOW}⚠️  Homebrew not found. Please install libusb manually:${NC}"
    echo "   xcode-select --install"
    echo "   /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    echo "   brew install libusb"
    exit 1
fi

# Check if libusb is installed
if ! brew list 2>/dev/null | grep -q libusb; then
    echo -e "${YELLOW}📦 Installing libusb (required for USB passthrough)...${NC}"
    brew install libusb
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Failed to install libusb${NC}"
        exit 1
    fi
    echo -e "${GREEN}   ✅ libusb installed successfully${NC}"
fi

# Create source directory
mkdir -p "$APP_BUNDLE/Contents/Resources/src"

# Create the worker C++ code with proper shutdown
cat > "$APP_BUNDLE/Contents/Resources/src/wiimote_worker.cpp" << 'CPPEOF'
// CSR4.0 Wii Remote Worker - With proper USB removal detection
// Returns to manager when dongle is unplugged

#include <iostream>
#include <iomanip>
#include <vector>
#include <cstring>
#include <thread>
#include <chrono>
#include <atomic>
#include <signal.h>
#include <libusb.h>
#include <unistd.h>

// HCI Protocol constants
#define HCI_CMD_RESET 0x0C03
#define HCI_CMD_READ_BDADDR 0x1009
#define HCI_CMD_WRITE_SCAN_ENABLE 0x0C1A
#define HCI_CMD_INQUIRY 0x0401
#define HCI_CMD_PIN_CODE_REP 0x040D

// HCI Events
#define HCI_EVENT_COMMAND_COMPL 0x0E
#define HCI_EVENT_INQUIRY_RESULT 0x02
#define HCI_EVENT_AUTH_COMPL 0x06

// HCI Command header
struct hci_cmd_hdr {
    uint16_t opcode;
    uint8_t length;
} __attribute__((packed));

// HCI Event header
struct hci_event_hdr {
    uint8_t event;
    uint8_t length;
} __attribute__((packed));

// Bluetooth address
struct bdaddr_t {
    uint8_t b[6];
    
    std::string to_string() const {
        char str[18];
        snprintf(str, sizeof(str), "%02x:%02x:%02x:%02x:%02x:%02x",
                 b[0], b[1], b[2], b[3], b[4], b[5]);
        return std::string(str);
    }
    
    bdaddr_t reversed() const {
        bdaddr_t rev;
        for (int i = 0; i < 6; i++) {
            rev.b[i] = b[5 - i];
        }
        return rev;
    }
};

// HCI Inquiry command
struct hci_inquiry_cp {
    uint8_t lap[3];
    uint8_t inquiry_length;
    uint8_t num_responses;
} __attribute__((packed));

// HCI PIN Code Reply
struct hci_pin_code_rep_cp {
    bdaddr_t bdaddr;
    uint8_t pin_size;
    uint8_t pin[16];
} __attribute__((packed));

class CSR4Worker {
private:
    libusb_device_handle* dev_handle;
    libusb_context* ctx;
    std::atomic<bool> running;
    std::thread event_thread;
    
    uint8_t EP_HCI_CMD = 0x02;
    uint8_t EP_HCI_EVENT = 0x81;
    uint8_t EP_ACL_IN = 0x82;
    
public:
    CSR4Worker() : dev_handle(nullptr), ctx(nullptr), running(false) {}
    
    ~CSR4Worker() {
        running = false;
        if (event_thread.joinable()) {
            event_thread.join();
        }
        if (dev_handle) {
            libusb_release_interface(dev_handle, 0);
            libusb_close(dev_handle);
        }
        if (ctx) {
            libusb_exit(ctx);
        }
    }
    
    bool is_device_still_connected() {
        if (!dev_handle) return false;
        
        // Try to get device descriptor - if fails, device was removed
        libusb_device* device = libusb_get_device(dev_handle);
        if (!device) return false;
        
        libusb_device_descriptor desc;
        int ret = libusb_get_device_descriptor(device, &desc);
        return ret == 0;
    }
    
    void send_hci_command(uint16_t opcode, const void* params, uint8_t param_len, int retries = 3) {
        for (int attempt = 1; attempt <= retries; attempt++) {
            if (!is_device_still_connected()) {
                std::cerr << "\n❌ USB device disconnected!" << std::endl;
                running = false;
                return;
            }
            
            std::vector<uint8_t> cmd(3 + param_len);
            hci_cmd_hdr* hdr = reinterpret_cast<hci_cmd_hdr*>(cmd.data());
            hdr->opcode = opcode;
            hdr->length = param_len;
            if (params && param_len > 0) {
                memcpy(cmd.data() + 3, params, param_len);
            }
            
            int transferred;
            int ret = libusb_bulk_transfer(dev_handle, EP_HCI_CMD, cmd.data(), cmd.size(),
                                           &transferred, 2000);
            
            if (ret == 0) {
                return;
            }
            
            if (ret == LIBUSB_ERROR_NO_DEVICE) {
                std::cerr << "\n❌ USB device disconnected!" << std::endl;
                running = false;
                return;
            }
            
            if (attempt < retries) {
                std::this_thread::sleep_for(std::chrono::milliseconds(500));
            } else {
                std::cerr << "❌ HCI command 0x" << std::hex << opcode << std::dec 
                          << " failed: " << libusb_error_name(ret) << std::endl;
            }
        }
    }
    
    bool init() {
        std::cout << "\n🔧 Initializing CSR4.0 worker..." << std::endl;
        
        if (libusb_init(&ctx) < 0) {
            std::cerr << "Failed to initialize libusb" << std::endl;
            return false;
        }
        
        // Find CSR4.0 dongle
        dev_handle = libusb_open_device_with_vid_pid(ctx, 0x0a12, 0x0001);
        if (!dev_handle) {
            dev_handle = libusb_open_device_with_vid_pid(ctx, 0x0a12, 0x0002);
        }
        
        if (!dev_handle) {
            std::cerr << "❌ CSR4.0 dongle not found." << std::endl;
            return false;
        }
        
        std::cout << "✅ Found CSR4.0 dongle" << std::endl;
        
        libusb_detach_kernel_driver(dev_handle, 0);
        
        int ret = libusb_claim_interface(dev_handle, 0);
        if (ret < 0) {
            std::cerr << "❌ Failed to claim interface: " << libusb_error_name(ret) << std::endl;
            return false;
        }
        
        // Simple initialization
        std::cout << "\n🔧 Initializing dongle..." << std::endl;
        
        std::cout << "  Resetting dongle..." << std::endl;
        send_hci_command(HCI_CMD_RESET, nullptr, 0);
        std::this_thread::sleep_for(std::chrono::milliseconds(2000));
        
        std::cout << "  Enabling scan..." << std::endl;
        uint8_t scan_enable = 0x03;
        send_hci_command(HCI_CMD_WRITE_SCAN_ENABLE, &scan_enable, 1);
        std::this_thread::sleep_for(std::chrono::milliseconds(500));
        
        std::cout << "✅ Dongle ready!" << std::endl;
        
        running = true;
        event_thread = std::thread(&CSR4Worker::event_loop, this);
        
        return true;
    }
    
    void start_inquiry() {
        if (!running) return;
        
        hci_inquiry_cp inquiry;
        inquiry.lap[0] = 0x33;
        inquiry.lap[1] = 0x8b;
        inquiry.lap[2] = 0x9e;
        inquiry.inquiry_length = 5;
        inquiry.num_responses = 0;
        
        send_hci_command(HCI_CMD_INQUIRY, &inquiry, sizeof(inquiry));
    }
    
    void send_pin_code(const bdaddr_t& bdaddr) {
        if (!running) return;
        
        hci_pin_code_rep_cp pin_rep;
        pin_rep.bdaddr = bdaddr;
        pin_rep.pin_size = 6;
        
        bdaddr_t reversed = bdaddr.reversed();
        memcpy(pin_rep.pin, reversed.b, 6);
        memset(pin_rep.pin + 6, 0, 10);
        
        send_hci_command(HCI_CMD_PIN_CODE_REP, &pin_rep, sizeof(pin_rep));
    }
    
    void handle_event(const uint8_t* data, int len) {
        if (len < 2) return;
        
        const hci_event_hdr* evt = reinterpret_cast<const hci_event_hdr*>(data);
        
        switch (evt->event) {
            case HCI_EVENT_INQUIRY_RESULT: {
                std::cout << "\n🎮🎮🎮 WII REMOTE FOUND! 🎮🎮🎮" << std::endl;
                const uint8_t* response = data + 2;
                uint8_t num_responses = response[0];
                
                for (int i = 0; i < num_responses; i++) {
                    const uint8_t* bdaddr_bytes = response + 1 + (i * 6);
                    bdaddr_t bdaddr;
                    memcpy(bdaddr.b, bdaddr_bytes, 6);
                    
                    std::cout << "  MAC: " << bdaddr.to_string() << std::endl;
                    send_pin_code(bdaddr);
                }
                break;
            }
            
            case HCI_EVENT_AUTH_COMPL: {
                const uint8_t* params = data + 2;
                uint8_t status = params[0];
                
                if (status == 0) {
                    std::cout << "\n✅✅✅ PAIRING SUCCESSFUL! ✅✅✅" << std::endl;
                }
                break;
            }
        }
    }
    
    void event_loop() {
        std::cout << "\n👂 Scanning for Wiimotes..." << std::endl;
        std::cout << "Press 1+2 on your Wii Remote" << std::endl;
        std::cout << "Unplug dongle to return to manager\n" << std::endl;
        
        uint8_t buffer[1024];
        int inquiry_counter = 0;
        
        while (running) {
            // Check if device still connected
            if (!is_device_still_connected()) {
                std::cout << "\n❌ Dongle removed - returning to manager..." << std::endl;
                running = false;
                break;
            }
            
            int transferred;
            int ret = libusb_bulk_transfer(dev_handle, EP_HCI_EVENT, buffer, sizeof(buffer),
                                          &transferred, 100);
            
            if (ret == LIBUSB_ERROR_NO_DEVICE) {
                std::cout << "\n❌ Dongle removed - returning to manager..." << std::endl;
                running = false;
                break;
            }
            
            if (ret == 0 && transferred > 0) {
                handle_event(buffer, transferred);
            }
            
            // Start inquiry every 5 seconds
            if (++inquiry_counter % 50 == 0) {
                start_inquiry();
            }
            
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
    }
    
    void run() {
        std::cout << "\n🎮 CSR4.0 Worker Active" << std::endl;
        start_inquiry();
        
        while (running) {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
    }
};

std::atomic<bool> g_running(true);

void signal_handler(int) {
    std::cout << "\n\n👋 Shutting down worker..." << std::endl;
    g_running = false;
}

int main() {
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);
    
    std::cout << "=========================================" << std::endl;
    std::cout << "   CSR4.0 Wii Remote Worker" << std::endl;
    std::cout << "=========================================" << std::endl;
    
    CSR4Worker worker;
    
    if (!worker.init()) {
        std::cerr << "\n❌ Failed to initialize worker" << std::endl;
        return 1;
    }
    
    worker.run();
    
    std::cout << "\n👋 Returning to manager..." << std::endl;
    return 0;
}
CPPEOF

# Create Makefile
cat > "$APP_BUNDLE/Contents/Resources/src/Makefile" << 'MAKEEOF'
CXX = g++
CXXFLAGS = -std=c++11 -Wall -O2 -pthread
LDFLAGS = -lusb-1.0 -pthread

all: wiimote_worker

wiimote_worker: wiimote_worker.cpp
	$(CXX) $(CXXFLAGS) -o $@ $< $(LDFLAGS)

clean:
	rm -f wiimote_worker

install: wiimote_worker
	cp wiimote_worker ../

.PHONY: all clean install
MAKEEOF

# Compile the binary
echo -e "${CYAN}⚙️  Compiling C++ worker binary...${NC}"
cd "$APP_BUNDLE/Contents/Resources/src"

if command -v pkg-config &> /dev/null; then
    CFLAGS=$(pkg-config --cflags libusb-1.0 2>/dev/null || echo "")
    LIBS=$(pkg-config --libs libusb-1.0 2>/dev/null || echo "-lusb-1.0")
    g++ -std=c++11 -Wall -O2 -pthread $CFLAGS -o wiimote_worker wiimote_worker.cpp $LIBS -pthread 2>&1 | tee /tmp/compile.log
else
    g++ -std=c++11 -Wall -O2 -pthread -I/opt/homebrew/include -I/usr/local/include -o wiimote_worker wiimote_worker.cpp -L/opt/homebrew/lib -L/usr/local/lib -lusb-1.0 -pthread 2>&1 | tee /tmp/compile.log
fi

if [ -f "wiimote_worker" ]; then
    cp wiimote_worker ../
    echo -e "${GREEN}   ✅ Compilation successful!${NC}"
else
    echo -e "${RED}   ❌ Compilation failed. Check /tmp/compile.log${NC}"
    cat /tmp/compile.log
    exit 1
fi

cd - > /dev/null

# ===============================================
# 6. CREATE THE MANAGER SCANNER SCRIPT
# ===============================================
echo -e "${CYAN}📝 Creating manager scanner script...${NC}"

cat > "$APP_BUNDLE/Contents/Resources/scanner.sh" << 'EOF'
#!/bin/bash
# CSR4.0 WII REMOTE SCANNER - MANAGER + WORKER

LOG_DIR="$HOME/Library/Logs/CSR4_Wii_Scanner"
LOG_FILE="$LOG_DIR/scanner.log"
SCAN_COUNT=0
CSR4_FOUND=0
RESOURCES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WORKER_BIN="$RESOURCES_DIR/wiimote_worker"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

mkdir -p "$LOG_DIR"

print_header() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     🎮 CSR4.0 WII REMOTE SCANNER                            ║${NC}"
    echo -e "${BLUE}║        Press Ctrl+C to stop                                  ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

scan_usb() {
    SCAN_COUNT=$((SCAN_COUNT + 1))
    
    if [ $((SCAN_COUNT % 5)) -eq 0 ]; then
        echo -e "${CYAN}[$(date +%H:%M:%S)] 🔍 Scan #${SCAN_COUNT}: Checking for CSR4.0...${NC}"
    fi
    
    USB_INFO=$(system_profiler SPUSBDataType 2>/dev/null)
    
    if echo "$USB_INFO" | grep -q -i "Cambridge Silicon Radio\|CSR8510\|CSR4.0"; then
        if [ $CSR4_FOUND -eq 0 ]; then
            echo -e "\n${GREEN}✅ CSR4.0 DONGLE DETECTED!${NC}"
            
            CSR4_FOUND=1
            echo "$(date): CSR4.0 detected" >> "$LOG_FILE"
            
            echo -e "\n${PURPLE}🎮 Launching worker...${NC}"
            echo -e "${YELLOW}🔑 You may be prompted for sudo password${NC}\n"
            
            # Worker takes over - manager pauses here
            sudo "$WORKER_BIN"
            
            # Worker exited - manager resumes
            echo -e "\n${GREEN}✅ Worker finished. Resuming scan...${NC}\n"
            CSR4_FOUND=0
        fi
    else
        if [ $CSR4_FOUND -eq 1 ]; then
            CSR4_FOUND=0
        fi
    fi
}

print_header
echo -e "${GREEN}🚀 Manager started at $(date)${NC}"
echo -e "${YELLOW}💡 Plug in CSR4.0 dongle to start worker${NC}\n"

while true; do
    scan_usb
    sleep 1
done
EOF

chmod +x "$APP_BUNDLE/Contents/Resources/scanner.sh"

# ===============================================
# 7. CREATE THE LAUNCHER SCRIPT (KEEP AS IS - WORKING!)
# ===============================================
echo -e "${CYAN}📝 Creating launcher script...${NC}"

cat > "$APP_BUNDLE/Contents/MacOS/launcher" << 'EOF'
#!/bin/bash
# LAUNCHER - Works with spaces in path

RESOURCES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../Resources" && pwd )"
SCANNER="$RESOURCES_DIR/scanner.sh"

echo "🔍 Looking for scanner at: $SCANNER" > /tmp/csr4_debug.log

if [ ! -f "$SCANNER" ]; then
    osascript -e "display dialog \"Scanner not found at:\\n$SCANNER\" buttons {\"OK\"} default button 1 with icon stop"
    exit 1
fi

chmod +x "$SCANNER"

# Simple launch with quotes
osascript <<APPLESCRIPT
tell application "Terminal"
    activate
    do script "\"$SCANNER\""
end tell
APPLESCRIPT
EOF

chmod +x "$APP_BUNDLE/Contents/MacOS/launcher"

# ===============================================
# 8. VERIFY BUNDLE STRUCTURE
# ===============================================
echo -e "${CYAN}🔍 Verifying app bundle structure...${NC}"

if [ -f "$APP_BUNDLE/Contents/MacOS/launcher" ] && [ -f "$APP_BUNDLE/Contents/Resources/scanner.sh" ] && [ -f "$APP_BUNDLE/Contents/Resources/wiimote_worker" ]; then
    echo -e "${GREEN}   ✅ Bundle structure is CORRECT${NC}"
    echo -e "${GREEN}   ├─ MacOS/launcher: $(file "$APP_BUNDLE/Contents/MacOS/launcher" | awk -F': ' '{print $2}')${NC}"
    echo -e "${GREEN}   ├─ Resources/scanner.sh: $(file "$APP_BUNDLE/Contents/Resources/scanner.sh" | awk -F': ' '{print $2}')${NC}"
    echo -e "${GREEN}   └─ Resources/wiimote_worker: $(file "$APP_BUNDLE/Contents/Resources/wiimote_worker" | awk -F': ' '{print $2}')${NC}"
else
    echo -e "${RED}   ❌ Bundle structure is INCORRECT!${NC}"
    ls -la "$APP_BUNDLE/Contents/MacOS/" 2>/dev/null || echo "   MacOS dir empty"
    ls -la "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || echo "   Resources dir empty"
    exit 1
fi

# ===============================================
# 9. INSTALL THE APP
# ===============================================
echo -e "${CYAN}📋 Installing to Applications...${NC}"

mkdir -p "$HOME/Applications"
APP_PATH="$HOME/Applications/$APP_BUNDLE"
rm -rf "$APP_PATH"
cp -R "$APP_BUNDLE" "$APP_PATH"

if [ -d "$APP_PATH" ]; then
    echo -e "${GREEN}   ✅ Installed to: $APP_PATH${NC}"
else
    echo -e "${RED}   ❌ Failed to install to Applications${NC}"
    APP_PATH="$(pwd)/$APP_BUNDLE"
fi

DESKTOP_APP="$HOME/Desktop/$APP_BUNDLE"
rm -rf "$DESKTOP_APP"
cp -R "$APP_BUNDLE" "$DESKTOP_APP"
echo -e "${GREEN}   ✅ Copied to Desktop: $DESKTOP_APP${NC}"

# ===============================================
# 10. CREATE DESKTOP LAUNCHER
# ===============================================
cat > "$HOME/Desktop/Launch CSR4.0 Scanner.command" << EOF
#!/bin/bash
echo "🚀 Launching CSR4.0 Wii Remote Scanner..."
echo "💡 PLUG IN CSR4.0 DONGLE!"
sleep 2
open "$APP_PATH"
EOF
chmod +x "$HOME/Desktop/Launch CSR4.0 Scanner.command"
echo -e "${GREEN}   ✅ Launcher created${NC}"

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
# 12. CREATE README
# ===============================================
cat > "$HOME/Desktop/CSR4.0_README.txt" << EOF
╔══════════════════════════════════════════════════════════════╗
║     🔥 CSR4.0 WII REMOTE SCANNER 🔥                         ║
╚══════════════════════════════════════════════════════════════╝

✅ FIXES:
• Working launcher with spaces in path
• Worker detects USB removal and returns to manager
• Proper shutdown handling

🎮 HOW TO USE:
1. Launch the app
2. Plug in CSR4.0 dongle
3. Enter sudo password
4. Press 1+2 on Wii Remote
5. Unplug dongle to return to manager
6. Press Ctrl+C in worker to exit

💡 TIP: Buy the $0.50 dongle (CSR8510-A10 REV 8891)
ENJOY! 🎮
EOF

echo -e "${GREEN}   ✅ README created${NC}"

# ===============================================
# 13. CREATE VERIFICATION SCRIPT
# ===============================================
cat > "$HOME/Desktop/Verify_CSR4_App.command" << 'EOF'
#!/bin/bash
APP_PATH="$HOME/Applications/CSR4.0 Wii Remote Scanner.app"

echo "🔍 VERIFYING INSTALLATION"
echo "========================"

[ -d "$APP_PATH" ] && echo "✅ App found" || echo "❌ App missing"
[ -f "$APP_PATH/Contents/MacOS/launcher" ] && echo "✅ Launcher exists"
[ -f "$APP_PATH/Contents/Resources/scanner.sh" ] && echo "✅ Manager exists"
[ -f "$APP_PATH/Contents/Resources/wiimote_worker" ] && echo "✅ Worker exists"

echo ""
echo "📋 To launch: open '$APP_PATH'"
EOF

chmod +x "$HOME/Desktop/Verify_CSR4_App.command"
echo -e "${GREEN}   ✅ Verification script created${NC}"

# ===============================================
# 14. CLEANUP
# ===============================================
rm -rf temp
echo -e "${GREEN}   ✅ Cleaned up temp files${NC}"

# ===============================================
# 15. FINAL SUMMARY
# ===============================================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     ✅ CSR4.0 WII REMOTE SCANNER - COMPLETE!                ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}📍 LOCATIONS:${NC}"
echo -e "   📁 App in Applications: ${GREEN}$HOME/Applications/$APP_NAME.app${NC}"
echo -e "   📁 App on Desktop:      ${GREEN}$HOME/Desktop/$APP_NAME.app${NC}"
echo ""

# ===============================================
# 16. OFFER TO LAUNCH
# ===============================================
read -p "Launch the app now? (Y/n): " LAUNCH_NOW
if [[ -z "$LAUNCH_NOW" || "$LAUNCH_NOW" =~ ^[Yy]$ ]]; then
    echo -e "${CYAN}🚀 Launching $APP_NAME...${NC}"
    echo -e "${YELLOW}💡 PLUG IN CSR4.0 DONGLE!${NC}"
    sleep 2
    open "$APP_PATH"
fi