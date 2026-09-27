#import "VirtualDisplay.h"

// Private interfaces from CoreGraphics, declared here so the compiler knows their shape.
@interface CGVirtualDisplayDescriptor : NSObject
@property (retain, nonatomic) dispatch_queue_t queue;
@property (retain, nonatomic) NSString *name;
@property (nonatomic) unsigned int maxPixelsHigh;
@property (nonatomic) unsigned int maxPixelsWide;
@property (nonatomic) CGSize sizeInMillimeters;
@property (nonatomic) unsigned int serialNum;
@property (nonatomic) unsigned int productID;
@property (nonatomic) unsigned int vendorID;
@property (nonatomic) CGPoint redPrimary;
@property (nonatomic) CGPoint greenPrimary;
@property (nonatomic) CGPoint bluePrimary;
@property (nonatomic) CGPoint whitePoint;
@property (copy, nonatomic) void (^terminationHandler)(id, id);
@end

@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:(double)refreshRate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property (retain, nonatomic) NSArray *modes;
@property (nonatomic) unsigned int hiDPI;
@end

@interface CGVirtualDisplay : NSObject
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@property (readonly, nonatomic) CGDirectDisplayID displayID;
@end

@implementation UMBVirtualDisplay {
    id _display;
}

+ (instancetype)displayWithName:(NSString *)name width:(unsigned int)width height:(unsigned int)height
                       vendorID:(unsigned int)vendorID productID:(unsigned int)productID serial:(unsigned int)serial {
    // Autorelease pools keep no hidden references, so the screen goes away as soon as destroy is called.
    UMBVirtualDisplay *wrapper = nil;
    @autoreleasepool {
    Class descClass = NSClassFromString(@"CGVirtualDisplayDescriptor");
    Class displayClass = NSClassFromString(@"CGVirtualDisplay");
    Class settingsClass = NSClassFromString(@"CGVirtualDisplaySettings");
    Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");
    if (!descClass || !displayClass || !settingsClass || !modeClass) return nil;

    CGVirtualDisplayDescriptor *desc = [[descClass alloc] init];
    desc.queue = dispatch_get_main_queue();
    desc.name = name;
    desc.maxPixelsWide = width;
    desc.maxPixelsHigh = height;
    desc.sizeInMillimeters = CGSizeMake(width * 0.25, height * 0.25);
    desc.vendorID = vendorID;
    desc.productID = productID;
    desc.serialNum = serial;
    // sRGB primaries, so gamma tables behave like a normal monitor.
    desc.redPrimary = CGPointMake(0.64, 0.33);
    desc.greenPrimary = CGPointMake(0.30, 0.60);
    desc.bluePrimary = CGPointMake(0.15, 0.06);
    desc.whitePoint = CGPointMake(0.3127, 0.3290);
    desc.terminationHandler = ^(id a, id b) {};

    CGVirtualDisplay *display = [[displayClass alloc] initWithDescriptor:desc];
    if (!display) return nil;
    CGVirtualDisplaySettings *settings = [[settingsClass alloc] init];
    settings.hiDPI = 0;
    settings.modes = @[[[modeClass alloc] initWithWidth:width height:height refreshRate:60]];
    if (![display applySettings:settings]) return nil;

    wrapper = [[UMBVirtualDisplay alloc] init];
    wrapper->_display = display;
    }
    return wrapper;
}

- (CGDirectDisplayID)displayID { return [(CGVirtualDisplay *)_display displayID]; }
- (void)destroy { @autoreleasepool { _display = nil; } }
@end
