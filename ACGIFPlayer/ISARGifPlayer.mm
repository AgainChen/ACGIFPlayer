//
//  ISARGifPlayer.m
//  IdealSeeAR
//
//  Created by again on 15/5/18.
//
//

#import "ISARGifPlayer.h"
//#include "CMVideoSampling.h"
//#include "CVTextureCache.h"
//#import <OpenGLES/ES2/glext.h>

#import "ACGIFPlayer.h"

#define MEGABYTE (1024 * 1024)

@interface ISARGifPlayer () <ACGIFPlayerDelegate>
{

    CMVideoSampling		_cmVideoSampling;

    BOOL _readyPlay;
    
    int _playerUUID;
    
    BOOL _isDeinit;
    
    GifReadyToPlayCallBack readyToPlayCallBack;
}

@property(nonatomic,strong) ACGIFPlayer *acGIFPlayer;
@property(nonatomic,copy) NSString *gifURL;
@end


@implementation ISARGifPlayer
- (id)init
{
    self = [super init];
    if (self) {
        //CMVideoSampling_Initialize(&_cmVideoSampling);
        self.acGIFPlayer = [[ACGIFPlayer alloc] init];
        self.acGIFPlayer.delegate = self;
    }
    return self;
}


- (void)setReadyCallBack:(GifReadyToPlayCallBack )callBack uuid:(int)uuid
{
    _playerUUID = uuid;
    readyToPlayCallBack = callBack;
}



- (BOOL)loadGifFile:(NSString *)filePath
{
    self.gifURL = filePath;
    [self.acGIFPlayer loadGifFile:filePath preformanceCategory:ACGIFPlayerPerformanceLowCPU];
    return YES;
}


- (void) acGifLoadStatus:(ACGIFPlayerStatus)status content:(id)content
{
    switch (status) {
        case ACGIFPlayerStatusFailed:
            NSLog(@"error = %@",(NSError *)content);
            break;
        case ACGIFPlayerStatusLoading:
            break;
        case ACGIFPlayerStatusReadyToPlay:
            _readyPlay = YES;
            readyToPlayCallBack(_playerUUID);
            [self.acGIFPlayer play];
            break;
        case ACGIFPlayerStatusPlaying:
            break;
        case ACGIFPlayerStatusPause:
            break;
        default:
            break;
    }
}

- (void) acGifFrameOutputSampleBuffer:(CVPixelBufferRef)sampleBuffer frameIndex:(NSInteger)index
{
    [self setupTexture:sampleBuffer];
}


- (void)startAnimating
{
    if (self.acGIFPlayer.playerStatus>ACGIFPlayerStatusLoading) {
        
        [self.acGIFPlayer play];
    }
}

- (void)stopAnimating
{
    if (self.acGIFPlayer.playerStatus>ACGIFPlayerStatusLoading) {
        [self.acGIFPlayer pause];
    }
}

- (intptr_t)GetTextureID
{
    if(!_readyPlay)
        return 0;
    
    return CMVideoSampling_LastSampledTexture(&_cmVideoSampling);
}


- (void)setupTexture:(CVPixelBufferRef )gifPixelBuffer {
    
//    if (gifPixelBuffer!=NULL) {
//        dispatch_async(dispatch_get_main_queue(), ^{
//            size_t w, h;
//            if(!_isDeinit)
//            {
//                CMVideoSampling_cvPixelBuffer(&_cmVideoSampling, gifPixelBuffer, &w, &h);
//            }
//        });
//    }
}

- (void)cleanUpTextures
{
    //CMVideoSampling_Uninitialize(&_cmVideoSampling);
}

- (void)deinitPlayer
{
    _isDeinit = YES;
    [self cleanUpTextures];
    self.acGIFPlayer = nil;
    self.gifURL = nil;
}

- (void)dealloc
{
    HSLog(@"gif player dealloc");
    
}
@end
