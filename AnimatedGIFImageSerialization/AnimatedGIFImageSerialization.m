// AnimatedGIFImageSerialization.m
//
// Copyright (c) 2014 Mattt Thompson (http://mattt.me/)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "AnimatedGIFImageSerialization.h"

#import <ImageIO/ImageIO.h>
#import <MobileCoreServices/MobileCoreServices.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, AnimatedGifScreenType) {
    AnimatedGifScreenType480h = 480, // iPhone 1, 2, 3, 4, 4s
    AnimatedGifScreenType568h = 568, // iPhone 5, iPhone 5s
    AnimatedGifScreenType667h = 667, // iPhone 6
    AnimatedGifScreenType736h = 736, // iPhone 6+
    AnimatedGifScreenTypeUnknown = 0
};

NSString * const AnimatedGifScreenTypeSuffix480h = @"";
NSString * const AnimatedGifScreenTypeSuffix568h = @"-568h";
NSString * const AnimatedGifScreenTypeSuffix667h = @"-667h";
NSString * const AnimatedGifScreenTypeSuffix736h = @"-736h";

NSString * const AnimatedGIFImageErrorDomain = @"com.compuserve.gif.image.error";

__attribute__((overloadable)) UIImage * UIImageWithAnimatedGIFData(NSData *data) {
    return UIImageWithAnimatedGIFData(data, [[UIScreen mainScreen] scale], 0.0f, nil);
}

__attribute__((overloadable)) UIImage * UIImageWithAnimatedGIFData(NSData *data, CGFloat scale, NSTimeInterval duration, NSError * __autoreleasing *error) {
    if (!data) {
        return nil;
    }

    NSMutableDictionary *mutableOptions = [NSMutableDictionary dictionary];
    [mutableOptions setObject:@(YES) forKey:(NSString *)kCGImageSourceShouldCache];
    [mutableOptions setObject:(NSString *)kUTTypeGIF forKey:(NSString *)kCGImageSourceTypeIdentifierHint];

    CGImageSourceRef imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)data, (__bridge CFDictionaryRef)mutableOptions);

    size_t numberOfFrames = CGImageSourceGetCount(imageSource);
    NSMutableArray *mutableImages = [NSMutableArray arrayWithCapacity:numberOfFrames];

    NSUInteger calculatedDuration = 0.0f;
    for (size_t idx = 0; idx < numberOfFrames; idx++) {
        CGImageRef imageRef = CGImageSourceCreateImageAtIndex(imageSource, idx, (__bridge CFDictionaryRef)mutableOptions);

        NSDictionary *properties = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(imageSource, idx, NULL);
        NSDictionary *gifProperties = properties[(__bridge NSString *)kCGImagePropertyGIFDictionary];

        NSNumber *delay = gifProperties[(__bridge NSString *)kCGImagePropertyGIFUnclampedDelayTime];
        if (!delay) {
            delay = gifProperties[(__bridge NSString *)kCGImagePropertyGIFDelayTime];
        }

        calculatedDuration += [delay doubleValue];

        [mutableImages addObject:[UIImage imageWithCGImage:imageRef scale:scale orientation:UIImageOrientationUp]];

        CGImageRelease(imageRef);
    }

    CFRelease(imageSource);

    if (numberOfFrames == 1) {
        return [mutableImages firstObject];
    } else {
        return [UIImage animatedImageWithImages:mutableImages duration:(duration <= 0.0f ? calculatedDuration : duration)];
    }
}

static BOOL AnimatedGifDataIsValid(NSData *data) {
    if (data.length > 4) {
        const unsigned char * bytes = [data bytes];

        return bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46;
    }

    return NO;
}

__attribute__((overloadable)) NSData * UIImageAnimatedGIFRepresentation(UIImage *image) {
    return UIImageAnimatedGIFRepresentation(image, 0.0f, 0, nil);
}

__attribute__((overloadable)) NSData * UIImageAnimatedGIFRepresentation(UIImage *image, NSTimeInterval duration, NSUInteger loopCount, NSError * __autoreleasing *error) {
    if (!image) {
        return nil;
    }
    
    NSArray *images = image.images;
    if (!images) {
        images = @[image];
    }
    
    NSDictionary *userInfo = nil;
    {
        size_t frameCount = images.count;
        NSTimeInterval frameDuration = (duration <= 0.0 ? image.duration / frameCount : duration / frameCount);
        NSDictionary *frameProperties = @{
                                          (__bridge NSString *)kCGImagePropertyGIFDictionary: @{
                                                (__bridge NSString *)kCGImagePropertyGIFDelayTime: @(frameDuration)
                                          }
                                        };

        NSMutableData *mutableData = [NSMutableData data];
        CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)mutableData, kUTTypeGIF, frameCount, NULL);

        NSDictionary *imageProperties = @{ (__bridge NSString *)kCGImagePropertyGIFDictionary: @{
                                                (__bridge NSString *)kCGImagePropertyGIFLoopCount: @(loopCount)
                                            }
                                         };
        CGImageDestinationSetProperties(destination, (__bridge CFDictionaryRef)imageProperties);
        
        for (size_t idx = 0; idx < images.count; idx++) {
            CGImageDestinationAddImage(destination, [[images objectAtIndex:idx] CGImage], (__bridge CFDictionaryRef)frameProperties);
        }
        
        BOOL success = CGImageDestinationFinalize(destination);
        CFRelease(destination);

        if (!success) {
            userInfo = @{
                         NSLocalizedDescriptionKey: NSLocalizedString(@"Could not finalize image destination", nil)
                        };

            goto _error;
        }

        return [NSData dataWithData:mutableData];
    }
    _error: {
        if (error) {
            *error = [[NSError alloc] initWithDomain:AnimatedGIFImageErrorDomain code:-1 userInfo:userInfo];
        }
        
        return nil;
    }
}

@implementation AnimatedGIFImageSerialization

+ (UIImage *)imageWithData:(NSData *)data
                     error:(NSError * __autoreleasing *)error
{
    return [self imageWithData:data scale:1.0f duration:0.0f error:error];
}

+ (UIImage *)imageWithData:(NSData *)data
                     scale:(CGFloat)scale
                  duration:(NSTimeInterval)duration
                     error:(NSError * __autoreleasing *)error
{
    return UIImageWithAnimatedGIFData(data, scale, duration, error);
}

#pragma mark -

+ (NSData *)animatedGIFDataWithImage:(UIImage *)image
                               error:(NSError * __autoreleasing *)error
{
    return [self animatedGIFDataWithImage:image duration:0.0f loopCount:0 error:error];
}

+ (NSData *)animatedGIFDataWithImage:(UIImage *)image
                            duration:(NSTimeInterval)duration
                           loopCount:(NSUInteger)loopCount
                               error:(NSError *__autoreleasing *)error
{
    return UIImageAnimatedGIFRepresentation(image, duration, loopCount, error);
}

@end

NS_ASSUME_NONNULL_END

#pragma mark -

#ifndef ANIMATED_GIF_NO_UIIMAGE_INITIALIZER_SWIZZLING
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

static inline void animated_gif_swizzleSelector(Class class, SEL originalSelector, SEL swizzledSelector) {
    Method originalMethod = class_getInstanceMethod(class, originalSelector);
    Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);
    if (class_addMethod(class, originalSelector, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod))) {
        class_replaceMethod(class, swizzledSelector, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, swizzledMethod);
    }
}

@interface UIImage (_AnimatedGIFImageSerialization)
@end

@implementation UIImage (_AnimatedGIFImageSerialization)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        @autoreleasepool {
            animated_gif_swizzleSelector(object_getClass((id)self), @selector(imageNamed:), @selector(animated_gif_imageNamed:));
            animated_gif_swizzleSelector(object_getClass((id)self), @selector(imageWithData:), @selector(animated_gif_imageWithData:));
            animated_gif_swizzleSelector(object_getClass((id)self), @selector(imageWithData:scale:), @selector(animated_gif_imageWithData:scale:));
            animated_gif_swizzleSelector(object_getClass((id)self), @selector(imageWithContentsOfFile:), @selector(animated_gif_imageWithContentsOfFile:));
            animated_gif_swizzleSelector(self, @selector(initWithContentsOfFile:), @selector(animated_gif_initWithContentsOfFile:));
            animated_gif_swizzleSelector(self, @selector(initWithData:), @selector(animated_gif_initWithData:));
            animated_gif_swizzleSelector(self, @selector(initWithData:scale:), @selector(animated_gif_initWithData:scale:));
        }
    });
}

#pragma mark -

+ (UIImage *)animated_gif_imageNamed:(NSString *)name __attribute__((objc_method_family(new))) {
    CGFloat scale = [[UIScreen mainScreen] scale];
    CGRect screenBounds = [[UIScreen mainScreen] bounds];
    
    NSString *ratioSuffix = @"";
    switch ((NSUInteger)screenBounds.size.height) {
        case AnimatedGifScreenType480h:
            ratioSuffix = AnimatedGifScreenTypeSuffix480h;
            break;
        case AnimatedGifScreenType568h:
            ratioSuffix = AnimatedGifScreenTypeSuffix568h;
            break;
        case AnimatedGifScreenType667h:
            ratioSuffix = AnimatedGifScreenTypeSuffix667h;
            break;
        case AnimatedGifScreenType736h:
            ratioSuffix = AnimatedGifScreenTypeSuffix736h;
            break;
    }

    NSString *scaleSuffix = @"";
    if (scale >= 3) {
        scaleSuffix = @"@3x";
    } else if (scale >= 2) {
        scaleSuffix = @"@2x";
    }
    
    NSString * _Nullable path = nil;
    if (!path) {
        // e.g. animated-568h@2x.gif
        NSString *nameWithRatioAndScale = [[[name stringByDeletingPathExtension] stringByAppendingString:ratioSuffix] stringByAppendingString:scaleSuffix];
        path = [[NSBundle mainBundle] pathForResource:nameWithRatioAndScale ofType:[name pathExtension]];
    }
    
    if (!path) {
        // e.g. animated@2x.gif
        NSString *nameWithRatio = [[[name stringByDeletingPathExtension] stringByAppendingString:scaleSuffix] stringByAppendingPathExtension:[name pathExtension]];
        path = [[NSBundle mainBundle] pathForResource:nameWithRatio ofType:[name pathExtension]];
    }
    
    if (!path) {
        // e.g. animated.gif
        path = [[NSBundle mainBundle] pathForResource:[name stringByDeletingPathExtension] ofType:[name pathExtension]];
    }
    
    if (path) {
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (AnimatedGifDataIsValid(data)) {
            return UIImageWithAnimatedGIFData(data);
        }
    }

    return [self animated_gif_imageNamed:name];
}

+ (UIImage *)animated_gif_imageWithContentsOfFile:(NSString *)path {
    if (path) {
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (AnimatedGifDataIsValid(data)) {
            if ([[path stringByDeletingPathExtension] hasSuffix:@"@3x"]) {
                return UIImageWithAnimatedGIFData(data, 3.0f, 0.0f, nil);
            } else if ([[path stringByDeletingPathExtension] hasSuffix:@"@2x"]) {
                return UIImageWithAnimatedGIFData(data, 2.0f, 0.0f, nil);
            } else {
                return UIImageWithAnimatedGIFData(data);
            }
        }
    }

    return [self animated_gif_imageWithContentsOfFile:path];
}

+ (UIImage *)animated_gif_imageWithData:(NSData *)data {
    if (AnimatedGifDataIsValid(data)) {
        return UIImageWithAnimatedGIFData(data);
    }

    return [self animated_gif_imageWithData:data];
}

+ (UIImage *)animated_gif_imageWithData:(NSData *)data
                                  scale:(CGFloat)scale {
    if (AnimatedGifDataIsValid(data)) {
        return UIImageWithAnimatedGIFData(data, scale, 0.0f, nil);
    }

    return [self animated_gif_imageWithData:data scale:scale];
}

#pragma mark -

- (id)animated_gif_initWithContentsOfFile:(NSString *)path __attribute__((objc_method_family(init))) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (AnimatedGifDataIsValid(data)) {
        if ([[path stringByDeletingPathExtension] hasSuffix:@"@3x"]) {
            return UIImageWithAnimatedGIFData(data, 3.0, 0.0f, nil);
        } else if ([[path stringByDeletingPathExtension] hasSuffix:@"@2x"]) {
            return UIImageWithAnimatedGIFData(data, 2.0, 0.0f, nil);
        } else {
            return UIImageWithAnimatedGIFData(data);
        }
    }

    return [self animated_gif_initWithContentsOfFile:path];
}

- (id)animated_gif_initWithData:(NSData *)data __attribute__((objc_method_family(init))) {
    if (AnimatedGifDataIsValid(data)) {
        return UIImageWithAnimatedGIFData(data);
    }

    return [self animated_gif_initWithData:data];
}

- (id)animated_gif_initWithData:(NSData *)data
                          scale:(CGFloat)scale __attribute__((objc_method_family(init)))
{
    if (AnimatedGifDataIsValid(data)) {
        return UIImageWithAnimatedGIFData(data, scale, 0.0f, nil);
    }

    return [self animated_gif_initWithData:data scale:scale];
}

@end

NS_ASSUME_NONNULL_END

#endif
