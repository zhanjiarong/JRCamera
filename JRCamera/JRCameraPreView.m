//
//  JRCameraPreView.m
//  MyCamera
//
//  Created by BoYun on 15/7/21.
//  Copyright (c) 2015年 Zhan. All rights reserved.
//

#import "JRCameraPreView.h"
#import <AVFoundation/AVFoundation.h>

@implementation JRCameraPreView

+ (Class)layerClass
{
    return [AVCaptureVideoPreviewLayer class];
}

- (AVCaptureSession *)session
{
    return [(AVCaptureVideoPreviewLayer *)[self layer] session];
}

- (void)setSession:(AVCaptureSession *)session
{
    [(AVCaptureVideoPreviewLayer *)[self layer] setSession:session];
}

@end
