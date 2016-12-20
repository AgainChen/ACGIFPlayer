//
//  ACGIFPlayer.h
//  IdealSeeAR
//
//  Created by Again on 8/16/16.
//  Copyright © 2016 Again. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
typedef NS_ENUM(NSInteger, ACGIFPlayerStatus) {
    ACGIFPlayerStatusFailed,
    ACGIFPlayerStatusLoading,
    ACGIFPlayerStatusReadyToPlay,
    ACGIFPlayerStatusPlaying,
    ACGIFPlayerStatusPause
};

typedef NS_ENUM(NSUInteger, ACGIFPlayerPerformance) {
    ACGIFPlayerPerformanceLowCPU,
    ACGIFPlayerPerformanceLowMemory
};

@protocol ACGIFPlayerDelegate <NSObject>

- (void) acGifLoadStatus:(ACGIFPlayerStatus)status content:(id)content;

- (void) acGifFrameOutputSampleBuffer:(CVPixelBufferRef)sampleBuffer frameIndex:(NSInteger)index;

@end

@interface ACGIFPlayer : NSObject
@property(nonatomic,weak) id <ACGIFPlayerDelegate> delegate;
@property(nonatomic,assign,readonly) ACGIFPlayerStatus playerStatus;
@property (nonatomic, assign, readonly) NSUInteger currentFrameIndex;

- (id) initWithGifFilePath:(NSString *)path;

- (void) loadGifFile:(NSString *)filePath preformanceCategory:(ACGIFPlayerPerformance)preformanceCategory;

- (void) play;

- (void) pause;

- (void) stop;

- (CGSize) acgifImageSize;

@end


@interface FLWeakProxy : NSProxy

+ (instancetype)weakProxyForObject:(id)targetObject;

@end
