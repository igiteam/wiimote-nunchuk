#!/bin/bash
# build_usb_monitor.sh - Creates USB Monitor macOS App
# Monitors USB connections/disconnections in real-time

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
echo "║  🔌 USB DEVICE MONITOR - macOS App Builder                  ║"
echo "║     • Monitors all USB connections                          ║"
echo "║     • Real-time device detection                            ║"
echo "║     • Shows device details (vendor, product, speed)         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

APP_NAME="USB Device Monitor"
BUNDLE_ID="com.usb.monitor"
ICON_URL="https://cdn-icons-png.flaticon.com/512/753/753318.png"  # USB icon
BUILD_DIR="USB_Monitor_Build"

# Create build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"/{scripts,resources,temp}
cd "$BUILD_DIR" || exit 1

# ===============================================
# DOWNLOAD ICON
# ===============================================
echo -e "${CYAN}🎨 Downloading icon...${NC}"
TEMP_ICON="temp/usb_icon.png"
curl -s -L "$ICON_URL" -o "$TEMP_ICON"

if [ -f "$TEMP_ICON" ] && [ -s "$TEMP_ICON" ]; then
    echo -e "${GREEN}   ✅ Icon downloaded successfully!${NC}"
    ICON_SOURCE="$TEMP_ICON"
else
    echo -e "${YELLOW}   ⚠ Download failed, creating default icon${NC}"
    # Create simple USB icon using base64 (blue square with USB text)
    echo "iVBORw0KGgoAAAANSUhEUgAAAgAAAAIAAQMAAADOtgr5AAAAAXNSR0IB2cksfwAAAAlwSFlzAAALEwAACxMBAJqcGAAAAANQTFRFAAAAp3o92gAAAAF0Uk5TAEDm2GYAAABdSURBVHic7cEBDQAAAMKg909tDjegAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA4M8AxV4CAdMU5Y0AAAAASUVORK5CYII=" | base64 -D > "temp/simple_icon.png"
    ICON_SOURCE="temp/simple_icon.png"
fi

# ===============================================
# CREATE APP BUNDLE
# ===============================================
echo -e "${CYAN}📦 Creating app bundle...${NC}"
APP_BUNDLE="$APP_NAME.app"
mkdir -p "$APP_BUNDLE/Contents/"{MacOS,Resources}

# ===============================================
# CREATE Info.plist
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
</dict>
</plist>
EOF

# ===============================================
# CREATE MONITOR SCRIPT
# ===============================================
echo -e "${CYAN}📝 Creating USB monitor script...${NC}"

# Copy the USB monitor script from above
cat > "$APP_BUNDLE/Contents/Resources/usb_monitor.sh" << 'EOF'
#!/bin/bash
# USB Device Monitor - Real-time connection tracker

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Configuration
LOG_DIR="$HOME/Library/Logs/USB_Monitor"
LOG_FILE="$LOG_DIR/usb_monitor.log"
STATE_FILE="$LOG_DIR/last_usb_state.txt"
CHECK_INTERVAL=2
SCAN_COUNT=0
START_TIME=$(date +%s)

mkdir -p "$LOG_DIR"

print_header() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     🔌 USB DEVICE MONITOR - REAL-TIME CONNECTION TRACKER    ║${NC}"
    echo -e "${BLUE}║        Press Ctrl+C to stop monitoring                       ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_stats() {
    local uptime=$(( $(date +%s) - START_TIME ))
    local minutes=$((uptime / 60))
    local seconds=$((uptime % 60))
    
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    printf "${CYAN}  ⏱️  Uptime: %02d:%02d | 📊 Scans: %04d${NC}\n" $minutes $seconds $SCAN_COUNT
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
}

get_usb_devices() {
    system_profiler SPUSBDataType 2>/dev/null | awk '
    BEGIN { RS="\n\n"; FS="\n" }
    /Product ID:/ {
        product = ""; vendor = ""; location = ""; speed = ""
        
        for (i=1; i<=NF; i++) {
            if ($i ~ /Product ID:/) product_id = substr($i, index($i, ":") + 2)
            if ($i ~ /Vendor ID:/) vendor_id = substr($i, index($i, ":") + 2)
            if ($i ~ /Manufacturer:/) vendor = substr($i, index($i, ":") + 2)
            if ($i ~ /Product:/) product = substr($i, index($i, ":") + 2)
            if ($i ~ /Location ID:/) location = substr($i, index($i, ":") + 2)
            if ($i ~ /Speed:/) speed = substr($i, index($i, ":") + 2)
        }
        
        if (product != "" || vendor != "") {
            key = product_id "_" vendor_id "_" location
            printf "%s|%s|%s|%s|%s|%s|%s\n", 
                   key, 
                   product ? product : "Unknown Device", 
                   vendor ? vendor : "Unknown Vendor", 
                   product_id ? product_id : "Unknown",
                   vendor_id ? vendor_id : "Unknown",
                   speed ? speed : "Unknown",
                   location ? location : "Unknown"
        }
    }' | sort -u
}

compare_usb_state() {
    local current_state="$1"
    local previous_state="$2"
    
    echo "$current_state" | while IFS='|' read -r key product vendor product_id vendor_id speed location; do
        if ! echo "$previous_state" | grep -q "^$key|"; then
            echo "NEW|$key|$product|$vendor|$product_id|$vendor_id|$speed|$location"
        fi
    done
    
    echo "$previous_state" | while IFS='|' read -r key product vendor product_id vendor_id speed location; do
        if ! echo "$current_state" | grep -q "^$key|"; then
            echo "GONE|$key|$product|$vendor|$product_id|$vendor_id|$speed|$location"
        fi
    done
}

format_usb_info() {
    local device_info="$1"
    local action="$2"
    
    IFS='|' read -r _ key product vendor product_id vendor_id speed location <<< "$device_info"
    
    product=$(echo "$product" | xargs)
    vendor=$(echo "$vendor" | xargs)
    
    if [ "$action" = "NEW" ]; then
        echo -e "${GREEN}🔌 DEVICE CONNECTED${NC}"
    else
        echo -e "${RED}🔌 DEVICE DISCONNECTED${NC}"
    fi
    echo -e "   ├─ Product: ${WHITE}${product:-Unknown}${NC}"
    echo -e "   ├─ Manufacturer: ${WHITE}${vendor:-Unknown}${NC}"
    echo -e "   ├─ Product ID: ${CYAN}${product_id}${NC}"
    echo -e "   ├─ Vendor ID: ${CYAN}${vendor_id}${NC}"
    echo -e "   ├─ Speed: ${YELLOW}${speed}${NC}"
    echo -e "   └─ Location: ${BLUE}${location}${NC}"
}

# Main monitoring loop
print_header
echo -e "${GREEN}[System] 🚀 USB Monitor started at $(date)${NC}\n"

CURRENT_STATE=$(get_usb_devices)
echo "$CURRENT_STATE" > "$STATE_FILE"

if [ -n "$CURRENT_STATE" ]; then
    echo -e "${GREEN}📊 Initial USB devices detected:${NC}"
    echo "$CURRENT_STATE" | while IFS='|' read -r key product vendor product_id vendor_id speed location; do
        echo -e "   • ${WHITE}${product:-Unknown Device}${NC} - ${vendor:-Unknown}"
    done
else
    echo -e "${YELLOW}📊 No USB devices initially detected${NC}"
fi
echo ""

while true; do
    SCAN_COUNT=$((SCAN_COUNT + 1))
    
    CURRENT_STATE=$(get_usb_devices)
    
    if [ -f "$STATE_FILE" ]; then
        PREVIOUS_STATE=$(cat "$STATE_FILE")
    else
        PREVIOUS_STATE=""
    fi
    
    if [ "$CURRENT_STATE" != "$PREVIOUS_STATE" ]; then
        CHANGES=$(compare_usb_state "$CURRENT_STATE" "$PREVIOUS_STATE")
        
        if [ -n "$CHANGES" ]; then
            echo ""
            echo -e "${PURPLE}════════════════════════════════════════════════════════════════${NC}"
            echo -e "${PURPLE}  🔔 USB STATE CHANGE DETECTED at $(date '+%H:%M:%S')${NC}"
            echo -e "${PURPLE}════════════════════════════════════════════════════════════════${NC}"
            
            echo "$CHANGES" | while read -r change; do
                action=$(echo "$change" | cut -d'|' -f1)
                if [ "$action" = "NEW" ]; then
                    format_usb_info "$change" "NEW"
                    echo "$(date): CONNECTED - $(echo "$change" | cut -d'|' -f3,4)" >> "$LOG_FILE"
                elif [ "$action" = "GONE" ]; then
                    format_usb_info "$change" "GONE"
                    echo "$(date): DISCONNECTED - $(echo "$change" | cut -d'|' -f3,4)" >> "$LOG_FILE"
                fi
                echo ""
            done
            
            echo "$CURRENT_STATE" > "$STATE_FILE"
        fi
    fi
    
    if [ $((SCAN_COUNT % 15)) -eq 0 ]; then
        print_stats
        echo -e "${GREEN}📊 Currently connected: $(echo "$CURRENT_STATE" | grep -v '^$' | wc -l | xargs) device(s)${NC}"
        echo ""
    fi
    
    if [ $((SCAN_COUNT % 5)) -eq 0 ]; then
        echo -e "${CYAN}[Scan] 🔍 Checking USB ports... (scan #${SCAN_COUNT})${NC}"
    fi
    
    sleep $CHECK_INTERVAL
done
EOF

chmod +x "$APP_BUNDLE/Contents/Resources/usb_monitor.sh"

# ===============================================
# CREATE LAUNCHER
# ===============================================
cat > "$APP_BUNDLE/Contents/MacOS/launcher" << 'EOF'
#!/bin/bash
RESOURCES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../Resources" && pwd )"
MONITOR="$RESOURCES_DIR/usb_monitor.sh"

if [ ! -f "$MONITOR" ]; then
    osascript -e "display dialog \"USB Monitor not found at:\\n$MONITOR\" buttons {\"OK\"} default button 1 with icon stop"
    exit 1
fi

chmod +x "$MONITOR"

osascript <<APPLESCRIPT
tell application "Terminal"
    activate
    set newWindow to do script "clear; echo \"========================================\"; echo \"   USB DEVICE MONITOR\"; echo \"========================================\"; echo \"\"; \"$MONITOR\"; exit"
    set custom title of newWindow to "USB Device Monitor"
end tell
APPLESCRIPT
EOF

chmod +x "$APP_BUNDLE/Contents/MacOS/launcher"

# ===============================================
# PROCESS ICON
# ===============================================
if [ -f "$ICON_SOURCE" ]; then
    PNG_SOURCE="$APP_BUNDLE/Contents/Resources/icon_source.png"
    sips -s format png "$ICON_SOURCE" --out "$PNG_SOURCE" 2>/dev/null || cp "$ICON_SOURCE" "$PNG_SOURCE"
    
    if [ -f "$PNG_SOURCE" ]; then
        ICONSET_DIR="$APP_BUNDLE/Contents/Resources/AppIcon.iconset"
        mkdir -p "$ICONSET_DIR"
        
        for SIZE in 16 32 64 128 256 512; do
            sips -z $SIZE $SIZE "$PNG_SOURCE" --out "$ICONSET_DIR/icon_${SIZE}x${SIZE}.png" 2>/dev/null || true
            RETINA=$((SIZE * 2))
            sips -z $RETINA $RETINA "$PNG_SOURCE" --out "$ICONSET_DIR/icon_${SIZE}x${SIZE}@2x.png" 2>/dev/null || true
        done
        
        iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns" 2>/dev/null
        rm -rf "$ICONSET_DIR"
    fi
fi

# ===============================================
# INSTALL APP
# ===============================================
echo -e "${CYAN}📋 Installing to Applications...${NC}"
mkdir -p "$HOME/Applications"
APP_PATH="$HOME/Applications/$APP_BUNDLE"
rm -rf "$APP_PATH"
cp -R "$APP_BUNDLE" "$APP_PATH"

# Copy to Desktop
DESKTOP_APP="$HOME/Desktop/$APP_BUNDLE"
rm -rf "$DESKTOP_APP"
cp -R "$APP_BUNDLE" "$DESKTOP_APP"

# Create launcher
cat > "$HOME/Desktop/Launch USB Monitor.command" << EOF
#!/bin/bash
open "$APP_PATH"
EOF
chmod +x "$HOME/Desktop/Launch USB Monitor.command"

# ===============================================
# CLEANUP AND SUMMARY
# ===============================================
rm -rf temp

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     ✅ USB DEVICE MONITOR - INSTALLATION COMPLETE!          ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}📍 LOCATIONS:${NC}"
echo -e "   📁 App in Applications: ${GREEN}$APP_PATH${NC}"
echo -e "   📁 App on Desktop:      ${GREEN}$DESKTOP_APP${NC}"
echo -e "   🚀 Launcher:            ${GREEN}$HOME/Desktop/Launch USB Monitor.command${NC}"
echo ""
echo -e "${PURPLE}🎯 READY TO MONITOR USB DEVICES!${NC}"
echo ""

read -p "Launch the USB Monitor now? (y/N): " LAUNCH_NOW
if [[ "$LAUNCH_NOW" =~ ^[Yy]$ ]]; then
    echo -e "${CYAN}🚀 Launching USB Monitor...${NC}"
    open "$APP_PATH"
fi