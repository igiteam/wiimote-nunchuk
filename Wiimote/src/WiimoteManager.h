#import <Foundation/Foundation.h>

@interface WiimoteManager : NSObject
@property (nonatomic, assign) uint8_t currentMode;
- (void)start;
- (void)stop;
@end
