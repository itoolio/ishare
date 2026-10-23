#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#include <signal.h>

@interface CGVirtualDisplayDescriptor : NSObject
@property(retain, nonatomic) dispatch_queue_t queue;
@property(retain, nonatomic) NSString *name;
@property(nonatomic) unsigned int maxPixelsHigh;
@property(nonatomic) unsigned int maxPixelsWide;
@property(nonatomic) CGSize sizeInMillimeters;
@property(nonatomic) unsigned int serialNum;
@property(nonatomic) unsigned int productID;
@property(nonatomic) unsigned int vendorID;
@property(copy, nonatomic) void (^terminationHandler)(id, id);
@end

@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:(double)refreshRate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property(retain, nonatomic) NSArray *modes;
@property(nonatomic) unsigned int hiDPI;
@end

@interface CGVirtualDisplay : NSObject
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@property(readonly, nonatomic) unsigned int displayID;
@end

static CGVirtualDisplay *virtualDisplay;

static unsigned int argumentValue(int argc, const char *argv[], const char *name, unsigned int fallback) {
    for (int index = 1; index + 1 < argc; index++) {
        if (strcmp(argv[index], name) == 0) {
            return (unsigned int)strtoul(argv[index + 1], NULL, 10);
        }
    }
    return fallback;
}

static CGDisplayModeRef findMode(CGDirectDisplayID display, size_t width, size_t height, size_t pixelWidth, size_t pixelHeight) {
    NSDictionary *options = @{(__bridge NSString *)kCGDisplayShowDuplicateLowResolutionModes: @YES};
    CFArrayRef modes = CGDisplayCopyAllDisplayModes(display, (__bridge CFDictionaryRef)options);
    CGDisplayModeRef match = NULL;
    for (CFIndex index = 0; modes && index < CFArrayGetCount(modes); index++) {
        CGDisplayModeRef mode = (CGDisplayModeRef)CFArrayGetValueAtIndex(modes, index);
        if (CGDisplayModeGetWidth(mode) == width && CGDisplayModeGetHeight(mode) == height &&
            CGDisplayModeGetPixelWidth(mode) == pixelWidth && CGDisplayModeGetPixelHeight(mode) == pixelHeight) {
            match = CGDisplayModeRetain(mode);
            break;
        }
    }
    if (modes) {
        CFRelease(modes);
    }
    return match;
}

static BOOL makeMain(CGDirectDisplayID display, unsigned int width) {
    CGDirectDisplayID displays[16];
    uint32_t count = 0;
    if (CGGetActiveDisplayList(16, displays, &count) != kCGErrorSuccess) {
        return NO;
    }
    CGDisplayConfigRef configuration;
    if (CGBeginDisplayConfiguration(&configuration) != kCGErrorSuccess) {
        return NO;
    }
    CGConfigureDisplayOrigin(configuration, display, 0, 0);
    int32_t x = (int32_t)width;
    for (uint32_t index = 0; index < count; index++) {
        if (displays[index] == display) {
            continue;
        }
        CGConfigureDisplayOrigin(configuration, displays[index], x, 0);
        x += (int32_t)CGDisplayPixelsWide(displays[index]);
    }
    return CGCompleteDisplayConfiguration(configuration, kCGConfigureForSession) == kCGErrorSuccess;
}

static void stop(int signal) {
    virtualDisplay = nil;
    exit(0);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        unsigned int width = argumentValue(argc, argv, "--width", 1680);
        unsigned int height = argumentValue(argc, argv, "--height", 1050);
        unsigned int scale = argumentValue(argc, argv, "--scale", 2);
        unsigned int pixelWidth = width * scale;
        unsigned int pixelHeight = height * scale;

        CGVirtualDisplayDescriptor *descriptor = [[CGVirtualDisplayDescriptor alloc] init];
        descriptor.queue = dispatch_get_main_queue();
        descriptor.name = @"ishare screenshots";
        descriptor.maxPixelsWide = pixelWidth;
        descriptor.maxPixelsHigh = pixelHeight;
        descriptor.sizeInMillimeters = CGSizeMake(width * 25.4 / 110.0, height * 25.4 / 110.0);
        descriptor.serialNum = 0x15A5;
        descriptor.productID = 0x15A5;
        descriptor.vendorID = 0x15A5;
        descriptor.terminationHandler = ^(id display, id error) {
            fprintf(stderr, "the virtual display was terminated\n");
            exit(1);
        };

        virtualDisplay = [[CGVirtualDisplay alloc] initWithDescriptor:descriptor];
        if (!virtualDisplay || virtualDisplay.displayID == 0) {
            fprintf(stderr, "couldn't create a virtual display\n");
            return 1;
        }
        CGVirtualDisplaySettings *settings = [[CGVirtualDisplaySettings alloc] init];
        settings.hiDPI = scale > 1 ? 1 : 0;
        settings.modes = @[
            [[CGVirtualDisplayMode alloc] initWithWidth:width height:height refreshRate:60],
            [[CGVirtualDisplayMode alloc] initWithWidth:pixelWidth height:pixelHeight refreshRate:60],
        ];
        if (![virtualDisplay applySettings:settings]) {
            fprintf(stderr, "couldn't apply the virtual display settings\n");
            return 1;
        }
        CGDirectDisplayID display = virtualDisplay.displayID;

        CGDisplayModeRef mode = NULL;
        for (int attempt = 0; attempt < 50 && !mode; attempt++) {
            [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
            mode = findMode(display, width, height, pixelWidth, pixelHeight);
        }
        if (!mode) {
            fprintf(stderr, "the virtual display has no %ux%u mode at %ux scale\n", width, height, scale);
            return 1;
        }
        CGDisplaySetDisplayMode(display, mode, NULL);
        CGDisplayModeRelease(mode);
        if (!makeMain(display, width)) {
            fprintf(stderr, "couldn't make the virtual display the main display\n");
            return 1;
        }
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];

        CGDisplayModeRef current = CGDisplayCopyDisplayMode(display);
        printf("ready display=%u points=%zux%zu pixels=%zux%zu main=%d\n", display, CGDisplayModeGetWidth(current),
               CGDisplayModeGetHeight(current), CGDisplayModeGetPixelWidth(current), CGDisplayModeGetPixelHeight(current),
               CGMainDisplayID() == display);
        fflush(stdout);
        CGDisplayModeRelease(current);

        signal(SIGTERM, stop);
        signal(SIGINT, stop);
        [[NSRunLoop mainRunLoop] run];
    }
    return 0;
}
