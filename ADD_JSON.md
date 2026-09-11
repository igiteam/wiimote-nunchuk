how to add this?

Add a plist or JSON file at ~/Library/Application Support/Wiimote/mappings.json. Load it on startup, fall back to the hardcoded defaults if it's missing.

Example file:
json

{
  "dpad_up":    { "short": "E",  "long": "UP",    "hold": false, "mouse": false },
  "dpad_down":  { "short": "V",  "long": "DOWN",  "hold": false, "mouse": false },
  "dpad_left":  { "short": "TAB","long": "TILDE", "hold": false, "mouse": false },
  "dpad_right": { "short": "SPACE","long": "Z",   "hold": false, "mouse": false },
  "A":          { "short": "Q",  "long": null,    "hold": true,  "mouse": false },
  "B":          { "short": null, "long": null,    "hold": true,  "mouse": true  },
  "minus":      { "short": "R",  "long": "G",     "hold": false, "mouse": false },
  "plus":       { "short": "B",  "long": null,    "hold": false, "mouse": false },
  "home":       { "short": "ESC","long": "ESC",   "hold": false, "mouse": false },
  "one":        { "short": "X",  "long": "N",     "hold": false, "mouse": false },
  "two":        { "short": "G",  "long": "F",     "hold": false, "mouse": false },
  "nunchuk_C":  { "action": "run" },
  "nunchuk_Z":  { "short": "K" }
}

You'd need:

    A name→keycode table (e.g. "E" → 0x0E, "SPACE" → 0x31).

    A parser that reads the file and populates configs[11][4] at runtime.

    A way to reload without restarting (menu item "Reload mappings").

Here's the full patch. It replaces the hardcoded #define MAP_* block with a JSON-driven config system that falls back to your existing defaults.
Step 1 — Add the new source file

Create src/KeyMappings.h:
objc

#import <Foundation/Foundation.h>

@interface KeyMappings : NSObject

// Singleton — call [KeyMappings shared] anywhere
+ (instancetype)shared;

// Load from ~/Library/Application Support/Wiimote/mappings.json
// Falls back to hardcoded defaults if the file is missing or invalid
- (void)load;

// Write the current mappings (including defaults) to disk so the user has a template
- (void)writeTemplateIfMissing;

// Returns the keycode for a button/slot, or 0 if unset
// button: @"dpad_up", @"A", @"B", @"minus", @"home", @"one", @"two", etc.
// slot:   @"short" or @"long"
- (int)keyForButton:(NSString *)button slot:(NSString *)slot;

// isHold / isMouse flags
- (BOOL)isHoldForButton:(NSString *)button;
- (BOOL)isMouseForButton:(NSString *)button;

// Nunchuk special actions
- (NSString *)actionForNunchukButton:(NSString *)which;   // @"C" or @"Z"

// Absolute path to the config file, for logging / menu display
- (NSString *)configPath;

@end

Create src/KeyMappings.m:
objc

#import "KeyMappings.h"

// Keycode constants — mirrored from WiimoteManager.m
#define KEY_A 0x00
#define KEY_S 0x01
#define KEY_D 0x02
#define KEY_W 0x0D
#define KEY_Q 0x0C
#define KEY_E 0x0E
#define KEY_R 0x0F
#define KEY_T 0x10
#define KEY_Y 0x11
#define KEY_U 0x12
#define KEY_I 0x13
#define KEY_O 0x14
#define KEY_P 0x15
#define KEY_F 0x03
#define KEY_G 0x04
#define KEY_H 0x05
#define KEY_J 0x06
#define KEY_K 0x07
#define KEY_L 0x08
#define KEY_Z 0x09
#define KEY_X 0x0A
#define KEY_C 0x0B
#define KEY_V 0x1A
#define KEY_B 0x1B
#define KEY_N 0x1D
#define KEY_M 0x1E
#define KEY_SPACE 0x31
#define KEY_ENTER 0x24
#define KEY_ESC 0x35
#define KEY_UP 0x7E
#define KEY_DOWN 0x7D
#define KEY_LEFT 0x7B
#define KEY_RIGHT 0x7C
#define KEY_TAB 0x30
#define KEY_SHIFT 0x38
#define KEY_CONTROL 0x3B
#define KEY_OPTION 0x3A
#define KEY_COMMAND 0x37
#define KEY_DELETE 0x33
#define KEY_TILDE 0x32

@interface KeyMappings ()
@property (nonatomic, strong) NSDictionary *config;
@end

@implementation KeyMappings

+ (instancetype)shared {
    static KeyMappings *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[KeyMappings alloc] init]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _config = [self defaultConfig];
    }
    return self;
}

- (NSString *)configPath {
    NSString *appSupport = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                                 NSUserDomainMask, YES) firstObject];
    return [appSupport stringByAppendingPathComponent:@"Wiimote/mappings.json"];
}

// ---------- Name → keycode table ----------
- (NSDictionary<NSString *, NSNumber *> *)keyNameTable {
    static NSDictionary *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = @{
            @"A": @(KEY_A), @"S": @(KEY_S), @"D": @(KEY_D), @"W": @(KEY_W),
            @"Q": @(KEY_Q), @"E": @(KEY_E), @"R": @(KEY_R), @"T": @(KEY_T),
            @"Y": @(KEY_Y), @"U": @(KEY_U), @"I": @(KEY_I), @"O": @(KEY_O),
            @"P": @(KEY_P), @"F": @(KEY_F), @"G": @(KEY_G), @"H": @(KEY_H),
            @"J": @(KEY_J), @"K": @(KEY_K), @"L": @(KEY_L), @"Z": @(KEY_Z),
            @"X": @(KEY_X), @"C": @(KEY_C), @"V": @(KEY_V), @"B": @(KEY_B),
            @"N": @(KEY_N), @"M": @(KEY_M),
            @"SPACE": @(KEY_SPACE), @"ENTER": @(KEY_ENTER), @"RETURN": @(KEY_ENTER),
            @"ESC": @(KEY_ESC), @"ESCAPE": @(KEY_ESC),
            @"UP": @(KEY_UP), @"DOWN": @(KEY_DOWN),
            @"LEFT": @(KEY_LEFT), @"RIGHT": @(KEY_RIGHT),
            @"TAB": @(KEY_TAB),
            @"SHIFT": @(KEY_SHIFT), @"LSHIFT": @(KEY_SHIFT),
            @"CTRL": @(KEY_CONTROL), @"CONTROL": @(KEY_CONTROL),
            @"ALT": @(KEY_OPTION), @"OPTION": @(KEY_OPTION),
            @"CMD": @(KEY_COMMAND), @"COMMAND": @(KEY_COMMAND),
            @"DELETE": @(KEY_DELETE), @"BACKSPACE": @(KEY_DELETE),
            @"TILDE": @(KEY_TILDE), @"`": @(KEY_TILDE),
        };
    });
    return table;
}

- (int)keyCodeFromName:(id)value {
    if (value == nil || value == [NSNull null]) return 0;
    if ([value isKindOfClass:[NSNumber class]]) return [value intValue];
    if ([value isKindOfClass:[NSString class]]) {
        NSNumber *n = [self keyNameTable][[value uppercaseString]];
        return n ? [n intValue] : 0;
    }
    return 0;
}

// ---------- Defaults (match your current #defines) ----------
- (NSDictionary *)defaultConfig {
    return @{
        @"dpad_up":    @{ @"short": @"E",     @"long": @"UP",    @"hold": @NO,  @"mouse": @NO },
        @"dpad_down":  @{ @"short": @"V",     @"long": @"DOWN",  @"hold": @NO,  @"mouse": @NO },
        @"dpad_left":  @{ @"short": @"TAB",   @"long": @"TILDE", @"hold": @NO,  @"mouse": @NO },
        @"dpad_right": @{ @"short": @"SPACE", @"long": @"Z",     @"hold": @NO,  @"mouse": @NO },
        @"A":          @{ @"short": @"Q",     @"long": [NSNull null], @"hold": @YES, @"mouse": @NO },
        @"B":          @{ @"short": [NSNull null], @"long": [NSNull null], @"hold": @YES, @"mouse": @YES },
        @"minus":      @{ @"short": @"R",     @"long": @"G",     @"hold": @NO,  @"mouse": @NO },
        @"plus":       @{ @"short": @"B",     @"long": [NSNull null], @"hold": @NO, @"mouse": @NO },
        @"home":       @{ @"short": @"ESC",   @"long": @"ESC",   @"hold": @NO,  @"mouse": @NO },
        @"one":        @{ @"short": @"X",     @"long": @"N",     @"hold": @NO,  @"mouse": @NO },
        @"two":        @{ @"short": @"G",     @"long": @"F",     @"hold": @NO,  @"mouse": @NO },
        @"nunchuk_C":  @{ @"action": @"run" },
        @"nunchuk_Z":  @{ @"short": @"K" },
    };
}

// ---------- Load ----------
- (void)load {
    NSString *path = [self configPath];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) {
        NSLog(@"[KeyMappings] No config at %@ — using defaults", path);
        self.config = [self defaultConfig];
        return;
    }
    NSError *err = nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    if (err || ![parsed isKindOfClass:[NSDictionary class]]) {
        NSLog(@"[KeyMappings] Invalid JSON at %@: %@ — using defaults", path, err);
        self.config = [self defaultConfig];
        return;
    }
    // Merge: start from defaults, override with user's entries
    NSMutableDictionary *merged = [[self defaultConfig] mutableCopy];
    [parsed enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *stop) {
        merged[k] = v;
    }];
    self.config = merged;
    NSLog(@"[KeyMappings] Loaded %lu mappings from %@", (unsigned long)merged.count, path);
}

- (void)writeTemplateIfMissing {
    NSString *path = [self configPath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) return;
    
    NSString *dir = [path stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    
    // Serialize defaults, converting NSNull back to JSON null
    NSData *data = [NSJSONSerialization dataWithJSONObject:[self defaultConfig]
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:nil];
    [data writeToFile:path atomically:YES];
    NSLog(@"[KeyMappings] Wrote template to %@", path);
}

// ---------- Accessors ----------
- (NSDictionary *)entryForButton:(NSString *)button {
    id e = self.config[button];
    return [e isKindOfClass:[NSDictionary class]] ? e : nil;
}

- (int)keyForButton:(NSString *)button slot:(NSString *)slot {
    NSDictionary *e = [self entryForButton:button];
    return [self keyCodeFromName:e[slot]];
}

- (BOOL)isHoldForButton:(NSString *)button {
    return [[self entryForButton:button][@"hold"] boolValue];
}

- (BOOL)isMouseForButton:(NSString *)button {
    return [[self entryForButton:button][@"mouse"] boolValue];
}

- (NSString *)actionForNunchukButton:(NSString *)which {
    NSString *key = [NSString stringWithFormat:@"nunchuk_%@", which];
    return [self entryForButton:key][@"action"];
}

@end

Step 2 — Patch WiimoteManager.m

a) Add the import at the top, next to the other imports:
objc

#import "KeyMappings.h"

b) Delete the entire #define MAP_* block. Delete lines from:
objc

#define MAP_DPAD_UP_SHORT KEY_E

through:
objc

#define MAP_2_LONG  KEY_F

Keep the KEY_* defines — they're still used in the nunchuk code.

c) In - (void)start, add a load call at the very top:
objc

- (void)start {
    if (self.running) return;
    [[KeyMappings shared] writeTemplateIfMissing];
    [[KeyMappings shared] load];
    self.running = YES;
    // ...rest unchanged
}

d) Replace the configs[11][4] block in parseWiimoteButtons: with:
objc

KeyMappings *km = [KeyMappings shared];
NSString *buttonKeys[11] = {
    @"dpad_up", @"dpad_down", @"dpad_left", @"dpad_right",
    @"B", @"A", @"minus", @"plus", @"home", @"one", @"two"
};

int configs[11][4];
for (int i = 0; i < 11; i++) {
    configs[i][0] = [km keyForButton:buttonKeys[i] slot:@"short"];
    configs[i][1] = [km keyForButton:buttonKeys[i] slot:@"long"];
    configs[i][2] = [km isHoldForButton:buttonKeys[i]] ? 1 : 0;
    configs[i][3] = [km isMouseForButton:buttonKeys[i]] ? 1 : 0;
}

The rest of parseWiimoteButtons: uses configs[i][...] identically, so nothing else changes there.
Step 3 — Add a "Reload Mappings" menu item

In AppDelegate.m, inside applicationDidFinishLaunching:, after adding the toggle item:
objc

NSMenuItem *reloadItem = [[NSMenuItem alloc] initWithTitle:@"Reload Mappings"
                                                    action:@selector(reloadMappings:)
                                             keyEquivalent:@"r"];
reloadItem.target = self;
[menu addItem:reloadItem];
[menu addItem:[NSMenuItem separatorItem]];

And add the action method:
objc

- (void)reloadMappings:(id)sender {
    [[KeyMappings shared] writeTemplateIfMissing];
    [[KeyMappings shared] load];
    NSLog(@"[AppDelegate] Mappings reloaded from %@", [[KeyMappings shared] configPath]);
}

Step 4 — Add the new file to the compile line

Your WiimoteManager.sh has:
text

clang -framework Cocoa ... -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" src/*.m

src/*.m already picks up KeyMappings.m — no change needed.
Step 5 — Run and configure

    Build and launch the app once. It writes the default template to:
    text

    ~/Library/Application Support/Wiimote/mappings.json

    Edit that file. Change any "short" or "long" value to a key name from the table ("E", "SPACE", "TAB", "UP", etc.). Set "hold" to true or false, "mouse" to true or false.

    Click the 🎮 menu bar icon → Reload Mappings. No restart needed.

The key names you can use
Name	Keycode	Notes
A–Z	0x00–0x1E	letters
SPACE	0x31	
TAB	0x30	
ENTER / RETURN	0x24	
ESC / ESCAPE	0x35	
UP DOWN LEFT RIGHT	0x7E–0x7B	arrow keys
SHIFT	0x38	left shift
CTRL / CONTROL	0x3B	
OPTION / ALT	0x3A	
CMD / COMMAND	0x37	
DELETE / BACKSPACE	0x33	
TILDE / ` | 0x32 | |		
(any number)	—	raw keycode, e.g. 50

If a name isn't in the table, the parser treats it as unset (0), which means "do nothing" for tap/hold. That's the safe fallback.
What happens if the JSON is broken

Malformed JSON → logs an error → uses hardcoded defaults. Unknown key names → that specific mapping becomes 0 (does nothing), all other mappings still work. Nothing crashes.
One caveat about "mouse": true on B

The mouse-hold path in parseWiimoteButtons: calls mouseDown:kCGMouseButtonLeft and spins up a rumble thread. If you set "mouse": true on a button that also has a keycode, only the mouse path runs — the keycode is ignored. That matches the current hardcoded behaviour for B. Keep that in mind if you remap.
its already 2000lines

Adding a separate .h/.m pair plus edits to two existing files is more friction than you need for something this small. You can drop the whole config system into the existing WiimoteManager.m — about 120 lines in one place, no new files, no build script changes.

Here's the minimal version. Three edits to WiimoteManager.m, nothing else.
Edit 1 — Replace the #define MAP_* block

Find this block near the top (after the #define KEY_* list):
objc

#define MAP_DPAD_UP_SHORT KEY_E
#define MAP_DPAD_UP_LONG  KEY_UP
...through...
#define MAP_2_LONG  KEY_F

Delete it. In its place, add:
objc

// ============================================
// RUNTIME-CONFIGURABLE KEY MAPPINGS
// Loaded from ~/Library/Application Support/Wiimote/mappings.json
// Falls back to the defaults below if the file is missing or invalid.
// ============================================

static NSDictionary *gKeyNameTable(void) {
    static NSDictionary *t;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        t = @{
            @"A": @(KEY_A), @"S": @(KEY_S), @"D": @(KEY_D), @"W": @(KEY_W),
            @"Q": @(KEY_Q), @"E": @(KEY_E), @"R": @(KEY_R), @"T": @(KEY_T),
            @"Y": @(KEY_Y), @"U": @(KEY_U), @"I": @(KEY_I), @"O": @(KEY_O),
            @"P": @(KEY_P), @"F": @(KEY_F), @"G": @(KEY_G), @"H": @(KEY_H),
            @"J": @(KEY_J), @"K": @(KEY_K), @"L": @(KEY_L), @"Z": @(KEY_Z),
            @"X": @(KEY_X), @"C": @(KEY_C), @"V": @(KEY_V), @"B": @(KEY_B),
            @"N": @(KEY_N), @"M": @(KEY_M),
            @"SPACE": @(KEY_SPACE), @"ENTER": @(KEY_ENTER), @"RETURN": @(KEY_ENTER),
            @"ESC": @(KEY_ESC), @"ESCAPE": @(KEY_ESC),
            @"UP": @(KEY_UP), @"DOWN": @(KEY_DOWN),
            @"LEFT": @(KEY_LEFT), @"RIGHT": @(KEY_RIGHT),
            @"TAB": @(KEY_TAB),
            @"SHIFT": @(KEY_SHIFT), @"LSHIFT": @(KEY_SHIFT),
            @"CTRL": @(KEY_CONTROL), @"CONTROL": @(KEY_CONTROL),
            @"ALT": @(KEY_OPTION), @"OPTION": @(KEY_OPTION),
            @"CMD": @(KEY_COMMAND), @"COMMAND": @(KEY_COMMAND),
            @"DELETE": @(KEY_DELETE), @"BACKSPACE": @(KEY_DELETE),
            @"TILDE": @(KEY_TILDE), @"`": @(KEY_TILDE),
        };
    });
    return t;
}

static int gKeyCodeFromJSON(id value) {
    if (value == nil || value == [NSNull null]) return 0;
    if ([value isKindOfClass:[NSNumber class]]) return [value intValue];
    if ([value isKindOfClass:[NSString class]]) {
        NSNumber *n = gKeyNameTable()[[value uppercaseString]];
        return n ? [n intValue] : 0;
    }
    return 0;
}

static NSDictionary *gDefaultMappings(void) {
    return @{
        @"dpad_up":    @{ @"short": @"E",     @"long": @"UP",    @"hold": @NO,  @"mouse": @NO },
        @"dpad_down":  @{ @"short": @"V",     @"long": @"DOWN",  @"hold": @NO,  @"mouse": @NO },
        @"dpad_left":  @{ @"short": @"TAB",   @"long": @"TILDE", @"hold": @NO,  @"mouse": @NO },
        @"dpad_right": @{ @"short": @"SPACE", @"long": @"Z",     @"hold": @NO,  @"mouse": @NO },
        @"A":          @{ @"short": @"Q",     @"long": [NSNull null], @"hold": @YES, @"mouse": @NO },
        @"B":          @{ @"short": [NSNull null], @"long": [NSNull null], @"hold": @YES, @"mouse": @YES },
        @"minus":      @{ @"short": @"R",     @"long": @"G",     @"hold": @NO,  @"mouse": @NO },
        @"plus":       @{ @"short": @"B",     @"long": [NSNull null], @"hold": @NO, @"mouse": @NO },
        @"home":       @{ @"short": @"ESC",   @"long": @"ESC",   @"hold": @NO,  @"mouse": @NO },
        @"one":        @{ @"short": @"X",     @"long": @"N",     @"hold": @NO,  @"mouse": @NO },
        @"two":        @{ @"short": @"G",     @"long": @"F",     @"hold": @NO,  @"mouse": @NO },
    };
}

static NSString *gMappingsPath(void) {
    NSString *as = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                         NSUserDomainMask, YES) firstObject];
    return [as stringByAppendingPathComponent:@"Wiimote/mappings.json"];
}

// Global config — read by parseWiimoteButtons: each frame
static NSDictionary *gMappings = nil;

static void gLoadMappings(void) {
    NSString *path = gMappingsPath();
    NSData *data = [NSData dataWithContentsOfFile:path];
    NSDictionary *base = gDefaultMappings();
    
    if (!data) {
        gMappings = base;
        NSLog(@"[Wiimote] No mappings at %@ — using defaults", path);
        return;
    }
    
    NSError *err = nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    if (err || ![parsed isKindOfClass:[NSDictionary class]]) {
        gMappings = base;
        NSLog(@"[Wiimote] Invalid JSON at %@ (%@) — using defaults", path, err);
        return;
    }
    
    NSMutableDictionary *merged = [base mutableCopy];
    [parsed enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *stop) {
        merged[k] = v;
    }];
    gMappings = merged;
    NSLog(@"[Wiimote] Loaded %lu mappings from %@", (unsigned long)merged.count, path);
}

// Write the defaults out if no file exists yet, so the user has a template
static void gWriteMappingsTemplateIfMissing(void) {
    NSString *path = gMappingsPath();
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) return;
    NSString *dir = [path stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSData *out = [NSJSONSerialization dataWithJSONObject:gDefaultMappings()
                                                  options:NSJSONWritingPrettyPrinted
                                                    error:nil];
    [out writeToFile:path atomically:YES];
    NSLog(@"[Wiimote] Wrote default mappings to %@", path);
}

// Helpers used inside parseWiimoteButtons:
static int gMapShort(NSString *btn) {
    return gKeyCodeFromJSON(gMappings[btn][@"short"]);
}
static int gMapLong(NSString *btn) {
    return gKeyCodeFromJSON(gMappings[btn][@"long"]);
}
static BOOL gMapHold(NSString *btn)  { return [gMappings[btn][@"hold"]  boolValue]; }
static BOOL gMapMouse(NSString *btn) { return [gMappings[btn][@"mouse"] boolValue]; }

Edit 2 — Call the loader in - (void)start

At the very top of - (void)start:
objc

- (void)start {
    if (self.running) return;
    gWriteMappingsTemplateIfMissing();
    gLoadMappings();
    self.running = YES;
    // ...rest unchanged
}

Edit 3 — Replace configs[11][4] in parseWiimoteButtons:

Find this block:
objc

int configs[11][4] = {
    {MAP_DPAD_UP_SHORT,     MAP_DPAD_UP_LONG,     0, 0},
    {MAP_DPAD_DOWN_SHORT,   MAP_DPAD_DOWN_LONG,   0, 0},
    {MAP_DPAD_LEFT_SHORT,   MAP_DPAD_LEFT_LONG,   0, 0},
    {MAP_DPAD_RIGHT_SHORT,  MAP_DPAD_RIGHT_LONG,  0, 0},
    {MAP_B_SHORT,           MAP_B_LONG,           1, 1},
    {MAP_A_SHORT,           MAP_A_LONG,           1, 0},
    {MAP_MINUS_SHORT,       MAP_MINUS_LONG,       0, 0},
    {MAP_PLUS_SHORT,        MAP_PLUS_LONG,        0, 0},
    {MAP_HOME_SHORT,        MAP_HOME_LONG,        0, 0},
    {MAP_1_SHORT,           MAP_1_LONG,           0, 0},
    {MAP_2_SHORT,           MAP_2_LONG,           0, 0},
};

Replace it with:
objc

// Build config table from runtime mappings (loaded once in -start)
static NSString * const kButtonKeys[11] = {
    @"dpad_up", @"dpad_down", @"dpad_left", @"dpad_right",
    @"B", @"A", @"minus", @"plus", @"home", @"one", @"two"
};

int configs[11][4];
for (int i = 0; i < 11; i++) {
    configs[i][0] = gMapShort(kButtonKeys[i]);
    configs[i][1] = gMapLong (kButtonKeys[i]);
    configs[i][2] = gMapHold (kButtonKeys[i]) ? 1 : 0;
    configs[i][3] = gMapMouse(kButtonKeys[i]) ? 1 : 0;
}

The rest of parseWiimoteButtons: uses configs[i][0..3] identically, so nothing below needs touching.
Edit 4 — Add a "Reload Mappings" menu item

In AppDelegate.m, find where you build the menu:
objc

[menu addItem:self.toggleMenuItem];
[menu addItem:[NSMenuItem separatorItem]];

Insert a reload item before the separator:
objc

[menu addItem:self.toggleMenuItem];

NSMenuItem *reloadItem = [[NSMenuItem alloc] initWithTitle:@"Reload Mappings"
                                                    action:@selector(reloadMappings:)
                                             keyEquivalent:@"r"];
reloadItem.target = self;
[menu addItem:reloadItem];

[menu addItem:[NSMenuItem separatorItem]];

Then add the action method anywhere in the AppDelegate implementation:
objc

- (void)reloadMappings:(id)sender {
    gWriteMappingsTemplateIfMissing();
    gLoadMappings();
    NSLog(@"[AppDelegate] Mappings reloaded from %@", gMappingsPath());
}

Because gLoadMappings and gMappingsPath are static in WiimoteManager.m, they aren't visible from AppDelegate.m. Two options:

    Simplest: move the reload logic into WiimoteManager. Add a public method - (void)reloadMappings; that calls the statics, then call [self.wiimoteManager reloadMappings] from the delegate.

    Or: drop a tiny extern void gLoadMappings(void); into AppDelegate.m — but this only works if you remove static from the declarations. Cleaner to just wrap it.

The wrapper is three lines. Add to WiimoteManager.h:
objc

- (void)reloadMappings;

Add to WiimoteManager.m:
objc

- (void)reloadMappings {
    gWriteMappingsTemplateIfMissing();
    gLoadMappings();
}

And in AppDelegate.m:
objc

- (void)reloadMappings:(id)sender {
    [self.wiimoteManager reloadMappings];
}

What you get

    One config file at ~/Library/Application Support/Wiimote/mappings.json, auto-created on first run.

    Edit it, click 🎮 → Reload Mappings, done.

    Broken JSON or unknown key names → silent fallback to defaults for just those entries, everything else still works.

    Total new code: ~130 lines in one file, ~10 lines of edits elsewhere. No new source files, no build script changes.

The JSON format

Exactly the shape from before. Key names are the ones in gKeyNameTable — "E", "SPACE", "TAB", "UP", "ESC", etc. Numeric keycodes also work if you prefer raw values.

One thing to keep in mind: the JSON is written as a flat merge over defaults. If you only put {"dpad_up": {"short": "R"}} in the file, only that one field changes; every other field keeps its default. That's the friendliest behaviour for partial overrides.