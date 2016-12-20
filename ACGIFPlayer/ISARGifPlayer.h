//
//  ISARGifPlayer.h
//  IdealSeeAR
//
//  Created by again on 15/5/18.
//
//

#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <GLKit/GLKit.h>
#import <UIKit/UIKit.h>

typedef void (*GifReadyToPlayCallBack)(int uuid);

@interface ISARGifPlayer : NSObject
- (BOOL)loadGifFile:(NSString *)filePath;
- (void)startAnimating;
- (void)stopAnimating;
- (void)deinitPlayer;
- (intptr_t)GetTextureID;
- (void)setReadyCallBack:(GifReadyToPlayCallBack )callBack uuid:(int)uuid;
@end
