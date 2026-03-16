#!/bin/bash
# wii_simple.sh - Simple Wii Remote checker with menu

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
WIITOOLS_DIR="$HOME/wii_tools"
mkdir -p "$WIITOOLS_DIR"

# Function to pair new Wii Remote (System Preferences method)
pair_new_wiimote() {
    echo ""
    echo -e "${CYAN}━━━━ PAIR NEW WII REMOTE ━━━━${NC}"
    echo ""
    echo "1. Press and HOLD buttons 1+2 on your Wii Remote"
    echo "2. LEDs should start blinking rapidly"
    echo ""
    read -p "Press Enter when ready (or 'q' to go back)..." choice
    
    if [[ "$choice" == "q" ]]; then
        return
    fi
    
    echo ""
    echo -e "${YELLOW}Scanning for 10 seconds...${NC}"
    
    # Scan for devices
    SCAN_FILE="$WIITOOLS_DIR/scan_$(date +%Y%m%d_%H%M%S).txt"
    blueutil --inquiry 10 > "$SCAN_FILE" 2>&1
    
    # Look for Wii Remote
    WI_MAC=$(grep -i "nintendo\|rvl\|wii" "$SCAN_FILE" | grep -o -E '([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}' | head -1)
    
    if [ -n "$WI_MAC" ]; then
        echo -e "${GREEN}✓ Found Wii Remote: $WI_MAC${NC}"
        
        # Calculate PIN (reverse MAC)
        CLEAN_MAC=$(echo "$WI_MAC" | tr -d ':-' | tr '[:lower:]' '[:upper:]')
        PIN_HEX=""
        for i in 10 8 6 4 2 0; do
            byte="${CLEAN_MAC:$i:2}"
            PIN_HEX="$PIN_HEX$byte"
        done
        
        echo -e "  PIN: $PIN_HEX"
        echo ""
        
        # Unpair if already exists
        blueutil --unpair "$WI_MAC" 2>/dev/null || true
        sleep 1
        
        # METHOD 1: Try Terminal pairing (often fails on macOS)
        echo -e "${YELLOW}Attempting Terminal pairing...${NC}"
        blueutil --pair "$WI_MAC" "$PIN_HEX" 2>/dev/null
        sleep 2
        
        # Check if paired
        if blueutil --paired 2>/dev/null | grep -q "$WI_MAC"; then
            echo -e "${GREEN}✓ Pairing successful!${NC}"
        else
            echo -e "${YELLOW}Terminal pairing failed - this is normal on macOS.${NC}"
            echo -e "${YELLOW}Opening System Preferences for manual pairing...${NC}"
            echo ""
            
            # METHOD 2: Open System Preferences for manual pairing
            echo -e "${CYAN}━━━━ MANUAL PAIRING INSTRUCTIONS ━━━━${NC}"
            echo ""
            echo "1. System Preferences will open to Bluetooth"
            echo "2. Look for 'Nintendo RVL-CNT-01' in the device list"
            echo "3. Click 'Pair' or 'Connect' next to it"
            echo "4. When asked for PIN, enter: ${GREEN}$PIN_HEX${NC}"
            echo "   (or as numbers: "
            for i in 0 2 4 6 8 10; do
                byte="${PIN_HEX:$i:2}"
                echo -n "$((0x$byte)) "
            done
            echo ")"
            echo ""
            echo "5. Click 'Continue' or 'Pair'"
            echo ""
            read -p "Press Enter to open System Preferences..."
            
            # Open Bluetooth preferences
            open "x-apple.systempreferences:com.apple.preference.bluetooth"
            
            echo ""
            echo -e "${YELLOW}Waiting for you to complete pairing...${NC}"
            echo "After pairing in System Preferences, come back here."
            read -p "Press Enter when pairing is complete..."
            
            # Check again
            if blueutil --paired 2>/dev/null | grep -q "$WI_MAC"; then
                echo -e "${GREEN}✓ Pairing successful via System Preferences!${NC}"
            else
                echo -e "${RED}✗ Still not paired. Let's try one more time with PIN display.${NC}"
                echo ""
                echo -e "${CYAN}PIN: ${GREEN}$PIN_HEX${NC}"
                echo "Try pairing manually in System Preferences now."
                read -p "Press Enter when done..."
            fi
        fi
        
        # Try to connect if paired
        if blueutil --paired 2>/dev/null | grep -q "$WI_MAC"; then
            echo -e "${YELLOW}Attempting to connect...${NC}"
            blueutil --connect "$WI_MAC" 2>/dev/null
            sleep 2
            
            if blueutil --is-connected "$WI_MAC" 2>/dev/null | grep -q "1"; then
                echo -e "${GREEN}✓ Connected!${NC}"
            else
                echo -e "${YELLOW}⚠ Paired but not connected.${NC}"
                echo "   Press any button on Wii Remote to wake it, then select Connect from menu."
            fi
        fi
    else
        echo -e "${RED}✗ No Wii Remote found in scan${NC}"
        echo ""
        echo "Troubleshooting:"
        echo "  • Make sure buttons 1+2 are HELD DOWN (not just pressed)"
        echo "  • LEDs should be blinking rapidly"
        echo "  • Check batteries"
        echo "  • Move remote closer"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

# Main menu loop
while true; do
    clear
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     SIMPLE WII REMOTE CHECKER         ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""

    # 1. CHECK IF BLUETOOTH IS ENABLED
    echo -e "${YELLOW}[1] Checking Bluetooth status...${NC}"
    BLUETOOTH_POWER=$(blueutil --power 2>/dev/null || echo "unknown")

    if [ "$BLUETOOTH_POWER" = "1" ]; then
        echo -e "  ${GREEN}✓ Bluetooth is ON${NC}"
    elif [ "$BLUETOOTH_POWER" = "0" ]; then
        echo -e "  ${RED}✗ Bluetooth is OFF${NC}"
        echo -e "  ${YELLOW}→ Turn it on: System Settings → Bluetooth${NC}"
    else
        echo -e "  ${RED}✗ Could not check Bluetooth status${NC}"
    fi
    echo ""

    # 2. SHOW ALL PAIRED DEVICES
    echo -e "${YELLOW}[2] Paired Bluetooth devices:${NC}"
    PAIRED=$(blueutil --paired 2>/dev/null)

    if [ -n "$PAIRED" ]; then
        echo "$PAIRED" | while read -r line; do
            # Extract MAC and name
            MAC=$(echo "$line" | grep -o -E '([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}' | head -1)
            NAME=$(echo "$line" | sed -E 's/.* (.*)$/\1/')
            
            # Check if connected
            CONNECTED=$(blueutil --is-connected "$MAC" 2>/dev/null || echo "0")
            
            if [ "$CONNECTED" = "1" ]; then
                echo -e "  ${GREEN}✓ $NAME ($MAC) - CONNECTED${NC}"
            else
                echo -e "  ${YELLOW}○ $NAME ($MAC) - not connected${NC}"
            fi
        done
    else
        echo -e "  No paired devices found"
    fi
    echo ""

    # 3. LOOK FOR WII REMOTE SPECIFICALLY
    echo -e "${YELLOW}[3] Looking for Wii Remote:${NC}"
    WI_FOUND=""
    WI_MAC=""

    # Check paired devices first
    WI_PAIRED=$(blueutil --paired 2>/dev/null | grep -i "nintendo\|rvl\|wii")

    if [ -n "$WI_PAIRED" ]; then
        WI_MAC=$(echo "$WI_PAIRED" | grep -o -E '([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}' | head -1)
        WI_NAME=$(echo "$WI_PAIRED" | sed -E 's/.* (.*)$/\1/')
        WI_CONNECTED=$(blueutil --is-connected "$WI_MAC" 2>/dev/null || echo "0")
        
        if [ "$WI_CONNECTED" = "1" ]; then
            echo -e "  ${GREEN}✓ Wii Remote FOUND and CONNECTED${NC}"
            echo -e "    Name: $WI_NAME"
            echo -e "    MAC:  $WI_MAC"
        else
            echo -e "  ${YELLOW}○ Wii Remote FOUND but not connected${NC}"
            echo -e "    Name: $WI_NAME"
            echo -e "    MAC:  $WI_MAC"
        fi
        WI_FOUND="yes"
    else
        echo -e "  ${YELLOW}○ No Wii Remote found${NC}"
    fi
    echo ""

    # 4. MENU OPTIONS
    echo -e "${CYAN}━━━━ WHAT DO YOU WANT TO DO? ━━━━${NC}"
    echo "  1) Pair a new Wii Remote"
    
    if [ -n "$WI_MAC" ]; then
        CLEAN_MAC=$(echo "$WI_MAC" | tr -d ':-')
        CONNECTED=$(blueutil --is-connected "$CLEAN_MAC" 2>/dev/null || echo "0")
        
        if [ "$CONNECTED" = "1" ]; then
            echo "  2) Disconnect Wii Remote"
        else
            echo "  2) Connect to Wii Remote"
        fi
        echo "  3) Forget/Unpair Wii Remote"
    fi
    
    echo "  0) Exit"
    echo ""
    read -p "Select option: " ACTION

    case $ACTION in
        1)
            pair_new_wiimote
            ;;
        2)
            if [ -n "$WI_MAC" ]; then
                echo ""
                CONNECTED=$(blueutil --is-connected "$CLEAN_MAC" 2>/dev/null || echo "0")
                
                if [ "$CONNECTED" = "1" ]; then
                    echo -e "${CYAN}Disconnecting...${NC}"
                    blueutil --disconnect "$CLEAN_MAC" 2>/dev/null
                    echo -e "${GREEN}✓ Disconnected${NC}"
                else
                    echo -e "${CYAN}Connecting...${NC}"
                    blueutil --connect "$CLEAN_MAC" 2>/dev/null
                    sleep 2
                    if blueutil --is-connected "$CLEAN_MAC" 2>/dev/null | grep -q "1"; then
                        echo -e "${GREEN}✓ Connected!${NC}"
                    else
                        echo -e "${YELLOW}⚠ Not connected. Press any button on Wii Remote and try again.${NC}"
                    fi
                fi
                echo ""
                read -p "Press Enter to continue..."
            fi
            ;;
        3)
            if [ -n "$WI_MAC" ]; then
                echo ""
                echo -e "${YELLOW}Are you sure? (y/n)${NC}"
                read -p "Forget Wii Remote? " confirm
                if [[ "$confirm" == "y" ]]; then
                    blueutil --unpair "$CLEAN_MAC" 2>/dev/null
                    echo -e "${GREEN}✓ Wii Remote forgotten${NC}"
                    WI_MAC=""
                fi
                echo ""
                read -p "Press Enter to continue..."
            fi
            ;;
        0)
            echo -e "${GREEN}Goodbye!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            sleep 1
            ;;
    esac
done