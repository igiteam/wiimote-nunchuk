#!/bin/bash

# Wiimote Checker - Test if your Wiimote is detected

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║           WIIMOTE DETECTION & CONNECTIVITY TEST                ║"
echo "║          Press 1+2 on your Wiimote to test                    ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo ""
echo "📡 Checking Bluetooth..."
echo ""

# Method 1: Check using system_profiler (more reliable)
BT_CHECK=$(system_profiler SPBluetoothDataType | grep -i "State" | head -1 | awk '{print $2}' || true)

if [ "$BT_CHECK" != "On" ] && [ "$BT_CHECK" != "ON" ]; then
    # Method 2: Check using defaults
    BT_CHECK2=$(defaults read /Library/Preferences/com.apple.Bluetooth ControllerPowerState 2>/dev/null || echo "0")
    if [ "$BT_CHECK2" != "1" ]; then
        # Method 3: Check using IOBluetooth
        BT_CHECK3=$(system_profiler SPBluetoothDataType | grep -i "Bluetooth" | head -1 | grep -i "On" || true)
        if [ -z "$BT_CHECK3" ]; then
            echo -e "${YELLOW}⚠️ Cannot detect Bluetooth status. Checking if any Bluetooth devices exist...${NC}"
            BT_DEVICES=$(system_profiler SPBluetoothDataType | grep -i "Address" | head -1 || true)
            if [ -z "$BT_DEVICES" ]; then
                echo -e "${RED}❌ No Bluetooth devices found. Bluetooth may be OFF.${NC}"
                echo ""
                echo "Try turning Bluetooth ON from:"
                echo "  System Preferences → Bluetooth → Turn Bluetooth On"
                echo ""
                exit 1
            else
                echo -e "${GREEN}✅ Bluetooth appears to be ON${NC}"
            fi
        else
            echo -e "${GREEN}✅ Bluetooth is ON${NC}"
        fi
    else
        echo -e "${GREEN}✅ Bluetooth is ON${NC}"
    fi
else
    echo -e "${GREEN}✅ Bluetooth is ON${NC}"
fi

# Check for existing paired Wiimotes
echo ""
echo "🔍 Checking for previously paired Wiimotes..."
echo ""

PAIRED=$(system_profiler SPBluetoothDataType | grep -i "Nintendo\|RVL\|Wiimote\|Wii" || true)
if [ -n "$PAIRED" ]; then
    echo -e "${YELLOW}⚠️ Found previously paired Wiimote:${NC}"
    echo "$PAIRED"
    echo ""
    echo -e "${YELLOW}You may need to unpair it first:${NC}"
    echo "   System Preferences → Bluetooth → Find device → Remove"
    echo ""
else
    echo -e "${GREEN}✅ No paired Wiimotes found${NC}"
fi

# Start scanning for devices
echo ""
echo "🔍 Scanning for Wiimotes..."
echo -e "${YELLOW}Press 1+2 on your Wiimote NOW! (or SYNC button)${NC}"
echo ""

# Create a temporary file for scan results
SCAN_RESULTS=$(mktemp)

# Run Bluetooth scan
system_profiler SPBluetoothDataType > "$SCAN_RESULTS" 2>/dev/null

# Wait for scan to complete
sleep 3

# Check results
WIIMOTE_FOUND=$(cat "$SCAN_RESULTS" | grep -i "Nintendo\|RVL\|Wiimote\|Wii" || true)

if [ -n "$WIIMOTE_FOUND" ]; then
    echo -e "${GREEN}✅ Wiimote found!${NC}"
    echo ""
    echo "Wiimote Details:"
    echo "$WIIMOTE_FOUND"
    echo ""
else
    echo -e "${RED}❌ No Wiimote found.${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Make sure your Wiimote has fresh batteries"
    echo "  2. Press 1+2 buttons on the Wiimote (they should flash)"
    echo "  3. For third-party Wiimotes, try pressing the SYNC button"
    echo "  4. Make sure no other device is connected to the Wiimote"
    echo "  5. Try opening System Preferences → Bluetooth and look for it"
    echo ""
    rm -f "$SCAN_RESULTS"
    exit 1
fi

# Try to get more info about the Wiimote
WIIMOTE_ADDR=$(cat "$SCAN_RESULTS" | grep -A 10 -i "Nintendo\|RVL\|Wiimote\|Wii" | grep "Address:" | head -1 | awk '{print $2}' || true)

if [ -n "$WIIMOTE_ADDR" ]; then
    echo -e "${GREEN}📍 Wiimote Address: ${CYAN}$WIIMOTE_ADDR${NC}"
    echo ""
else
    # Try to get address from paired devices
    WIIMOTE_ADDR=$(system_profiler SPBluetoothDataType | grep -A 5 -i "Nintendo\|RVL\|Wiimote\|Wii" | grep "Address:" | head -1 | awk '{print $2}' || true)
    if [ -n "$WIIMOTE_ADDR" ]; then
        echo -e "${GREEN}📍 Wiimote Address: ${CYAN}$WIIMOTE_ADDR${NC}"
        echo ""
    fi
fi

# Clean up
rm -f "$SCAN_RESULTS"

echo "============================================================"
echo ""
echo -e "${GREEN}🎮 Wiimote detected successfully!${NC}"
echo ""
echo -e "${CYAN}What to try next:${NC}"
echo "  1. Try connecting with the main Wiimote app"
echo "  2. If connection fails, unpair and try again"
echo "  3. For third-party Wiimotes, try pressing SYNC button first"
echo ""
echo -e "${YELLOW}To unpair a Wiimote from command line:${NC}"
echo "   sudo defaults delete /Library/Preferences/com.apple.Bluetooth.plist"
echo "   (then restart Bluetooth)"
echo ""

echo ""
echo -e "${CYAN}Done!${NC}"