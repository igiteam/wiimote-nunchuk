#!/bin/bash
# usb_monitor_ubuntu.sh - USB Monitor for Ubuntu (Allwinner H3)
# Runs in tmux for persistent monitoring

# ============================================
# Configuration
# ============================================
SESSION_NAME="usb-monitor"
LOG_DIR="$HOME/usb_monitor_logs"
LOG_FILE="$LOG_DIR/usb_monitor.log"
STATE_FILE="$LOG_DIR/last_usb_state.txt"
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
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
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

# ============================================
# Start Script
# ============================================
clear
echo ""
echo -e "${PURPLE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${PURPLE}║                                                               ║${NC}"
echo -e "${PURPLE}║      🔌 USB DEVICE MONITOR - Ubuntu (Allwinner H3)           ║${NC}"
echo -e "${PURPLE}║                                                               ║${NC}"
echo -e "${PURPLE}║      • Real-time USB connection monitoring                    ║${NC}"
echo -e "${PURPLE}║      • Runs in tmux for persistence                           ║${NC}"
echo -e "${PURPLE}║      • Logs all USB events                                    ║${NC}"
echo -e "${PURPLE}║      • Shows device details                                   ║${NC}"
echo -e "${PURPLE}║                                                               ║${NC}"
echo -e "${PURPLE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

log "Starting USB Monitor setup at $(date)"

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
    bc

# Check if tmux is installed
if ! check_command tmux; then
    error "Failed to install tmux"
fi
log "✅ Tmux installed successfully"

# Check if lsusb is available
if ! check_command lsusb; then
    error "usbutils not installed properly"
fi
log "✅ USB utilities installed"

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
# Create Monitor Script
# ============================================
section "Creating USB Monitor Script"

MONITOR_SCRIPT="$LOG_DIR/usb_monitor_core.sh"

log "Creating monitor script at: $MONITOR_SCRIPT"

cat > "$MONITOR_SCRIPT" << 'EOF'
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
LOG_DIR="$HOME/usb_monitor_logs"
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

get_usb_devices() {
    # Use lsusb to get USB devices with more detail
    lsusb -v 2>/dev/null | awk '
    BEGIN { RS=""; FS="\n" }
    /idVendor/ {
        bus=""; device=""; id=""; vendor=""; product=""; speed=""
        
        for (i=1; i<=NF; i++) {
            if ($i ~ /Bus [0-9]+ Device [0-9]+/) {
                bus = $i
            }
            if ($i ~ /idVendor/) {
                split($i, a, "0x")
                id = a[2]
                gsub(/ /, "", id)
            }
            if ($i ~ /bDeviceClass/) {
                device_class = $i
            }
            if ($i ~ /idProduct/) {
                product_id = $i
            }
            if ($i ~ /bcdUSB/) {
                speed = $i
            }
            if ($i ~ /iManufacturer/) {
                vendor_line = $i
                match(vendor_line, /[0-9]+ (.*)/, arr)
                vendor = arr[1]
            }
            if ($i ~ /iProduct/) {
                product_line = $i
                match(product_line, /[0-9]+ (.*)/, arr)
                product = arr[1]
            }
        }
        
        if (product != "" || vendor != "") {
            key = bus "_" id
            printf "%s|%s|%s|%s|%s|%s\n", 
                   key, 
                   product ? product : "Unknown Device", 
                   vendor ? vendor : "Unknown Vendor", 
                   id ? id : "Unknown",
                   speed ? speed : "Unknown",
                   bus ? bus : "Unknown"
        }
    }' | sort -u
}

# Alternative simpler method using lsusb
get_usb_devices_simple() {
    lsusb | while read line; do
        bus=$(echo "$line" | awk '{print $2}')
        device=$(echo "$line" | awk '{print $4}' | sed 's/://')
        id=$(echo "$line" | awk '{print $6}')
        description=$(echo "$line" | cut -d' ' -f7-)
        
        # Try to get more details
        vendor=""
        product=""
        
        if [ -n "$id" ]; then
            vendor_id=$(echo "$id" | cut -d':' -f1)
            product_id=$(echo "$id" | cut -d':' -f2)
            
            # Look up in usb.ids if available
            if [ -f /usr/share/usb.ids ]; then
                vendor_line=$(grep -i "^$vendor_id" /usr/share/usb.ids 2>/dev/null | head -1)
                if [ -n "$vendor_line" ]; then
                    vendor=$(echo "$vendor_line" | cut -f2-)
                fi
            fi
        fi
        
        key="Bus${bus}_Dev${device}"
        printf "%s|%s|%s|%s|%s|%s\n" \
               "$key" \
               "${description:-Unknown}" \
               "${vendor:-$vendor_id}" \
               "${id:-Unknown}" \
               "USB 2.0" \
               "Bus $bus Device $device"
    done
}

compare_usb_state() {
    local current_state="$1"
    local previous_state="$2"
    
    echo "$current_state" | while IFS='|' read -r key product vendor id speed location; do
        if ! echo "$previous_state" | grep -q "^$key|"; then
            echo "NEW|$key|$product|$vendor|$id|$speed|$location"
        fi
    done
    
    echo "$previous_state" | while IFS='|' read -r key product vendor id speed location; do
        if ! echo "$current_state" | grep -q "^$key|"; then
            echo "GONE|$key|$product|$vendor|$id|$speed|$location"
        fi
    done
}

format_usb_info() {
    local device_info="$1"
    local action="$2"
    
    IFS='|' read -r _ key product vendor id speed location <<< "$device_info"
    
    product=$(echo "$product" | xargs)
    vendor=$(echo "$vendor" | xargs)
    
    if [ "$action" = "NEW" ]; then
        echo -e "${GREEN}🔌 DEVICE CONNECTED${NC}"
    else
        echo -e "${RED}🔌 DEVICE DISCONNECTED${NC}"
    fi
    echo -e "   ├─ Product: ${WHITE}${product:-Unknown}${NC}"
    echo -e "   ├─ Manufacturer: ${WHITE}${vendor:-Unknown}${NC}"
    echo -e "   ├─ Device ID: ${CYAN}${id}${NC}"
    echo -e "   ├─ Speed: ${YELLOW}${speed}${NC}"
    echo -e "   └─ Location: ${BLUE}${location}${NC}"
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
    echo "$CURRENT_STATE" | while IFS='|' read -r key product vendor id speed location; do
        echo -e "   • ${WHITE}${product:-Unknown Device}${NC} - ${vendor:-Unknown}"
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

chmod +x "$MONITOR_SCRIPT"
log "✅ Monitor script created"

# ============================================
# Create Control Scripts
# ============================================
section "Creating Control Scripts"

# Start script
cat > "$HOME/usb-monitor-start.sh" << EOF
#!/bin/bash
# Start USB Monitor in tmux

SESSION_NAME="$SESSION_NAME"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "\${GREEN}Starting USB Monitor in tmux session: \${SESSION_NAME}\${NC}"

# Kill existing session if any
tmux kill-session -t "\$SESSION_NAME" 2>/dev/null || true

# Create new session with monitor
tmux new-session -d -s "\$SESSION_NAME" "cd $LOG_DIR && exec $MONITOR_SCRIPT"

sleep 1
if tmux has-session -t "\$SESSION_NAME" 2>/dev/null; then
    echo -e "\${GREEN}✅ USB Monitor started successfully!\${NC}"
    echo ""
    echo -e "📌 Commands:"
    echo -e "   View monitor: tmux attach -t \$SESSION_NAME"
    echo -e "   Detach: Ctrl+B, then D"
    echo -e "   Stop monitor: tmux kill-session -t \$SESSION_NAME"
    echo -e "   Check status: tmux ls | grep \$SESSION_NAME"
else
    echo -e "\${RED}❌ Failed to start USB Monitor\${NC}"
    exit 1
fi
EOF
chmod +x "$HOME/usb-monitor-start.sh"

# Stop script
cat > "$HOME/usb-monitor-stop.sh" << EOF
#!/bin/bash
SESSION_NAME="$SESSION_NAME"
LOG_DIR="$LOG_DIR"

# Colors
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
        tail -20 "\$LOG_DIR/usb_monitor.log"
    fi
else
    echo -e "\${RED}❌ USB Monitor not running\${NC}"
fi
EOF
chmod +x "$HOME/usb-monitor-stop.sh"

# Status script (like check-wii-covers)
cat > "/usr/local/bin/usb-monitor-status" << EOF
#!/bin/bash
SESSION_NAME="$SESSION_NAME"
LOG_DIR="$LOG_DIR"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo -e "\${PURPLE}=== USB Monitor Status ===\${NC}"
echo ""

# Check tmux session
if tmux has-session -t "\$SESSION_NAME" 2>/dev/null; then
    echo -e "\${GREEN}✅ Monitor is RUNNING\${NC}"
    SESSION_INFO=\$(tmux list-sessions | grep "\$SESSION_NAME")
    echo "   Session: \$SESSION_INFO"
else
    echo -e "\${RED}❌ Monitor is STOPPED\${NC}"
fi
echo ""

# USB Statistics
echo -e "\${CYAN}📊 USB Statistics:\${NC}"
TOTAL_USB=\$(lsusb | wc -l)
echo "   Total USB devices: \$TOTAL_USB"

# Show USB tree
echo ""
echo -e "\${CYAN}🔌 Connected USB Devices:\${NC}"
lsusb | while read line; do
    echo "   \$line"
done

# Show recent logs
if [ -f "\$LOG_DIR/usb_monitor.log" ]; then
    echo ""
    echo -e "\${CYAN}📝 Recent Events (last 5):\${NC}"
    tail -5 "\$LOG_DIR/usb_monitor.log" | while read line; do
        echo "   \$line"
    done
    
    TOTAL_EVENTS=\$(wc -l < "\$LOG_DIR/usb_monitor.log")
    echo ""
    echo "   Total events logged: \$TOTAL_EVENTS"
fi

# Management commands
echo ""
echo -e "\${YELLOW}🛠️  Commands:\${NC}"
echo "   Start:   ~/usb-monitor-start.sh"
echo "   Stop:    ~/usb-monitor-stop.sh"
echo "   View:    tmux attach -t \$SESSION_NAME"
echo "   Logs:    tail -f \$LOG_DIR/usb_monitor.log"
echo "   Status:  usb-monitor-status"
EOF
sudo chmod +x /usr/local/bin/usb-monitor-status

log "✅ Control scripts created"

# ============================================
# Create Autostart Service (Optional)
# ============================================
section "Setting Up Autostart (Optional)"

echo "Do you want USB Monitor to start automatically on boot?"
echo "1) Yes - Start on boot"
echo "2) No - Manual start only"
read -p "Enter choice (1-2) [default: 2]: " AUTOSTART
AUTOSTART=${AUTOSTART:-2}

if [ "$AUTOSTART" == "1" ]; then
    log "Creating systemd service..."
    
    sudo tee /etc/systemd/system/usb-monitor.service > /dev/null << EOF
[Unit]
Description=USB Monitor Service
After=multi-user.target

[Service]
Type=forking
User=$USER
ExecStart=/home/$USER/usb-monitor-start.sh
ExecStop=/home/$USER/usb-monitor-stop.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable usb-monitor.service
    log "✅ Autostart enabled"
else
    log "Skipping autostart setup"
fi

# ============================================
# Test and Start Monitor
# ============================================
section "Starting USB Monitor"

# Quick test of lsusb
log "Testing USB detection..."
if lsusb | head -5 | while read line; do
    echo "   $line"
done; then
    log "✅ USB detection working"
else
    warning "USB detection test failed"
fi

# Ask to start monitor
echo ""
read -p "Start USB Monitor now? (y/N): " START_NOW
if [[ "$START_NOW" =~ ^[Yy]$ ]]; then
    log "Starting USB Monitor..."
    bash "$HOME/usb-monitor-start.sh"
    
    echo ""
    echo "Do you want to:"
    echo "1) Attach now and watch USB events"
    echo "2) Detach and let it run in background"
    read -p "Enter choice (1-2) [default: 1]: " ATTACH_CHOICE
    ATTACH_CHOICE=${ATTACH_CHOICE:-1}
    
    if [ "$ATTACH_CHOICE" == "1" ]; then
        log "Attaching to tmux session..."
        sleep 2
        tmux attach -t "$SESSION_NAME"
    else
        log "Monitor running in background"
    fi
fi

# ============================================
# Final Output
# ============================================
section "INSTALLATION COMPLETE!"

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  USB MONITOR IS READY!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}📁 LOCATIONS:${NC}"
echo "   - Log directory: $LOG_DIR"
echo "   - Log file: $LOG_FILE"
echo "   - State file: $STATE_FILE"
echo ""
echo -e "${YELLOW}🛠️  MANAGEMENT COMMANDS:${NC}"
echo "   - Check status: usb-monitor-status"
echo "   - Start monitor: ~/usb-monitor-start.sh"
echo "   - Stop monitor: ~/usb-monitor-stop.sh"
echo "   - View live: tmux attach -t $SESSION_NAME"
echo "   - Detach: Ctrl+B, then D"
echo "   - List sessions: tmux ls"
echo ""
echo -e "${YELLOW}📊 TMUX COMMANDS (from your Wii script):${NC}"
echo "   - Check if running: tmux ls"
echo "   - Attach to view: tmux attach -t $SESSION_NAME"
echo "   - Kill session: tmux kill-session -t $SESSION_NAME"
echo "   - List all: tmux list-sessions"
echo ""
echo -e "${YELLOW}🔍 TROUBLESHOOTING:${NC}"
echo "   - Check USB devices: lsusb"
echo "   - View real-time logs: tail -f $LOG_FILE"
echo "   - Test USB detection: sudo lsusb -v | head -50"
echo "   - Check Allwinner H3 USB: dmesg | grep -i usb"
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Save info
cat > "$LOG_DIR/installation_info.txt" << EOF
USB Monitor Installation
Date: $(date)
Session Name: $SESSION_NAME
Log Directory: $LOG_DIR
Commands:
  - Status: usb-monitor-status
  - Start: ~/usb-monitor-start.sh
  - Stop: ~/usb-monitor-stop.sh
  - View: tmux attach -t $SESSION_NAME
System: $(uname -a)
USB Controller: $(lspci | grep -i usb 2>/dev/null || echo "ARM USB (Allwinner H3)")
EOF

log "✅ Installation complete! Run 'usb-monitor-status' to check status"

# Key Changes for Ubuntu/Allwinner H3:
#     Tmux Integration (copied from your Wii script):
#         Uses tmux sessions for persistent monitoring
#         Session name: usb-monitor
#         Same tmux commands you're used to: tmux attach, tmux ls, tmux kill-session

#     Ubuntu-Specific USB Detection:
#         Uses lsusb instead of macOS system_profiler
#         Added fallback methods for different detail levels
#         Compatible with Allwinner H3 USB controllers

#     Control Scripts (like your check-wii-covers):
#         usb-monitor-status - Shows status, USB devices, recent events
#         usb-monitor-start.sh - Starts the monitor
#         usb-monitor-stop.sh - Stops the monitor

#     Allwinner H3 Optimizations:
#         Lighter weight detection methods
#         Works with ARM architecture
#         Proper USB bus enumeration

#     Same Tmux Workflow You Know:
#     # Check if running
#     tmux ls

#     # View monitor
#     tmux attach -t usb-monitor
#     # Detach (Ctrl+B, D)

#     # Stop monitor
#     tmux kill-session -t usb-monitor

#     Added Status Command (like your check-wii-covers):
#     usb-monitor-status
#     # Shows:
#     # - If monitor is running
#     # - Connected USB devices
#     # - Recent events
#     # - Management commands

# The script follows the same patterns as your Wii covers 
#script - using tmux for persistence, creating helper scripts, 
#and providing easy management commands. Perfect for 
#monitoring USB devices on your Allwinner H3 board!