//
//  JRCameraPreView.h
//  MyCamera
//
//  Created by BoYun on 15/7/21.
//  Copyright (c) 2015年 Zhan. All rights reserved.
//

#import <UIKit/UIKit.h>

@class AVCaptureSession;

@interface JRCameraPreView : UIView

@property (nonatomic, weak) AVCaptureSession *session;

@end
