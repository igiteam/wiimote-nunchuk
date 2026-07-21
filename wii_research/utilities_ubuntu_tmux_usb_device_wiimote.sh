#!/bin/bash
# utilities_ubuntu_tmux_usb_device_wiimote.sh
# Ubuntu (Allwinner H3) USB Monitor + Wiimote Controller
# Runs in tmux with proper Wiimote pairing and nunchuk support

# ============================================
# Configuration
# ============================================
USB_SESSION="usb-monitor"
WIIMOTE_SESSION="wiimote-controller"
LOG_DIR="$HOME/device_monitor_logs"
USB_LOG_FILE="$LOG_DIR/usb_monitor.log"
WIIMOTE_LOG_FILE="$LOG_DIR/wiimote_controller.log"
USB_STATE_FILE="$LOG_DIR/last_usb_state.txt"
CHECK_INTERVAL=2
SCAN_COUNT=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# ============================================
# Helper Functions
# ============================================
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_DIR/setup.log"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_DIR/setup.log"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_DIR/setup.log"
}

section() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

check_command() {
    if ! command -v $1 &> /dev/null; then
        return 1
    fi
    return 0
}

# Function to calculate Wiimote PIN (reverse MAC bytes - same as macOS version)
calculate_wiimote_pin() {
    local mac_address="$1"
    # Remove separators and convert to uppercase
    local clean_mac=$(echo "$mac_address" | tr -d ':' | tr -d '-' | tr '[:lower:]' '[:upper:]')
    
    if [ ${#clean_mac} -ne 12 ]; then
        echo "ERROR: Invalid MAC length"
        return 1
    fi
    
    # Reverse the byte order for PIN (Wii Remote specific)
    local pin=""
    for i in 10 8 6 4 2 0; do
        pin+="${clean_mac:$i:2}"
    done
    
    echo "$pin"
}

# ============================================
# Start Script
# ============================================
clear
echo ""
echo -e "${PURPLE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${PURPLE}║                                                               ║${NC}"
echo -e "${PURPLE}║      🎮🔌 ALL-IN-ONE DEVICE MONITOR - Ubuntu (Allwinner H3)  ║${NC}"
echo -e "${PURPLE}║                                                               ║${NC}"
echo -e "${PURPLE}║      • USB Device Monitor (real-time connections)            ║${NC}"
echo -e "${PURPLE}║      • Wiimote Controller with Nunchuk WASD                  ║${NC}"
echo -e "${PURPLE}║      • Proper Bluetooth pairing (MAC reverse PIN)            ║${NC}"
echo -e "${PURPLE}║      • All run in tmux for persistence                        ║${NC}"
echo -e "${PURPLE}║                                                               ║${NC}"
echo -e "${PURPLE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

log "Starting All-in-One Device Monitor setup at $(date)"

# ============================================
# Install Dependencies
# ============================================
section "Installing Dependencies"

log "Updating package list..."
sudo apt-get update -y

log "Installing required packages..."
sudo apt-get install -y \
    tmux \
    usbutils \
    lsb-release \
    pciutils \
    htop \
    bc \
    bluez \
    bluez-tools \
    bluetooth \
    libbluetooth-dev \
    python3 \
    python3-pip \
    python3-evdev \
    python3-pyudev \
    libusb-1.0-0-dev \
    libudev-dev \
    joystick \
    jstest-gtk \
    evtest \
    xdotool \
    x11-utils

# Install Python packages for Wiimote
log "Installing Python packages for Wiimote support..."
pip3 install --user pybluez 2>/dev/null || warning "pybluez installation failed, trying alternative..."
pip3 install --user evdev 2>/dev/null
pip3 install --user pyudev 2>/dev/null

# Install cwiid for Wiimote (Ubuntu's version of wiiuse)
if ! check_command wminput; then
    log "Installing cwiid for Wiimote support..."
    sudo apt-get install -y cwiid wminput lswm
fi

# Check if tmux is installed
if ! check_command tmux; then
    error "Failed to install tmux"
fi
log "✅ Tmux installed successfully"

# Check Bluetooth service
log "Checking Bluetooth service..."
sudo systemctl enable bluetooth
sudo systemctl start bluetooth
if systemctl is-active --quiet bluetooth; then
    log "✅ Bluetooth service is running"
else
    warning "Bluetooth service not running, attempting to start..."
    sudo systemctl start bluetooth
fi

log "✅ All dependencies installed"

# ============================================
# Create Directory Structure
# ============================================
section "Setting Up Directories"

log "Creating log directory: $LOG_DIR"
mkdir -p "$LOG_DIR"

if [ ! -d "$LOG_DIR" ]; then
    error "Failed to create log directory"
fi
log "✅ Directories created"

# ============================================
# Create USB Monitor Script
# ============================================
section "Creating USB Monitor Script"

USB_MONITOR_SCRIPT="$LOG_DIR/usb_monitor_core.sh"

log "Creating USB monitor script at: $USB_MONITOR_SCRIPT"

cat > "$USB_MONITOR_SCRIPT" << 'EOF'
#!/bin/bash
# USB Device Monitor Core - Runs inside tmux

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
LOG_DIR="$HOME/device_monitor_logs"
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
    echo -e "${BLUE}║        Session: $(tmux display-message -p '#S')                                      ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_stats() {
    local uptime=$(( $(date +%s) - START_TIME ))
    local minutes=$((uptime / 60))
    local seconds=$((uptime % 60))
    local total_devices=$(lsusb | wc -l)
    
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    printf "${CYAN}  ⏱️  Uptime: %02d:%02d | 📊 Scans: %04d | 🔌 USB Buses: %d${NC}\n" $minutes $seconds $SCAN_COUNT $total_devices
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
}

get_usb_devices_simple() {
    lsusb | while read line; do
        bus=$(echo "$line" | awk '{print $2}')
        device=$(echo "$line" | awk '{print $4}' | sed 's/://')
        id=$(echo "$line" | awk '{print $6}')
        description=$(echo "$line" | cut -d' ' -f7-)
        
        # Check for Nintendo devices (Wiimotes, etc.)
        vendor_id=$(echo "$id" | cut -d':' -f1)
        is_nintendo=0
        if [ "$vendor_id" = "057e" ] || [ "$vendor_id" = "057E" ]; then
            is_nintendo=1
        fi
        
        key="Bus${bus}_Dev${device}"
        printf "%s|%s|%s|%s|%s|%s|%d\n" \
               "$key" \
               "${description:-Unknown}" \
               "${vendor_id:-Unknown}" \
               "${id:-Unknown}" \
               "USB 2.0" \
               "Bus $bus Device $device" \
               "$is_nintendo"
    done
}

compare_usb_state() {
    local current_state="$1"
    local previous_state="$2"
    
    echo "$current_state" | while IFS='|' read -r key product vendor id speed location is_nintendo; do
        if ! echo "$previous_state" | grep -q "^$key|"; then
            echo "NEW|$key|$product|$vendor|$id|$speed|$location|$is_nintendo"
        fi
    done
    
    echo "$previous_state" | while IFS='|' read -r key product vendor id speed location is_nintendo; do
        if ! echo "$current_state" | grep -q "^$key|"; then
            echo "GONE|$key|$product|$vendor|$id|$speed|$location|$is_nintendo"
        fi
    done
}

format_usb_info() {
    local device_info="$1"
    local action="$2"
    
    IFS='|' read -r _ key product vendor id speed location is_nintendo <<< "$device_info"
    
    product=$(echo "$product" | xargs)
    vendor=$(echo "$vendor" | xargs)
    
    # Highlight Nintendo devices (Wiimotes)
    if [ "$is_nintendo" = "1" ]; then
        if [ "$action" = "NEW" ]; then
            echo -e "${PURPLE}🎮 NINTENDO DEVICE DETECTED (Wiimote?)${NC}"
        fi
    fi
    
    if [ "$action" = "NEW" ]; then
        echo -e "${GREEN}🔌 DEVICE CONNECTED${NC}"
    else
        echo -e "${RED}🔌 DEVICE DISCONNECTED${NC}"
    fi
    echo -e "   ├─ Product: ${WHITE}${product:-Unknown}${NC}"
    echo -e "   ├─ Vendor ID: ${CYAN}${vendor}${NC}"
    echo -e "   ├─ Device ID: ${CYAN}${id}${NC}"
    echo -e "   ├─ Speed: ${YELLOW}${speed}${NC}"
    echo -e "   └─ Location: ${BLUE}${location}${NC}"
    if [ "$is_nintendo" = "1" ]; then
        echo -e "   └─ ${PURPLE}🎮 Nintendo device - Ready for Wiimote pairing!${NC}"
    fi
}

# Main monitoring loop
print_header
echo -e "${GREEN}[System] 🚀 USB Monitor started at $(date)${NC}\n"

# Initial scan
CURRENT_STATE=$(get_usb_devices_simple)
echo "$CURRENT_STATE" > "$STATE_FILE"

INITIAL_COUNT=$(echo "$CURRENT_STATE" | grep -v '^$' | wc -l)
if [ "$INITIAL_COUNT" -gt 0 ]; then
    echo -e "${GREEN}📊 Initial USB devices detected:${NC}"
    echo "$CURRENT_STATE" | while IFS='|' read -r key product vendor id speed location is_nintendo; do
        if [ "$is_nintendo" = "1" ]; then
            echo -e "   • ${PURPLE}🎮 ${product:-Unknown Device}${NC} - Nintendo device detected!"
        else
            echo -e "   • ${WHITE}${product:-Unknown Device}${NC}"
        fi
    done
else
    echo -e "${YELLOW}📊 No USB devices initially detected${NC}"
fi
echo ""

# Trap Ctrl+C to show stats before exit
trap 'echo ""; echo -e "${PURPLE}📊 Final Stats - Uptime: $((($(date +%s)-START_TIME)/60))m, Scans: $SCAN_COUNT${NC}"; echo -e "${YELLOW}👋 Monitor stopped at $(date)${NC}"; exit 0' INT

while true; do
    SCAN_COUNT=$((SCAN_COUNT + 1))
    
    CURRENT_STATE=$(get_usb_devices_simple)
    
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
                    echo "$(date): CONNECTED - $(echo "$change" | cut -d'|' -f3)" >> "$LOG_FILE"
                elif [ "$action" = "GONE" ]; then
                    format_usb_info "$change" "GONE"
                    echo "$(date): DISCONNECTED - $(echo "$change" | cut -d'|' -f3)" >> "$LOG_FILE"
                fi
                echo ""
            done
            
            echo "$CURRENT_STATE" > "$STATE_FILE"
        fi
    fi
    
    # Show stats every 30 seconds
    if [ $((SCAN_COUNT % 15)) -eq 0 ]; then
        print_stats
        CURRENT_COUNT=$(echo "$CURRENT_STATE" | grep -v '^$' | wc -l | xargs)
        echo -e "${GREEN}📊 Currently connected: $CURRENT_COUNT device(s)${NC}"
        echo ""
    fi
    
    # Show scan indicator every 10 seconds
    if [ $((SCAN_COUNT % 5)) -eq 0 ]; then
        echo -e "${CYAN}[Scan] 🔍 Checking USB ports... (scan #${SCAN_COUNT})${NC}"
    fi
    
    sleep $CHECK_INTERVAL
done
EOF

chmod +x "$USB_MONITOR_SCRIPT"
log "✅ USB Monitor script created"

# ============================================
# Create Wiimote Controller Script
# ============================================
section "Creating Wiimote Controller Script"

WIIMOTE_SCRIPT="$LOG_DIR/wiimote_controller.py"

log "Creating Wiimote controller script at: $WIIMOTE_SCRIPT"

cat > "$WIIMOTE_SCRIPT" << 'EOF'
#!/usr/bin/env python3
"""
Wiimote Controller for Ubuntu with Nunchuk WASD Support
Proper pairing with MAC reverse PIN calculation (same as macOS version)
"""

import os
import sys
import time
import struct
import subprocess
import threading
import signal
from datetime import datetime

# Try to import Bluetooth libraries
try:
    import bluetooth
    BLUETOOTH_AVAILABLE = True
except ImportError:
    BLUETOOTH_AVAILABLE = False
    print("⚠️ pybluez not available, trying system commands...")

try:
    from evdev import UInput, ecodes as e
    EVDEV_AVAILABLE = True
except ImportError:
    EVDEV_AVAILABLE = False
    print("⚠️ evdev not available, trying xdotool...")

# Colors for output
class Colors:
    GREEN = '\033[0;32m'
    RED = '\033[0;31m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    PURPLE = '\033[0;35m'
    CYAN = '\033[0;36m'
    WHITE = '\033[1;37m'
    NC = '\033[0m'

def log(msg, color=Colors.GREEN):
    """Log message with timestamp"""
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    print(f"{color}[{timestamp}]{Colors.NC} {msg}")
    sys.stdout.flush()

class WiimoteController:
    """Wiimote Controller with Nunchuk WASD support"""
    
    # Wii Remote constants
    WM_BT_VENDOR_ID = 0x057E  # Nintendo
    WM_BT_PRODUCT_ID = 0x0306  # RVL-CNT-01
    
    # Key codes for evdev/xdotool
    KEY_MAP = {
        'w': 'W', 'a': 'A', 's': 'S', 'd': 'D',
        'up': 'Up', 'down': 'Down', 'left': 'Left', 'right': 'Right',
        'space': 'space', 'ctrl': 'Control_L', 'shift': 'Shift_L'
    }
    
    def __init__(self):
        self.connected = False
        self.nunchuk_connected = False
        self.wasd_mode = True
        self.debug = True
        self.running = False
        self.joy_x = 0.0
        self.joy_y = 0.0
        self.last_keys = set()
        
        # Setup log file
        self.log_file = open(os.path.expanduser("~/device_monitor_logs/wiimote_controller.log"), "a")
        
        # Initialize input method
        self.setup_input_method()
        
        log(f"{Colors.PURPLE}🎮 Wiimote Controller initialized with Nunchuk WASD support{Colors.NC}")
        
    def setup_input_method(self):
        """Setup keyboard input method (evdev or xdotool)"""
        if EVDEV_AVAILABLE:
            try:
                self.ui = UInput({
                    e.EV_KEY: [e.KEY_W, e.KEY_A, e.KEY_S, e.KEY_D, 
                              e.KEY_UP, e.KEY_DOWN, e.KEY_LEFT, e.KEY_RIGHT,
                              e.KEY_LEFTCTRL, e.KEY_LEFTSHIFT, e.KEY_SPACE]
                }, name="wiimote-controller", bustype=e.BUS_USB)
                self.input_method = 'evdev'
                log(f"{Colors.GREEN}✅ Using evdev for input{Colors.NC}")
            except Exception as e:
                log(f"{Colors.YELLOW}⚠️ evdev init failed: {e}, falling back to xdotool{Colors.NC}")
                self.input_method = 'xdotool'
        else:
            self.input_method = 'xdotool'
            log(f"{Colors.YELLOW}⚠️ Using xdotool for input{Colors.NC}")
    
    def calculate_pin(self, mac_address):
        """Calculate Wiimote PIN (reverse MAC bytes - same as macOS version)"""
        clean_mac = mac_address.replace(':', '').replace('-', '').upper()
        
        if len(clean_mac) != 12:
            log(f"{Colors.RED}❌ Invalid MAC length: {len(clean_mac)}{Colors.NC}")
            return None
        
        # Reverse the byte order for PIN (Wii Remote specific)
        pin = ""
        for i in range(10, -1, -2):
            pin += clean_mac[i:i+2]
        
        log(f"{Colors.CYAN}🔐 PIN calculated: {pin} from MAC: {mac_address}{Colors.NC}")
        return pin
    
    def scan_for_wiimotes(self):
        """Scan for Wii Remotes using bluetooth"""
        log(f"{Colors.CYAN}🔍 Scanning for Wii Remotes (RVL-CNT-01)...{Colors.NC}")
        
        if BLUETOOTH_AVAILABLE:
            try:
                devices = bluetooth.discover_devices(duration=8, lookup_names=True, flush_cache=True)
                
                for addr, name in devices:
                    log(f"{Colors.YELLOW}   Found: {addr} - {name}{Colors.NC}")
                    if "Nintendo" in name or "RVL" in name or "Wiimote" in name:
                        log(f"{Colors.GREEN}✅ Wii Remote found: {name} at {addr}{Colors.NC}")
                        return addr
            except Exception as e:
                log(f"{Colors.RED}❌ Bluetooth scan error: {e}{Colors.NC}")
        
        # Fallback to hcitool
        try:
            result = subprocess.run(['hcitool', 'scan'], capture_output=True, text=True, timeout=10)
            for line in result.stdout.split('\n'):
                if 'Nintendo' in line or 'RVL' in line:
                    parts = line.split()
                    if len(parts) >= 2:
                        addr = parts[0]
                        log(f"{Colors.GREEN}✅ Wii Remote found via hcitool: {addr}{Colors.NC}")
                        return addr
        except Exception as e:
            log(f"{Colors.RED}❌ hcitool scan error: {e}{Colors.NC}")
        
        return None
    
    def pair_with_pin(self, mac_address):
        """Pair with Wii Remote using calculated PIN"""
        log(f"{Colors.PURPLE}🔐 ========== PAIRING WITH WII REMOTE =========={Colors.NC}")
        
        pin = self.calculate_pin(mac_address)
        if not pin:
            return False
        
        log(f"{Colors.CYAN}🔐 Using PIN: {pin}{Colors.NC}")
        
        # Try bluetoothctl for pairing
        try:
            # Remove if already paired
            subprocess.run(['bluetoothctl', 'remove', mac_address], capture_output=True)
            time.sleep(1)
            
            # Start pairing process
            log(f"{Colors.CYAN}🔐 Starting pairing with bluetoothctl...{Colors.NC}")
            
            # Create expect script for automatic PIN entry
            expect_script = f"""
#!/usr/bin/expect -f
set timeout 20
spawn bluetoothctl
expect "Agent registered"
send "pair {mac_address}\\r"
expect "Confirm passkey"
send "yes\\r"
expect "Enter PIN code"
send "{pin}\\r"
expect "Pairing successful"
send "trust {mac_address}\\r"
send "connect {mac_address}\\r"
expect "Connection successful"
send "exit\\r"
expect eof
"""
            with open('/tmp/wiimote_pair.exp', 'w') as f:
                f.write(expect_script)
            os.chmod('/tmp/wiimote_pair.exp', 0o755)
            
            result = subprocess.run(['/tmp/wiimote_pair.exp'], capture_output=True, text=True, timeout=30)
            if 'Pairing successful' in result.stdout or 'Connection successful' in result.stdout:
                log(f"{Colors.GREEN}✅ Pairing successful!{Colors.NC}")
                return True
            else:
                log(f"{Colors.YELLOW}⚠️ Pairing may have failed: {result.stdout[-200:]}{Colors.NC}")
                
        except Exception as e:
            log(f"{Colors.RED}❌ Pairing error: {e}{Colors.NC}")
        
        return False
    
    def connect_cwiid(self):
        """Connect using cwiid (most reliable for Wiimote)"""
        log(f"{Colors.CYAN}🎮 Attempting connection with cwiid...{Colors.NC}")
        log(f"{Colors.YELLOW}   Press 1+2 on your Wii Remote NOW!{Colors.NC}")
        
        try:
            # Try to import cwiid
            import cwiid
            
            # Connect to Wiimote
            log(f"{Colors.CYAN}   Waiting for Wiimote (press 1+2)...{Colors.NC}")
            self.wiimote = cwiid.Wiimote()
            log(f"{Colors.GREEN}✅ Connected via cwiid!{Colors.NC}")
            
            # Set up reporting mode for nunchuk
            self.wiimote.rpt_mode = cwiid.RPT_BTN | cwiid.RPT_ACC | cwiid.RPT_EXT
            time.sleep(0.5)
            
            # Check for nunchuk
            if self.wiimote.state.get('ext_type') == cwiid.EXT_NUNCHUK:
                self.nunchuk_connected = True
                log(f"{Colors.GREEN}✅ Nunchuk detected!{Colors.NC}")
            else:
                log(f"{Colors.YELLOW}⚠️ No nunchuk detected{Colors.NC}")
            
            self.connected = True
            self.running = True
            
            # Start polling thread
            self.poll_thread = threading.Thread(target=self.poll_cwiid)
            self.poll_thread.daemon = True
            self.poll_thread.start()
            
            return True
            
        except ImportError:
            log(f"{Colors.RED}❌ cwiid not available. Install with: sudo apt-get install cwiid{Colors.NC}")
            return False
        except Exception as e:
            log(f"{Colors.RED}❌ cwiid connection failed: {e}{Colors.NC}")
            return False
    
    def poll_cwiid(self):
        """Poll Wiimote for data (cwiid version)"""
        log(f"{Colors.GREEN}✅ Starting Wiimote polling...{Colors.NC}")
        
        while self.running and self.connected:
            try:
                state = self.wiimote.state
                
                # Get nunchuk data if available
                if self.nunchuk_connected and 'ext' in state:
                    ext = state['ext']
                    if 'nunchuk' in ext:
                        nunchuk = ext['nunchuk']
                        
                        # Get joystick position (0-255 range)
                        joy_x = (nunchuk['stick'][0] - 128) / 128.0
                        joy_y = (nunchuk['stick'][1] - 128) / 128.0
                        
                        # Apply deadzone
                        deadzone = 0.15
                        if abs(joy_x) < deadzone:
                            joy_x = 0
                        if abs(joy_y) < deadzone:
                            joy_y = 0
                        
                        self.joy_x = joy_x
                        self.joy_y = joy_y
                        
                        # Get button states
                        c_pressed = bool(nunchuk['buttons'] & 0x02)
                        z_pressed = bool(nunchuk['buttons'] & 0x01)
                        
                        if self.debug and (int(joy_x * 100) % 25 == 0):
                            log(f"{Colors.PURPLE}🎮 Nunchuk: ({joy_x:.2f}, {joy_y:.2f}) C:{c_pressed} Z:{z_pressed}{Colors.NC}")
                        
                        # Process WASD movement
                        if self.wasd_mode:
                            self.process_wasd(joy_x, joy_y)
                
                # Get Wiimote buttons
                buttons = state.get('buttons', 0)
                
                # Button mappings
                if buttons & cwiid.BTN_A:
                    self.send_key('space', True)
                else:
                    self.send_key('space', False)
                    
                if buttons & cwiid.BTN_B:
                    self.send_key('ctrl', True)
                else:
                    self.send_key('ctrl', False)
                
                # D-pad for scrolling/arrow keys
                if buttons & cwiid.BTN_UP:
                    self.send_key('up', True)
                else:
                    self.send_key('up', False)
                    
                if buttons & cwiid.BTN_DOWN:
                    self.send_key('down', True)
                else:
                    self.send_key('down', False)
                
                time.sleep(0.05)  # 20Hz polling
                
            except Exception as e:
                if self.running:
                    log(f"{Colors.RED}❌ Polling error: {e}{Colors.NC}")
                time.sleep(1)
    
    def process_wasd(self, joy_x, joy_y):
        """Process nunchuk joystick for WASD movement"""
        # Determine which keys should be pressed
        current_keys = set()
        
        if joy_y > 0:
            current_keys.add('w')
        elif joy_y < 0:
            current_keys.add('s')
            
        if joy_x < 0:
            current_keys.add('a')
        elif joy_x > 0:
            current_keys.add('d')
        
        # Release keys that are no longer pressed
        for key in self.last_keys - current_keys:
            self.send_key(key, False)
        
        # Press new keys
        for key in current_keys - self.last_keys:
            self.send_key(key, True)
        
        self.last_keys = current_keys
    
    def send_key(self, key, pressed):
        """Send key press/release event"""
        action = "PRESS" if pressed else "RELEASE"
        
        if self.debug and pressed and key in ['w','a','s','d']:
            log(f"{Colors.CYAN}⌨️ Key {action}: {key}{Colors.NC}")
        
        if self.input_method == 'evdev':
            try:
                key_map = {
                    'w': e.KEY_W, 'a': e.KEY_A, 's': e.KEY_S, 'd': e.KEY_D,
                    'up': e.KEY_UP, 'down': e.KEY_DOWN, 'left': e.KEY_LEFT, 'right': e.KEY_RIGHT,
                    'space': e.KEY_SPACE, 'ctrl': e.KEY_LEFTCTRL, 'shift': e.KEY_LEFTSHIFT
                }
                if key in key_map:
                    self.ui.write(e.EV_KEY, key_map[key], 1 if pressed else 0)
                    self.ui.syn()
            except Exception as e:
                log(f"{Colors.RED}❌ evdev error: {e}{Colors.NC}")
                self.input_method = 'xdotool'
                self.send_key(key, pressed)  # Retry with xdotool
        
        if self.input_method == 'xdotool':
            try:
                key_map = {
                    'w': 'w', 'a': 'a', 's': 's', 'd': 'd',
                    'up': 'Up', 'down': 'Down', 'left': 'Left', 'right': 'Right',
                    'space': 'space', 'ctrl': 'Control_L', 'shift': 'Shift_L'
                }
                if key in key_map:
                    cmd = ['xdotool', 'keydown' if pressed else 'keyup', key_map[key]]
                    subprocess.run(cmd, capture_output=True)
            except Exception as e:
                log(f"{Colors.RED}❌ xdotool error: {e}{Colors.NC}")
    
    def run(self):
        """Main run loop"""
        log(f"{Colors.PURPLE}🎮 ========== WIIMOTE CONTROLLER STARTING =========={Colors.NC}")
        
        # Try cwiid first (most reliable)
        if self.connect_cwiid():
            log(f"{Colors.GREEN}✅ Connected via cwiid!{Colors.NC}")
            log(f"{Colors.CYAN}🎮 Controls:{Colors.NC}")
            log(f"{Colors.CYAN}   • Nunchuk joystick → WASD movement{Colors.NC}")
            log(f"{Colors.CYAN}   • A button → Space{Colors.NC}")
            log(f"{Colors.CYAN}   • B button → Ctrl{Colors.NC}")
            log(f"{Colors.CYAN}   • D-pad → Arrow keys{Colors.NC}")
            log(f"{Colors.YELLOW}Press Ctrl+C to exit{Colors.NC}")
            
            # Keep running
            try:
                while self.running:
                    time.sleep(1)
            except KeyboardInterrupt:
                log(f"{Colors.YELLOW}👋 Shutting down...{Colors.NC}")
                self.running = False
                if self.connected:
                    try:
                        self.wiimote.close()
                    except:
                        pass
                if self.input_method == 'evdev':
                    self.ui.close()
                return 0
        else:
            # Fallback to manual pairing
            log(f"{Colors.YELLOW}⚠️ cwiid failed, trying manual pairing...{Colors.NC}")
            
            # Scan for Wiimote
            mac = self.scan_for_wiimotes()
            if mac:
                log(f"{Colors.GREEN}✅ Found Wiimote at {mac}{Colors.NC}")
                
                # Pair with PIN
                if self.pair_with_pin(mac):
                    log(f"{Colors.GREEN}✅ Pairing complete!{Colors.NC}")
                    log(f"{Colors.YELLOW}Now try running 'wminput' in another terminal{Colors.NC}")
                else:
                    log(f"{Colors.RED}❌ Pairing failed{Colors.NC}")
            else:
                log(f"{Colors.RED}❌ No Wiimote found{Colors.NC}")
                log(f"{Colors.YELLOW}Make sure to press 1+2 on your Wii Remote!{Colors.NC}")
            
            return 1

def main():
    """Main entry point"""
    controller = WiimoteController()
    sys.exit(controller.run())

if __name__ == "__main__":
    main()
EOF

chmod +x "$WIIMOTE_SCRIPT"
log "✅ Wiimote controller script created"

# ============================================
# Create Bash wrapper for Wiimote (alternative)
# ============================================
WIIMOTE_BASH_SCRIPT="$LOG_DIR/wiimote_wminput.sh"

cat > "$WIIMOTE_BASH_SCRIPT" << 'EOF'
#!/bin/bash
# Wiimote wrapper using wminput (cwiid)

LOG_DIR="$HOME/device_monitor_logs"
LOG_FILE="$LOG_DIR/wiimote_wminput.log"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${PURPLE}🎮 ========== WIIMOTE WMINPUT WRAPPER ==========${NC}" | tee -a "$LOG_FILE"

# Check if wminput is available
if ! command -v wminput &> /dev/null; then
    echo -e "${RED}❌ wminput not found. Install with: sudo apt-get install wminput${NC}"
    exit 1
fi

# Create nunchuk configuration
NUNCHUK_CONF="/tmp/nunchuk_wasd.conf"
cat > "$NUNCHUK_CONF" << 'CONF'
# Wii Remote Nunchuk to WASD mapping
# Joystick to WASD
Wiimote.Nunchuk.Stick.XMinus = KEY_A
Wiimote.Nunchuk.Stick.XPlus = KEY_D
Wiimote.Nunchuk.Stick.YMinus = KEY_S
Wiimote.Nunchuk.Stick.YPlus = KEY_W

# Nunchuk buttons
Wiimote.Nunchuk.C = KEY_LEFTCTRL
Wiimote.Nunchuk.Z = KEY_SPACE

# Wiimote buttons
Wiimote.A = KEY_SPACE
Wiimote.B = KEY_LEFTCTRL
Wiimote.Up = KEY_UP
Wiimote.Down = KEY_DOWN
Wiimote.Left = KEY_LEFT
Wiimote.Right = KEY_RIGHT
Wiimote.Home = KEY_HOME
Wiimote.Minus = KEY_MINUS
Wiimote.Plus = KEY_EQUAL
Wiimote.One = KEY_1
Wiimote.Two = KEY_2
CONF

echo -e "${CYAN}🎮 Starting wminput with nunchuk WASD config...${NC}" | tee -a "$LOG_FILE"
echo -e "${YELLOW}   Press 1+2 on your Wii Remote NOW!${NC}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Run wminput with the config
wminput -c "$NUNCHUK_CONF" 2>&1 | tee -a "$LOG_FILE"
EOF

chmod +x "$WIIMOTE_BASH_SCRIPT"
log "✅ Wiimote wminput wrapper created"

# ============================================
# Create Control Scripts
# ============================================
section "Creating Control Scripts"

# Combined status script (like usb-monitor-status from first script)
cat > "/usr/local/bin/device-monitor-status" << EOF
#!/bin/bash
USB_SESSION="$USB_SESSION"
WIIMOTE_SESSION="$WIIMOTE_SESSION"
LOG_DIR="$LOG_DIR"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo -e "${PURPLE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${PURPLE}║              DEVICE MONITOR STATUS                           ║${NC}"
echo -e "${PURPLE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check USB Monitor session
echo -e "${CYAN}🔌 USB MONITOR:${NC}"
if tmux has-session -t "\$USB_SESSION" 2>/dev/null; then
    echo -e "   ${GREEN}✅ RUNNING${NC}"
    SESSION_INFO=\$(tmux list-sessions | grep "\$USB_SESSION")
    echo "   Session: \$SESSION_INFO"
    
    # Show last 3 USB events
    if [ -f "\$LOG_DIR/usb_monitor.log" ]; then
        echo ""
        echo -e "   ${CYAN}Recent USB events:${NC}"
        tail -3 "\$LOG_DIR/usb_monitor.log" | while read line; do
            echo "     📍 \$line"
        done
    fi
else
    echo -e "   ${RED}❌ STOPPED${NC}"
fi

echo ""

# Check Wiimote Controller session
echo -e "${PURPLE}🎮 WIIMOTE CONTROLLER:${NC}"
if tmux has-session -t "\$WIIMOTE_SESSION" 2>/dev/null; then
    echo -e "   ${GREEN}✅ RUNNING${NC}"
    SESSION_INFO=\$(tmux list-sessions | grep "\$WIIMOTE_SESSION")
    echo "   Session: \$SESSION_INFO"
    
    # Show if nunchuk connected
    if [ -f "\$LOG_DIR/wiimote_controller.log" ]; then
        echo ""
        echo -e "   ${CYAN}Recent Wiimote events:${NC}"
        tail -3 "\$LOG_DIR/wiimote_controller.log" | while read line; do
            echo "     🎮 \$line"
        done
    fi
else
    echo -e "   ${RED}❌ STOPPED${NC}"
fi

echo ""
echo -e "${YELLOW}📊 USB Statistics:${NC}"
TOTAL_USB=\$(lsusb | wc -l)
NINTENDO_USB=\$(lsusb | grep -i "057e" | wc -l)
echo "   Total USB devices: \$TOTAL_USB"
echo "   Nintendo devices:  \$NINTENDO_USB"

echo ""
echo -e "${YELLOW}🛠️  Commands:${NC}"
echo "   Status:           device-monitor-status"
echo "   Start USB:        ~/usb-monitor-start.sh"
echo "   Stop USB:         ~/usb-monitor-stop.sh"
echo "   View USB:         tmux attach -t \$USB_SESSION"
echo "   Start Wiimote:    ~/wiimote-start.sh"
echo "   Stop Wiimote:     ~/wiimote-stop.sh"
echo "   View Wiimote:     tmux attach -t \$WIIMOTE_SESSION"
echo "   Both logs:        tail -f \$LOG_DIR/*.log"
EOF
sudo chmod +x /usr/local/bin/device-monitor-status

# USB Monitor start script
cat > "$HOME/usb-monitor-start.sh" << EOF
#!/bin/bash
SESSION_NAME="$USB_SESSION"
LOG_DIR="$LOG_DIR"
MONITOR_SCRIPT="$USB_MONITOR_SCRIPT"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "\${GREEN}Starting USB Monitor in tmux session: \${SESSION_NAME}\${NC}"

# Kill existing session if any
tmux kill-session -t "\$SESSION_NAME" 2>/dev/null || true

# Create new session with monitor
tmux new-session -d -s "\$SESSION_NAME" "cd $LOG_DIR && exec bash \$MONITOR_SCRIPT"

sleep 1
if tmux has-session -t "\$SESSION_NAME" 2>/dev/null; then
    echo -e "\${GREEN}✅ USB Monitor started successfully!\${NC}"
    echo ""
    echo -e "📌 Commands:"
    echo -e "   View monitor: tmux attach -t \$SESSION_NAME"
    echo -e "   Detach: Ctrl+B, then D"
    echo -e "   Stop monitor: ~/usb-monitor-stop.sh"
else
    echo -e "\${RED}❌ Failed to start USB Monitor\${NC}"
    exit 1
fi
EOF
chmod +x "$HOME/usb-monitor-start.sh"

# USB Monitor stop script
cat > "$HOME/usb-monitor-stop.sh" << EOF
#!/bin/bash
SESSION_NAME="$USB_SESSION"
LOG_DIR="$LOG_DIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if tmux has-session -t "\$SESSION_NAME" 2>/dev/null; then
    echo -e "\${YELLOW}Stopping USB Monitor...\${NC}"
    tmux kill-session -t "\$SESSION_NAME"
    echo -e "\${GREEN}✅ Monitor stopped\${NC}"
    
    # Show summary
    if [ -f "\$LOG_DIR/usb_monitor.log" ]; then
        echo ""
        echo -e "\${CYAN}📊 Session Summary:\${NC}"
        tail -5 "\$LOG_DIR/usb_monitor.log"
    fi
else
    echo -e "\${RED}❌ USB Monitor not running\${NC}"
fi
EOF
chmod +x "$HOME/usb-monitor-stop.sh"

# Wiimote start script
cat > "$HOME/wiimote-start.sh" << EOF
#!/bin/bash
SESSION_NAME="$WIIMOTE_SESSION"
LOG_DIR="$LOG_DIR"
WIIMOTE_SCRIPT="$WIIMOTE_SCRIPT"
WIIMOTE_BASH="$WIIMOTE_BASH_SCRIPT"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo -e "\${PURPLE}Starting Wiimote Controller in tmux session: \${SESSION_NAME}\${NC}"
echo ""

# Ask which method to use
echo "Select Wiimote connection method:"
echo "1) 🐍 Python script (cwiid) - Most reliable, full nunchuk support"
echo "2) 📟 wminput wrapper - Alternative method"
echo "3) 🔧 Manual pairing only (show PIN)"
read -p "Enter choice (1-3) [default: 1]: " METHOD
METHOD=\${METHOD:-1}

# Kill existing session if any
tmux kill-session -t "\$SESSION_NAME" 2>/dev/null || true

case \$METHOD in
    1)
        echo -e "\${GREEN}Starting Python Wiimote controller...\${NC}"
        tmux new-session -d -s "\$SESSION_NAME" "cd $LOG_DIR && python3 \$WIIMOTE_SCRIPT"
        ;;
    2)
        echo -e "\${GREEN}Starting wminput wrapper...\${NC}"
        tmux new-session -d -s "\$SESSION_NAME" "cd $LOG_DIR && bash \$WIIMOTE_BASH"
        ;;
    3)
        echo -e "\${YELLOW}Manual PIN mode:${NC}"
        echo "1) Press 1+2 on Wii Remote"
        echo "2) Run: hcitool scan | grep -i nintendo"
        echo "3) Get MAC, then run: ./calculate-pin.sh <MAC>"
        echo ""
        echo -e "\${PURPLE}PIN Calculator:${NC}"
        
        # Create PIN calculator
        cat > "/tmp/calculate-pin.sh" << 'PINEOF'
#!/bin/bash
mac=\$1
clean_mac=\$(echo \$mac | tr -d ':' | tr '[:lower:]' '[:upper:]')
pin=""
for i in 10 8 6 4 2 0; do
    pin+="\${clean_mac:\$i:2}"
done
echo "PIN: \$pin"
PINEOF
        chmod +x /tmp/calculate-pin.sh
        
        echo "Run: /tmp/calculate-pin.sh <MAC>"
        exit 0
        ;;
esac

sleep 2
if tmux has-session -t "\$SESSION_NAME" 2>/dev/null; then
    echo -e "\${GREEN}✅ Wiimote Controller started!\${NC}"
    echo ""
    echo -e "📌 Commands:"
    echo -e "   View controller: tmux attach -t \$SESSION_NAME"
    echo -e "   Detach: Ctrl+B, then D"
    echo -e "   Stop: ~/wiimote-stop.sh"
    echo -e "   Press 1+2 on Wii Remote NOW to connect!"
else
    echo -e "\${RED}❌ Failed to start Wiimote Controller\${NC}"
    exit 1
fi
EOF
chmod +x "$HOME/wiimote-start.sh"

# Wiimote stop script
cat > "$HOME/wiimote-stop.sh" << EOF
#!/bin/bash
SESSION_NAME="$WIIMOTE_SESSION"
LOG_DIR="$LOG_DIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if tmux has-session -t "\$SESSION_NAME" 2>/dev/null; then
    echo -e "\${YELLOW}Stopping Wiimote Controller...\${NC}"
    tmux kill-session -t "\$SESSION_NAME"
    echo -e "\${GREEN}✅ Controller stopped\${NC}"
    
    # Show summary
    if [ -f "\$LOG_DIR/wiimote_controller.log" ]; then
        echo ""
        echo -e "\${CYAN}📊 Session Summary:\${NC}"
        tail -5 "\$LOG_DIR/wiimote_controller.log"
    fi
else
    echo -e "\${RED}❌ Wiimote Controller not running\${NC}"
fi
EOF
chmod +x "$HOME/wiimote-stop.sh"

# ============================================
# Test and Start Options
# ============================================
section "Starting Services"

# Quick test of USB detection
log "Testing USB detection..."
if lsusb | head -5 > /dev/null; then
    log "✅ USB detection working"
else
    warning "USB detection test failed"
fi

# Test Bluetooth
log "Testing Bluetooth..."
if systemctl is-active --quiet bluetooth; then
    log "✅ Bluetooth is active"
    
    # Check for Nintendo devices
    NINTENDO_DEVICES=$(lsusb | grep -i "057e" | wc -l)
    if [ "$NINTENDO_DEVICES" -gt 0 ]; then
        log "✅ Found $NINTENDO_DEVICES Nintendo device(s) - Wiimote may be connected via USB charger"
    fi
else
    warning "Bluetooth is not active"
fi

# Ask to start services
echo ""
echo "Which services would you like to start?"
echo "1) 🔌 USB Monitor only"
echo "2) 🎮 Wiimote Controller only"
echo "3) 🔌🎮 Both USB Monitor and Wiimote Controller"
echo "4) 📋 Show status only"
echo "5) Exit"
read -p "Enter choice (1-5) [default: 3]: " START_CHOICE
START_CHOICE=${START_CHOICE:-3}

case $START_CHOICE in
    1)
        log "Starting USB Monitor..."
        bash "$HOME/usb-monitor-start.sh"
        
        echo ""
        echo "Attach to USB Monitor now?"
        read -p "Attach? (y/N): " ATTACH
        if [[ "$ATTACH" =~ ^[Yy]$ ]]; then
            tmux attach -t "$USB_SESSION"
        fi
        ;;
        
    2)
        log "Starting Wiimote Controller..."
        bash "$HOME/wiimote-start.sh"
        
        echo ""
        echo "Attach to Wiimote Controller now?"
        read -p "Attach? (y/N): " ATTACH
        if [[ "$ATTACH" =~ ^[Yy]$ ]]; then
            tmux attach -t "$WIIMOTE_SESSION"
        fi
        ;;
        
    3)
        log "Starting both services..."
        bash "$HOME/usb-monitor-start.sh"
        bash "$HOME/wiimote-start.sh"
        
        echo ""
        echo -e "${GREEN}✅ Both services started!${NC}"
        echo ""
        echo "Tmux sessions:"
        tmux ls
        echo ""
        echo "To view:"
        echo "  USB:      tmux attach -t $USB_SESSION"
        echo "  Wiimote:  tmux attach -t $WIIMOTE_SESSION"
        ;;
        
    4)
        device-monitor-status
        ;;
        
    5)
        log "Exiting without starting services"
        ;;
esac

# ============================================
# Create README
# ============================================
cat > "$HOME/README-device-monitor.txt" << EOF
================================================
🎮🔌 ALL-IN-ONE DEVICE MONITOR - USER GUIDE
================================================

This tool provides two services in tmux sessions:

1. 🔌 USB MONITOR - Real-time USB device connection tracking
2. 🎮 WIIMOTE CONTROLLER - Wii Remote with Nunchuk WASD control

================================================
📋 QUICK COMMANDS
================================================

Check status:
  device-monitor-status

USB Monitor:
  Start:   ~/usb-monitor-start.sh
  Stop:    ~/usb-monitor-stop.sh
  View:    tmux attach -t usb-monitor

Wiimote Controller:
  Start:   ~/wiimote-start.sh
  Stop:    ~/wiimote-stop.sh
  View:    tmux attach -t wiimote-controller

Logs:
  View all:    tail -f ~/device_monitor_logs/*.log
  USB log:     tail -f ~/device_monitor_logs/usb_monitor.log
  Wiimote log: tail -f ~/device_monitor_logs/wiimote_controller.log

================================================
🎮 WIIMOTE PAIRING INSTRUCTIONS
================================================

First time pairing (same as macOS method):
1. Make sure Bluetooth is ON
2. Press and HOLD buttons 1+2 on Wii Remote
3. LEDs should blink rapidly
4. Run: ~/wiimote-start.sh
5. Choose option 1 (Python script)

If using manual PIN:
1. Get MAC: hcitool scan | grep -i nintendo
2. Calculate PIN: reverse MAC bytes
   Example: MAC 00:19:1D:12:34:56 → PIN 5634121D1900
3. Use: bluetoothctl pair <MAC> and enter PIN

Nunchuk Controls:
• Joystick → WASD movement (W/A/S/D)
• Joystick tilt → Movement speed
• C button → Ctrl
• Z button → Space

Wiimote Controls:
• A button → Space
• B button → Ctrl
• D-pad → Arrow keys

================================================
🔌 USB MONITOR FEATURES
================================================
• Real-time USB connection detection
• Shows device details (vendor, product, speed)
• Highlights Nintendo devices (Wiimotes)
• Logs all USB events
• Runs in tmux for persistence

================================================
🔧 TROUBLESHOOTING
================================================

Wiimote not connecting:
1. Press 1+2 again (LEDs should blink)
2. Check Bluetooth: systemctl status bluetooth
3. Try manual PIN method (option 3)
4. Check logs: tail -f ~/device_monitor_logs/wiimote_controller.log

USB not showing:
1. Run: lsusb to check if detected
2. Check logs: tail -f ~/device_monitor_logs/usb_monitor.log
3. Run with sudo if needed

Tmux issues:
1. List sessions: tmux ls
2. Kill stuck session: tmux kill-session -t <name>
3. Detach from session: Ctrl+B, then D

================================================
EOF

# ============================================
# Final Output
# ============================================
section "INSTALLATION COMPLETE!"

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     ALL-IN-ONE DEVICE MONITOR IS READY!                      ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}📁 LOCATIONS:${NC}"
echo "   - Log directory: $LOG_DIR"
echo "   - USB log: $LOG_DIR/usb_monitor.log"
echo "   - Wiimote log: $LOG_DIR/wiimote_controller.log"
echo ""
echo -e "${PURPLE}🎮 WIIMOTE FEATURES (from macOS version):${NC}"
echo "   • Same PIN calculation (reverse MAC bytes)"
echo "   • Nunchuk joystick → WASD movement"
echo "   • Proper Bluetooth pairing"
echo "   • A/B button mapping"
echo "   • D-pad for arrow keys"
echo ""
echo -e "${YELLOW}🛠️  MANAGEMENT COMMANDS:${NC}"
echo "   - Check status: device-monitor-status"
echo "   - Start USB: ~/usb-monitor-start.sh"
echo "   - Stop USB: ~/usb-monitor-stop.sh"
echo "   - Start Wiimote: ~/wiimote-start.sh"
echo "   - Stop Wiimote: ~/wiimote-stop.sh"
echo ""
echo -e "${CYAN}📊 TMUX SESSIONS:${NC}"
echo "   USB Monitor:      tmux attach -t $USB_SESSION"
echo "   Wiimote:          tmux attach -t $WIIMOTE_SESSION"
echo "   List all:         tmux ls"
echo "   Detach:           Ctrl+B, then D"
echo ""
echo -e "${GREEN}✅ Installation complete! Run 'device-monitor-status' to check${NC}"
echo ""

# Key Features from the macOS Wiimote Script Ported to Ubuntu:

#     Same PIN Calculation:

#     def calculate_pin(self, mac_address):
#         clean_mac = mac_address.replace(':', '').replace('-', '').upper()
#         pin = ""
#         for i in range(10, -1, -2):
#             pin += clean_mac[i:i+2]
#         return pin

#     Nunchuk WASD Movement:
#         Joystick X/Y → W/A/S/D keys
#         Deadzone filtering
#         Non-linear response curve
#         Key press/release handling

#     Multiple Connection Methods:
#         Python/cwiid (most reliable, like macOS)
#         wminput wrapper (alternative)
#         Manual PIN calculation (same as macOS)

#     Button Mappings (same as macOS):
#         A button → Space
#         B button → Ctrl
#         D-pad → Arrow keys
#         Nunchuk C → Ctrl
#         Nunchuk Z → Space

#     Integrated USB Monitor:
#         Real-time USB detection
#         Highlights Nintendo devices
#         Logs all events

#     Tmux Sessions (from your scripts):
#         usb-monitor - USB monitoring
#         wiimote-controller - Wiimote control

# Run with:
# chmod +x utilities_ubuntu_tmux_usb_device_wiimote.sh
# ./utilities_ubuntu_tmux_usb_device_wiimote.sh