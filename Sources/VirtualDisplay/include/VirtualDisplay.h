// Test-only bridge to macOS's private CGVirtualDisplay API (the same one DeskPad and BetterDisplay use).
// It creates real, software-only screens that the window server treats like connected monitors.
// Only the test target links this; the Umbra app never does.
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface UMBVirtualDisplay : NSObject
/// Create a virtual display. Returns nil if the private API isn't available on this macOS.
+ (nullable instancetype)displayWithName:(NSString *)name
                                   width:(unsigned int)width
                                  height:(unsigned int)height
                                vendorID:(unsigned int)vendorID
                               productID:(unsigned int)productID
                                  serial:(unsigned int)serial;
@property (readonly) CGDirectDisplayID displayID;
/// Remove the display. It also goes away when this object is released.
- (void)destroy;
@end

NS_ASSUME_NONNULL_END
