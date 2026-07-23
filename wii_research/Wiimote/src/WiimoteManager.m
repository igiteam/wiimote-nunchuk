#import "WiimoteManager.h"
#import <IOBluetooth/IOBluetooth.h>
#import <AppKit/AppKit.h>
#import <math.h>

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
// IR properties
@property (nonatomic, assign) BOOL irEnabled;
@property (nonatomic, assign) BOOL irBottom;
@property (nonatomic, assign) int irX1, irY1, irX2, irY2, irX3, irY3, irX4, irY4;
// Wiimote buttons
@property (nonatomic, assign) BOOL btnA, btnB, btn1, btn2, btnPlus, btnMinus, btnHome;
@property (nonatomic, assign) BOOL btnUp, btnDown, btnLeft, btnRight;
// RAW IR debug
@property (nonatomic, assign) BOOL debugIR;
// Last display to prevent flicker
@property (nonatomic, strong) NSString *lastDisplay;

// SCREEN CALIBRATION
@property (nonatomic, assign) float calCenterX;
@property (nonatomic, assign) float calCenterY;
@property (nonatomic, assign) float calTopLeftX;
@property (nonatomic, assign) float calTopLeftY;
@property (nonatomic, assign) BOOL calCenterSet;
@property (nonatomic, assign) BOOL calTopLeftSet;
@property (nonatomic, assign) BOOL isScreenCalibrated;

// Smoothing
@property (nonatomic, assign) float smoothX;
@property (nonatomic, assign) float smoothY;
@property (nonatomic, assign) BOOL hasSmooth;

// Last button states for detection (with debounce)
@property (nonatomic, assign) BOOL lastA;
@property (nonatomic, assign) BOOL lastHome;
@property (nonatomic, assign) int homeDebounceCount;
@property (nonatomic, assign) int aDebounceCount;
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
        _irEnabled = YES;
        _irBottom = YES;
        _debugIR = NO;
        _irX1 = _irY1 = _irX2 = _irY2 = _irX3 = _irY3 = _irX4 = _irY4 = -1;
        _btnA = _btnB = _btn1 = _btn2 = _btnPlus = _btnMinus = _btnHome = NO;
        _btnUp = _btnDown = _btnLeft = _btnRight = NO;
        _lastDisplay = @"";
        
        // Screen calibration
        _calCenterX = 0;
        _calCenterY = 0;
        _calTopLeftX = 0;
        _calTopLeftY = 0;
        _calCenterSet = NO;
        _calTopLeftSet = NO;
        _isScreenCalibrated = NO;
        _smoothX = 0;
        _smoothY = 0;
        _hasSmooth = NO;
        _lastA = NO;
        _lastHome = NO;
        _homeDebounceCount = 0;
        _aDebounceCount = 0;
        
        printf("[Wiimote] FULL FEATURED with Screen Calibration\n");
        printf("[Wiimote] Press A at center, then A at top-left to calibrate screen\n");
        printf("[Wiimote] Press HOME to reset screen calibration\n");
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
    printf("\n[Wiimote] Stopped\n");
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
    
    // Set reporting mode to 0x37 (includes IR + Extension)
    [self setReportingMode:0x37];
    usleep(50000);
    
    // ENABLE IR CAMERA FIRST
    if (self.irEnabled) {
        printf("[IR] Enabling IR Camera...\n");
        
        // Enable IR with 0x04 (basic mode without pixel clock)
        uint8_t irEnable[] = {0xA2, 0x13, 0x04};
        [self.ctrl writeSync:irEnable length:3];
        usleep(50000);
        
        uint8_t irEnable2[] = {0xA2, 0x1A, 0x04};
        [self.ctrl writeSync:irEnable2 length:3];
        usleep(50000);
        
        [self initIR];
    }
    
    // Then init Nunchuk
    [self initNunchuk];
    
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.05
                                                   target:self
                                                 selector:@selector(pollStatus)
                                                 userInfo:nil
                                                  repeats:YES];
}

- (void)initIR {
    printf("\n========== INIT IR REGISTERS ==========\n");
    fflush(stdout);
    
    // Write 0x08 to 0xb00030 (enable IR)
    [self writeMemory:0xB00030 data:[NSData dataWithBytes:"\x08" length:1]];
    usleep(50000);
    
    // Write sensitivity block (Level 3)
    uint8_t block1[] = {0x02, 0x00, 0x00, 0x71, 0x01, 0x00, 0xAA, 0x00, 0x64};
    uint8_t block2[] = {0x63, 0x03};
    
    [self writeMemory:0xB00000 data:[NSData dataWithBytes:block1 length:9]];
    usleep(50000);
    
    [self writeMemory:0xB0001A data:[NSData dataWithBytes:block2 length:2]];
    usleep(50000);
    
    // Set IR mode to Basic (0x01)
    uint8_t irMode = 0x01;
    [self writeMemory:0xB00033 data:[NSData dataWithBytes:&irMode length:1]];
    usleep(50000);
    
    // Write 0x08 to 0xb00030 again (enable IR with settings)
    [self writeMemory:0xB00030 data:[NSData dataWithBytes:"\x08" length:1]];
    usleep(50000);
    
    // Set reporting mode back to 0x37
    [self setReportingMode:0x37];
    usleep(50000);
    
    printf("[IR] Registers initialized! (Bottom: %s, Mode: Basic)\n", self.irBottom ? "YES" : "NO");
    printf("==================================\n\n");
    fflush(stdout);
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

- (void)parseWiimoteButtons:(uint8_t *)data {
    self.btnLeft   = (data[0] & 0x01) == 0;
    self.btnRight  = (data[0] & 0x02) == 0;
    self.btnDown   = (data[0] & 0x04) == 0;
    self.btnUp     = (data[0] & 0x08) == 0;
    self.btnPlus   = (data[0] & 0x10) == 0;
    
    self.btn2      = (data[1] & 0x01) == 0;
    self.btn1      = (data[1] & 0x02) == 0;
    self.btnB      = (data[1] & 0x04) == 0;
    self.btnA      = (data[1] & 0x08) == 0;
    self.btnMinus  = (data[1] & 0x10) == 0;
    self.btnHome   = (data[1] & 0x80) == 0;
}

- (void)parseIRData:(uint8_t *)data {
    if (!self.irEnabled) return;
    
    // Check if IR data is valid (not all 0xFF)
    BOOL hasData = NO;
    for (int i = 0; i < 10; i++) {
        if (data[i] != 0xFF) { hasData = YES; break; }
    }
    
    if (!hasData) {
        self.irX1 = self.irX2 = self.irX3 = self.irX4 = -1;
        self.irY1 = self.irY2 = self.irY3 = self.irY4 = -1;
        return;
    }
    
    // Parse Basic Mode (10 bytes for 4 objects)
    // Object 1 (bytes 0, 1, 2 bits 4-5 for X, bits 6-7 for Y)
    if (data[0] != 0xFF || data[1] != 0xFF) {
        uint16_t x1 = data[0] | ((data[2] & 0x30) << 4);
        uint16_t y1 = data[1] | ((data[2] & 0xC0) << 2);
        self.irX1 = x1;
        self.irY1 = self.irBottom ? (1023 - y1) : y1;
    } else {
        self.irX1 = -1; self.irY1 = -1;
    }
    
    // Object 2 (bytes 3, 4, 2 bits 0-1 for X, bits 2-3 for Y)
    if (data[3] != 0xFF || data[4] != 0xFF) {
        uint16_t x2 = data[3] | ((data[2] & 0x03) << 8);
        uint16_t y2 = data[4] | ((data[2] & 0x0C) << 6);
        self.irX2 = x2;
        self.irY2 = self.irBottom ? (1023 - y2) : y2;
    } else {
        self.irX2 = -1; self.irY2 = -1;
    }
    
    // Object 3 (bytes 5, 6, 7 bits 4-5 for X, bits 6-7 for Y)
    if (data[5] != 0xFF || data[6] != 0xFF) {
        uint16_t x3 = data[5] | ((data[7] & 0x30) << 4);
        uint16_t y3 = data[6] | ((data[7] & 0xC0) << 2);
        self.irX3 = x3;
        self.irY3 = self.irBottom ? (1023 - y3) : y3;
    } else {
        self.irX3 = -1; self.irY3 = -1;
    }
    
    // Object 4 (bytes 8, 9, 7 bits 0-1 for X, bits 2-3 for Y)
    if (data[8] != 0xFF || data[9] != 0xFF) {
        uint16_t x4 = data[8] | ((data[7] & 0x03) << 8);
        uint16_t y4 = data[9] | ((data[7] & 0x0C) << 6);
        self.irX4 = x4;
        self.irY4 = self.irBottom ? (1023 - y4) : y4;
    } else {
        self.irX4 = -1; self.irY4 = -1;
    }
}

- (NSString *)buttonString {
    NSMutableString *str = [NSMutableString string];
    if (self.btnA) [str appendString:@"A"];
    if (self.btnB) [str appendString:@"B"];
    if (self.btn1) [str appendString:@"1"];
    if (self.btn2) [str appendString:@"2"];
    if (self.btnPlus) [str appendString:@"+"];
    if (self.btnMinus) [str appendString:@"-"];
    if (self.btnHome) [str appendString:@"H"];
    if (self.btnUp) [str appendString:@"↑"];
    if (self.btnDown) [str appendString:@"↓"];
    if (self.btnLeft) [str appendString:@"←"];
    if (self.btnRight) [str appendString:@"→"];
    if (str.length == 0) [str appendString:@"-"];
    return str;
}

- (void)parseNunchukData:(uint8_t *)decrypted withID:(uint8_t)id andCoreData:(uint8_t *)coreData {
    int rawX = decrypted[0];
    int rawY = decrypted[1];
    
    // Handle Nunchuk calibration
    if (self.calibrating && self.extConnected) {
        // Skip extreme values during calibration
        if (rawX > 30 && rawX < 220 && rawY > 30 && rawY < 220) {
            self.calXSum += rawX;
            self.calYSum += rawY;
            self.calSamples++;
        }
        
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
    
    if (coreData) {
        [self parseWiimoteButtons:coreData];
    }
    
    self.cPressed = ((decrypted[5] & 0x02) == 0);
    self.zPressed = !((decrypted[5] & 0x01) == 0);
    
    int centeredX = rawX - self.joyXCenter;
    int centeredY = -(rawY - self.joyYCenter);
    
    int deadzone = 15;
    if (abs(centeredX) < deadzone) centeredX = 0;
    if (abs(centeredY) < deadzone) centeredY = 0;
    
    self.joyX = centeredX;
    self.joyY = centeredY;
    
    NSString *direction = @"IDLE";
    double magnitude = 0;
    
    if (centeredX != 0 || centeredY != 0) {
        magnitude = sqrt(centeredX * centeredX + centeredY * centeredY);
        if (abs(centeredX) > abs(centeredY)) {
            direction = (centeredX > 0) ? @"RIGHT" : @"LEFT";
        } else {
            direction = (centeredY > 0) ? @"DOWN" : @"UP";
        }
    }
    
    NSString *buttons = [self buttonString];
    
    // Get screen coordinates from IR
    NSScreen *screen = [NSScreen mainScreen];
    CGFloat screenWidth = screen.frame.size.width;
    CGFloat screenHeight = screen.frame.size.height;
    
    // Find valid IR dots
    int validDots = 0;
    float avgX = 0, avgY = 0;
    int irDots[4][2] = {
        {self.irX1, self.irY1},
        {self.irX2, self.irY2},
        {self.irX3, self.irY3},
        {self.irX4, self.irY4}
    };
    
    for (int i = 0; i < 4; i++) {
        if (irDots[i][0] != -1 && irDots[i][1] != -1) {
            avgX += irDots[i][0];
            avgY += irDots[i][1];
            validDots++;
        }
    }
    
    float screenX = 0, screenY = 0;
    if (validDots > 0) {
        avgX /= validDots;
        avgY /= validDots;
        
        // Map to screen
        if (self.isScreenCalibrated) {
            float relX = (avgX - self.calTopLeftX) / ((self.calCenterX - self.calTopLeftX) * 2);
            float relY = (avgY - self.calTopLeftY) / ((self.calCenterY - self.calTopLeftY) * 2);
            screenX = relX * screenWidth;
            screenY = relY * screenHeight;
        } else {
            screenX = (avgX / 1023.0) * screenWidth;
            screenY = (avgY / 1023.0) * screenHeight;
        }
        
        if (self.irBottom) {
            screenY = screenHeight - screenY;
        }
        
        screenX = MAX(0, MIN(screenWidth, screenX));
        screenY = MAX(0, MIN(screenHeight, screenY));
        
        // Smoothing
        if (!self.hasSmooth) {
            self.smoothX = screenX;
            self.smoothY = screenY;
            self.hasSmooth = YES;
        } else {
            self.smoothX = screenX * 0.7 + self.smoothX * 0.3;
            self.smoothY = screenY * 0.7 + self.smoothY * 0.3;
        }
    }
    
    // Handle screen calibration buttons with debouncing
    // HOME button - reset calibration (with debounce)
    if (self.btnHome && !self.lastHome) {
        self.calCenterSet = NO;
        self.calTopLeftSet = NO;
        self.isScreenCalibrated = NO;
        self.hasSmooth = NO;
        printf("\n🔴 SCREEN CALIBRATION RESET\n");
        printf("📋 Point at CENTER and press A\n");
        fflush(stdout);
        [self setRumble:YES];
        usleep(200000);
        [self setRumble:NO];
    }
    self.lastHome = self.btnHome;
    
    // A button - set calibration points (with debounce)
    if (self.btnA && !self.lastA) {
        if (!self.calCenterSet && validDots > 0) {
            self.calCenterX = avgX;
            self.calCenterY = avgY;
            self.calCenterSet = YES;
            printf("\n✅ CENTER set: IR(%.0f, %.0f) Screen(%.0f, %.0f)\n", 
                   avgX, avgY, self.smoothX, self.smoothY);
            printf("📋 Point at TOP-LEFT and press A\n");
            fflush(stdout);
            [self setRumble:YES];
            usleep(150000);
            [self setRumble:NO];
        } else if (!self.calTopLeftSet && validDots > 0) {
            self.calTopLeftX = avgX;
            self.calTopLeftY = avgY;
            self.calTopLeftSet = YES;
            self.isScreenCalibrated = YES;
            printf("\n✅ TOP-LEFT set: IR(%.0f, %.0f) Screen(%.0f, %.0f)\n", 
                   avgX, avgY, self.smoothX, self.smoothY);
            printf("🎉 SCREEN CALIBRATION COMPLETE!\n");
            fflush(stdout);
            [self setRumble:YES];
            usleep(200000);
            [self setRumble:NO];
            usleep(100000);
            [self setRumble:YES];
            usleep(200000);
            [self setRumble:NO];
        } else if (self.calCenterSet && self.calTopLeftSet) {
            printf("\n⚠️ Already calibrated! Press HOME to reset.\n");
            fflush(stdout);
        } else if (validDots == 0) {
            printf("\n⚠️ No IR dots detected! Point Wiimote at sensor bar.\n");
            fflush(stdout);
        }
    }
    self.lastA = self.btnA;
    
    // Build display
    NSMutableString *display = [NSMutableString string];
    [display appendFormat:@"[Nunchuk] X:%+4d Y:%+4d | Dir: %-5@ | Wii: %@ | C:%d Z:%d | ",
     self.joyX, self.joyY, direction, buttons, self.cPressed, self.zPressed];
    
    if (validDots > 0) {
        [display appendFormat:@"Screen: (%.0f, %.0f)", self.smoothX, self.smoothY];
        if (self.isScreenCalibrated) {
            [display appendString:@" [Calibrated]"];
        }
        [display appendFormat:@" | Dots: %d", validDots];
    } else {
        [display appendString:@"No IR dots"];
    }
    
    // Only update if changed
    if (![display isEqualToString:self.lastDisplay]) {
        printf("\r%s   ", [display UTF8String]);
        fflush(stdout);
        self.lastDisplay = display;
    }
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
            }
        }
        return;
    }
    
    if (id == 0x21 && len >= 10) {
        if (d[5] == 0xA4 && d[6] == 0x00 && d[7] == 0xFE) {
            if (d[8] == 0x00 && d[9] == 0x00) {
                self.extConnected = YES;
                printf("\n[READ 0x21] ✅ NUNCHUK CONFIRMED!\n");
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
            
            [self parseNunchukData:decrypted withID:id andCoreData:NULL];
            return;
        }
        return;
    }
    
    if (id == 0x22) {
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
        
        uint8_t *coreData = d + 2;
        data = d + extOffset;
        
        // Parse IR data (10 bytes at offset 5 for mode 0x37)
        if (self.irEnabled && id == 0x37 && len >= 27) {
            [self parseIRData:d + 5];
        }
        
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
        
        [self parseNunchukData:decrypted withID:id andCoreData:coreData];
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
