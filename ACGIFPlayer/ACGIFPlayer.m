//
//  ACGIFPlayer.m
//  IdealSeeAR
//
//  Created by Again on 8/16/16.
//  Copyright © 2016 Again. All rights reserved.
//

#import "ACGIFPlayer.h"
#import <ImageIO/ImageIO.h>
#import <MobileCoreServices/MobileCoreServices.h>

static int const preloadFrameCount = 5;

@interface ACGIFPlayer ()
{
    CGImageSourceRef            _gifImageSource;
    NSInteger                        _loopCount;
    NSUInteger                      _frameCount;
    NSUInteger                   _loopCountdown;
    ACGIFPlayerPerformance _preformanceCategory;
    UIImage                   *_firstFrameImage;
    NSTimeInterval                 _accumulator;
    CGSize                           _imageSize;
    dispatch_queue_t               _decodeQueue;
}
@property (nonatomic, strong) NSMutableArray *imageArray;
@property (nonatomic, strong) NSMutableArray *delayTimesArray;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, strong, readonly) NSMutableIndexSet *cachedFrames;
@property (nonatomic, strong, readonly) NSMutableIndexSet *requestedFrames;
@end


@implementation ACGIFPlayer

- (id) initWithGifFilePath:(NSString *)path
{
    self = [super init];
    if (self) {
        [self loadGifFile:path];
    }
    return self;
}

- (void) loadGifFile:(NSString *)filePath
{
    [self loadGifFile:filePath preformanceCategory:ACGIFPlayerPerformanceLowCPU];
}

- (void) loadGifFile:(NSString *)filePath preformanceCategory:(ACGIFPlayerPerformance)preformanceCategory
{
    _playerStatus = ACGIFPlayerStatusLoading;
    if (_delegate && [_delegate respondsToSelector:@selector(acGifLoadStatus:content:)]) {
        [_delegate acGifLoadStatus:_playerStatus content:nil];
    }
    _preformanceCategory = preformanceCategory;
    _cachedFrames = [[NSMutableIndexSet alloc] init];
    _requestedFrames = [[NSMutableIndexSet alloc] init];
    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        if (_delegate && [_delegate respondsToSelector:@selector(acGifLoadStatus:content:)]) {
            [_delegate acGifLoadStatus:ACGIFPlayerStatusFailed content:[NSError errorWithDomain:[NSString stringWithFormat:@"Not found file :%@",filePath] code:-1 userInfo:nil]];
        }
        return;
    }
    
    NSData *gifImageData = [NSData dataWithContentsOfFile:filePath];
    _gifImageSource = CGImageSourceCreateWithData((__bridge CFDataRef)gifImageData, (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceShouldCache: @NO});
    if (!_gifImageSource) {
        if (_delegate && [_delegate respondsToSelector:@selector(acGifLoadStatus:content:)]) {
            [_delegate acGifLoadStatus:ACGIFPlayerStatusFailed content:[NSError errorWithDomain:@"Failed to create gif imageSource." code:-2 userInfo:nil]];
        }
        return;
    }
    
    CFStringRef imageSourceContainerType = CGImageSourceGetType(_gifImageSource);
    if (!UTTypeConformsTo(imageSourceContainerType,kUTTypeGIF)) {
        if (_delegate && [_delegate respondsToSelector:@selector(acGifLoadStatus:content:)]) {
            [_delegate acGifLoadStatus:ACGIFPlayerStatusFailed content:[NSError errorWithDomain:@"Source type is not gif format." code:-3 userInfo:nil]];
        }
        return;
    }
    
    NSDictionary *imageProperties = (NSDictionary *)CFBridgingRelease(CGImageSourceCopyProperties(_gifImageSource, NULL));
    _loopCount = [[[imageProperties objectForKey:(__bridge id)kCGImagePropertyGIFDictionary] objectForKey:(__bridge id)kCGImagePropertyGIFLoopCount] unsignedIntegerValue];
    if (_loopCount>0) {
        _loopCountdown = _loopCount;
    }else{
        _loopCountdown = NSIntegerMax;
    }
    
    if([imageProperties objectForKey:@"{GIF}"])
    {
        NSDictionary *gifDic = [imageProperties objectForKey:@"{GIF}"];
        if ([gifDic objectForKey:@"LoopCount"]) {
            _loopCountdown = [[gifDic objectForKey:@"LoopCount"] intValue];
        }else{
            _loopCountdown = 1;
        }
    }
    
    size_t imageCount = CGImageSourceGetCount(_gifImageSource);
    _frameCount = imageCount;
    if (imageCount==0) {
        if (_delegate && [_delegate respondsToSelector:@selector(acGifLoadStatus:content:)]) {
            [_delegate acGifLoadStatus:ACGIFPlayerStatusFailed content:[NSError errorWithDomain:@"Unkonw Error." code:-3 userInfo:nil]];
        }
        return;
    }else if (imageCount==1)
    {
        //Only one image.
    }
    
    self.delayTimesArray =[[NSMutableArray alloc] initWithCapacity:_frameCount];
    self.imageArray = [[NSMutableArray alloc] init];
    if (!_decodeQueue) {
        _decodeQueue = dispatch_queue_create("com.againchen.gifdecode", NULL);
    }
    
    dispatch_async(_decodeQueue, ^{
       [self preloadGIFImages];
    });
}


#pragma mark-
#pragma mark Decode and Cache

/**
 *  预加载GIF图片
 */
- (void) preloadGIFImages
{
    int preloadCount = (int)MIN(self.frameCacheSizeCurrent, _frameCount);
    
    for (int i=0; i<_frameCount; i++) {
        
        NSTimeInterval kDelayTimeIntervalDefault = 0.1;
        NSDictionary *frameProperties = (NSDictionary *)CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(_gifImageSource, i, NULL));
        NSDictionary *framePropertiesGIF = [frameProperties objectForKey:(__bridge id)kCGImagePropertyGIFDictionary];
        NSNumber *delayTime = [framePropertiesGIF objectForKey:(__bridge id)kCGImagePropertyGIFUnclampedDelayTime];
        if (!delayTime) {
            NSNumber *delayTime2 = [framePropertiesGIF objectForKey:(__bridge id)kCGImagePropertyGIFDelayTime];
            if (delayTime2) {
                kDelayTimeIntervalDefault =[delayTime2 floatValue];
            }
        }else
        {
            kDelayTimeIntervalDefault = [delayTime floatValue];
        }
        
        if (kDelayTimeIntervalDefault < 0.021f)
        {
            kDelayTimeIntervalDefault = 0.100f;
        }
        [_delayTimesArray addObject:@(kDelayTimeIntervalDefault)];
        
        if (i<preloadCount) {
            CGImageRef frameImageRef = CGImageSourceCreateImageAtIndex(_gifImageSource, i, NULL);
            if(frameImageRef)
            {
                _imageSize = CGSizeMake(CGImageGetWidth(frameImageRef), CGImageGetWidth(frameImageRef));
                
                CVPixelBufferRef image = [self pixelBufferFromCGImage:frameImageRef];
                if (image) {
                    [_imageArray addObject:(__bridge_transfer id)image];
                    [_cachedFrames addIndex:i];
                }
                
                if(_firstFrameImage == nil)
                {
                    if ((_imageSize.width*_imageSize.height*4*_frameCount)/(1024*1024) > 60) {
                        _preformanceCategory = ACGIFPlayerPerformanceLowMemory;
                    }
                    _firstFrameImage = [UIImage imageWithCGImage:frameImageRef];
                }
                CFRelease(frameImageRef);
            }else
            {
                [_imageArray addObject:[NSNull null]];
            }
            
            if (i==preloadCount-1) {
                _playerStatus = ACGIFPlayerStatusReadyToPlay;
                if (_delegate && [_delegate respondsToSelector:@selector(acGifLoadStatus:content:)]) {
                    [_delegate acGifLoadStatus:ACGIFPlayerStatusReadyToPlay content:_firstFrameImage];
                }
            }
        }else
        {
            [_imageArray addObject:[NSNull null]];
        }
    }
}

/**
 *  解码GIF中index位置的图像并转成CVPixelBuffer 格式
 *
 *  @param frameIndex
 *
 *  @return 返回CVPixelBuffer 数据
 */
- (CVPixelBufferRef) decodeGIFImageAtIndex:(NSInteger)frameIndex
{
    CGImageRef frameImageRef = CGImageSourceCreateImageAtIndex(_gifImageSource, frameIndex, NULL);
    
    if (!frameImageRef) {
        return nil;
    }
    
    CVPixelBufferRef image = [self pixelBufferFromCGImage:frameImageRef];
    
    CFRelease(frameImageRef);
    
    return image;
}

/**
 *  添加帧到缓存中
 *
 *  @param frameIndexesToAddToCache 需要缓存的帧的集合
 */
- (void)addFramesToCache:(NSIndexSet *)frameIndexesToAddToCache
{
    NSRange firstRange = NSMakeRange(_currentFrameIndex, _frameCount - _currentFrameIndex);
    NSRange secondRange = NSMakeRange(0, _currentFrameIndex);
    if (firstRange.length + secondRange.length != _frameCount) {
        NSLog(@"Two-part frame cache range doesn't equal full range.");
    }
    [self.requestedFrames addIndexes:frameIndexesToAddToCache];
    __weak ACGIFPlayer *weakSelf = self;
    dispatch_async(_decodeQueue, ^{
        void (^frameRangeBlock)(NSRange, BOOL *) = ^(NSRange range, BOOL *stop) {
            for (NSUInteger i = range.location; i < NSMaxRange(range); i++) {
                CVPixelBufferRef image = [self decodeGIFImageAtIndex:i];
                if (image && weakSelf) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [weakSelf.imageArray replaceObjectAtIndex:i withObject:(__bridge_transfer id)image];
                        [weakSelf.cachedFrames addIndex:i];
                        [weakSelf.requestedFrames removeIndex:i];
                    });
                }
            }
        };
        [frameIndexesToAddToCache enumerateRangesInRange:firstRange options:0 usingBlock:frameRangeBlock];
        [frameIndexesToAddToCache enumerateRangesInRange:secondRange options:0 usingBlock:frameRangeBlock];
    });
}

/**
 *  清除过多的缓存如果需要
 */
- (void)purgeFrameCacheIfNeeded
{
    if (_preformanceCategory == ACGIFPlayerPerformanceLowMemory && [self.cachedFrames count] > self.frameCacheSizeCurrent) {
        NSMutableIndexSet *indexesToPurge = [self.cachedFrames mutableCopy];
        [indexesToPurge removeIndexes:[self frameIndexesToCache]];
        [indexesToPurge enumerateRangesUsingBlock:^(NSRange range, BOOL *stop) {
            for (NSUInteger i = range.location; i < NSMaxRange(range); i++) {
                [self.cachedFrames removeIndex:i];
                [self.imageArray replaceObjectAtIndex:i withObject:[NSNull null]];
            }
        }];
    }
}

/**
 *  获取某帧的图像并向后缓存
 *
 *  @param index 帧索引
 *
 *  @return 某帧的数据
 */
- (id)imageLazilyCachedAtIndex:(NSUInteger)index
{
    if ([self.cachedFrames count] < _frameCount) {
        NSMutableIndexSet *frameIndexesToAddToCacheMutable = [self frameIndexesToCache];
        [frameIndexesToAddToCacheMutable removeIndexes:self.cachedFrames];
        [frameIndexesToAddToCacheMutable removeIndexes:self.requestedFrames];
        NSIndexSet *frameIndexesToAddToCache = [frameIndexesToAddToCacheMutable copy];
        if ([frameIndexesToAddToCache count] > 0) {
            [self addFramesToCache:frameIndexesToAddToCache];
        }
    }
    
    id image = [self.imageArray objectAtIndex:self.currentFrameIndex];
    
    [self purgeFrameCacheIfNeeded];
    
    return image;
}

/**
 *  计算需要缓存的帧的集合
 *
 *  @return 帧的集合
 */

- (NSMutableIndexSet *)frameIndexesToCache
{
    NSMutableIndexSet *indexesToCache;
    /* 如果是低CPU模式，就把所有的GIF帧都加入缓存 */
    if (_preformanceCategory == ACGIFPlayerPerformanceLowCPU) {
        indexesToCache = [[NSMutableIndexSet alloc] initWithIndexesInRange:NSMakeRange(0, _frameCount)];
    }else
    {
        indexesToCache = [[NSMutableIndexSet alloc] init];
        NSUInteger firstLength = MIN(self.frameCacheSizeCurrent, _frameCount - _currentFrameIndex);
        NSRange firstRange = NSMakeRange(_currentFrameIndex, firstLength);
        [indexesToCache addIndexesInRange:firstRange];
        NSUInteger secondLength = self.frameCacheSizeCurrent - firstLength;
        if (secondLength > 0) {
            NSRange secondRange = NSMakeRange(0, secondLength);
            [indexesToCache addIndexesInRange:secondRange];
        }
        if ([indexesToCache count] != self.frameCacheSizeCurrent) {
            NSLog(@"Number of frames to cache doesn't equal expected cache size.");
        }
    }
    
    return indexesToCache;
}

#pragma mark -
#pragma mark GIF Interface

- (CGSize) acgifImageSize
{
    return _imageSize;
}

- (void) play
{
    if (!self.displayLink) {
        FLWeakProxy *weakProxy = [FLWeakProxy weakProxyForObject:self];
        self.displayLink = [CADisplayLink displayLinkWithTarget:weakProxy selector:@selector(displayDidRefresh:)];
        [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    }
    self.displayLink.frameInterval = 2;
    self.displayLink.paused = NO;
    _playerStatus = ACGIFPlayerStatusPlaying;
    if (_delegate && [_delegate respondsToSelector:@selector(acGifLoadStatus:content:)]) {
        [_delegate acGifLoadStatus:_playerStatus content:nil];
    }
}

- (void) pause
{
    if(self.displayLink)
    {
        self.displayLink.paused = YES;
        _playerStatus = ACGIFPlayerStatusPause;
        if (_delegate && [_delegate respondsToSelector:@selector(acGifLoadStatus:content:)]) {
            [_delegate acGifLoadStatus:_playerStatus content:nil];
        }
    }
}

- (void) stop
{
    if(self.displayLink)
    {
        _playerStatus = ACGIFPlayerStatusPause;
        self.displayLink.paused = YES;
    }
}

- (void)displayDidRefresh:(CADisplayLink *)displayLink
{
    if (_playerStatus==ACGIFPlayerStatusPlaying) {
        _accumulator += displayLink.duration * displayLink.frameInterval;
        if (_currentFrameIndex < _delayTimesArray.count && _accumulator>=[_delayTimesArray[_currentFrameIndex] floatValue]) {
            _accumulator -= [_delayTimesArray[_currentFrameIndex] floatValue];
            
            if(_currentFrameIndex<_imageArray.count)
            {
                id image = [self imageLazilyCachedAtIndex:self.currentFrameIndex];
                
                if (![image isKindOfClass:[NSNull class]]) {
                    if (_delegate && [_delegate respondsToSelector:@selector(acGifFrameOutputSampleBuffer:frameIndex:)]) {
                        [_delegate acGifFrameOutputSampleBuffer:(__bridge CVPixelBufferRef)image frameIndex:_currentFrameIndex];
                    }
                }
                
                if(_currentFrameIndex+1 >=_imageArray.count &&  _imageArray.count<_frameCount)
                {
                    return;
                }
                _currentFrameIndex++;
                if (_currentFrameIndex >= _imageArray.count) {
                    _loopCountdown--;
                    if (_loopCountdown==0) {
                        [self pause];
                        return;
                    }
                    _currentFrameIndex = 0;
                }
            }
        }
    }
}

- (void)deinitPlayer
{
    [_displayLink invalidate];
    if (_gifImageSource) {
        CFRelease(_gifImageSource);
    }
    
    if(self.imageArray)
    {
        [self.imageArray removeAllObjects];
        self.imageArray = nil;
    }

}

- (void)dealloc
{
    if (_gifImageSource) {
        CFRelease(_gifImageSource);
    }
}

- (NSUInteger)frameCacheSizeCurrent
{
    NSUInteger frameCacheSizeCurrent = 4;

    return frameCacheSizeCurrent;
}

/**
 *  CGImage图像格式转CVPixelBuffer格式
 *
 *  @param image CGImage
 *
 *  @return CVPixelBuffer
 */

- (CVPixelBufferRef)pixelBufferFromCGImage:(CGImageRef)image
{
    NSDictionary *IOSurfaceProperties =@{(__bridge NSString *)kCVPixelBufferMetalCompatibilityKey :[NSNumber numberWithBool:YES]};
    CGSize frameSize = CGSizeMake(CGImageGetWidth(image), CGImageGetHeight(image));
    NSDictionary *options = @{
                              (__bridge NSString *)kCVPixelBufferCGImageCompatibilityKey: @(YES),
                              (__bridge NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey: @(YES),
                              (__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey : IOSurfaceProperties};
    CVPixelBufferRef pixelBuffer;
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, frameSize.width,
                                          frameSize.height,  kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef) options,
                                          &pixelBuffer);
    if (status != kCVReturnSuccess) {
        return NULL;
    }
    
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    void *data = CVPixelBufferGetBaseAddress(pixelBuffer);
    CGColorSpaceRef rgbColorSpace = CGImageGetColorSpace(image);
    CGContextRef context = CGBitmapContextCreate(data, frameSize.width, frameSize.height,
                                                 8, CVPixelBufferGetBytesPerRow(pixelBuffer), rgbColorSpace,
                                                 kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGContextTranslateCTM(context, frameSize.width, 0);
    CGContextScaleCTM(context, -1, 1);
    CGContextDrawImage(context, CGRectMake(0, 0, CGImageGetWidth(image),
                                           CGImageGetHeight(image)), image);
    CGContextRelease(context);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    
    return pixelBuffer;
}


@end



#pragma mark - FLWeakProxy

@interface FLWeakProxy ()

@property (nonatomic, weak) id target;

@end


@implementation FLWeakProxy

#pragma mark Life Cycle

+ (instancetype)weakProxyForObject:(id)targetObject
{
    FLWeakProxy *weakProxy = [FLWeakProxy alloc];
    weakProxy.target = targetObject;
    return weakProxy;
}


#pragma mark Forwarding Messages

- (id)forwardingTargetForSelector:(SEL)selector
{
    return _target;
}


#pragma mark - NSWeakProxy Method Overrides
#pragma mark Handling Unimplemented Methods

- (void)forwardInvocation:(NSInvocation *)invocation
{
    void *nullPointer = NULL;
    [invocation setReturnValue:&nullPointer];
}


- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector
{
    return [NSObject instanceMethodSignatureForSelector:@selector(init)];
}


@end
