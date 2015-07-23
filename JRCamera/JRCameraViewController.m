//
//  JRCameraViewController.m
//  MyCamera
//
//  Created by BoYun on 15/7/21.
//  Copyright (c) 2015年 Zhan. All rights reserved.
//

#import "JRCameraViewController.h"

#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>

#import "JRCameraPreView.h"

#define JR_OS_VERSION [[[UIDevice currentDevice] systemVersion] floatValue]

static void * CapturingStillImageContext = &CapturingStillImageContext;
static void * RecordingContext = &RecordingContext;
static void * SessionRunningAndDeviceAuthorizedContext = &SessionRunningAndDeviceAuthorizedContext;

@interface JRCameraViewController () <AVCaptureFileOutputRecordingDelegate>

@property (weak, nonatomic) IBOutlet JRCameraPreView *cameraPreview;
@property (weak, nonatomic) IBOutlet UIButton *recordButton;
@property (weak, nonatomic) IBOutlet UIButton *stillButton;
@property (weak, nonatomic) IBOutlet UIButton *cameraButton;

- (IBAction)toggleMovieRecording:(id)sender;
- (IBAction)snapStillImage:(id)sender;
- (IBAction)changeCamera:(id)sender;
- (IBAction)focusAndExposeTap:(id)sender;

@property (nonatomic, strong) dispatch_queue_t sessionQueue;
@property (nonatomic, weak) AVCaptureSession *session;
@property (nonatomic, strong) AVCaptureDeviceInput *videoDeviceInput;
@property (nonatomic, strong) AVCaptureMovieFileOutput *movieFileOutput;
@property (nonatomic, strong) AVCaptureStillImageOutput *stillImageOutput;

@property (nonatomic, assign) UIBackgroundTaskIdentifier backgroundRecordingID;
@property (nonatomic, getter=isDeviceAuthorized) BOOL deviceAuthorized;
@property (nonatomic, readonly, getter=isSessionRunningAndDeviceAuthorized) BOOL sessionRunningAndDeviceAuthorized;
@property (nonatomic, assign) BOOL lockInterfaceRotation;
@property (nonatomic, strong) id runtimeErrorHandlingObserver;

@end

@implementation JRCameraViewController

- (BOOL)isSessionRunningAndDeviceAuthorized
{
    return [[self session] isRunning] && [self isDeviceAuthorized];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self checkDeviceAuthorizationStatus];
    
    [self setupCamera];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    dispatch_async([self sessionQueue], ^{
        [self addObserver:self forKeyPath:@"sessionRunningAndDeviceAuthorized" options:NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew context:SessionRunningAndDeviceAuthorizedContext];
        [self addObserver:self forKeyPath:@"stillImageOutput.capturingStillImage" options:NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew context:CapturingStillImageContext];
        [self addObserver:self forKeyPath:@"movieFileOutput.recording" options:NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew context:RecordingContext];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(subjectAreaDidChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:[[self videoDeviceInput] device]];
        
        // addObserverForName: object: queue: usingBlock:返回一个监听者对象，要保存这个对象以便后面移除它
        __weak __typeof(self) weakSelf = self;
        [self setRuntimeErrorHandlingObserver:[[NSNotificationCenter defaultCenter] addObserverForName:AVCaptureSessionRuntimeErrorNotification object:[self session] queue:nil usingBlock:^(NSNotification *note) {
            __strong __typeof(weakSelf) strongSelf = weakSelf;
            dispatch_async([strongSelf sessionQueue], ^{
                [[strongSelf session] startRunning];
                [[strongSelf recordButton] setTitle:@"录制" forState:UIControlStateNormal];
            });
        }]];
        [[self session] startRunning];
    });
}

- (void)viewDidDisappear:(BOOL)animated
{
    dispatch_async([self sessionQueue], ^{
        [[self session] stopRunning];
        
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:[[self videoDeviceInput] device]];
        [[NSNotificationCenter defaultCenter] removeObserver:[self runtimeErrorHandlingObserver]];
        
        [self removeObserver:self forKeyPath:@"sessionRunningAndDeviceAuthorized" context:SessionRunningAndDeviceAuthorizedContext];
        [self removeObserver:self forKeyPath:@"stillImageOutput.capturingStillImage" context:CapturingStillImageContext];
        [self removeObserver:self forKeyPath:@"movieFileOutput.recording" context:RecordingContext];
    });
}

- (BOOL)prefersStatusBarHidden
{
    return  YES;
}

- (BOOL)shouldAutorotate
{
    return ![self lockInterfaceRotation];
}

- (NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAll;
}

/** 
 iOS 2.0 ~ 8.0
 屏幕将要旋转屏幕旋转时要改变AVCaptureVideoPreviewLayer的方向，否则不适应屏幕会出现大黑边。
 */
- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    // 屏幕旋转时要改变AVCaptureVideoPreviewLayer的方向，否则不适应屏幕会出现大黑边。
    [[(AVCaptureVideoPreviewLayer *)[[self cameraPreview] layer] connection] setVideoOrientation:(AVCaptureVideoOrientation)toInterfaceOrientation];
}

/** 
 iOS 8.0 + 
 屏幕将要旋转屏幕旋转时要改变AVCaptureVideoPreviewLayer的方向，否则不适应屏幕会出现大黑边。
 */
- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    // 注意以下两个枚举定义的LandscapeLeft和LandscapeRight名称相反，但是实际值有代表的屏幕方向是相同的，以 home键 所在方向为标准
    
    /* UIDeviceOrientation
    UIDeviceOrientationLandscapeLeft = 3       // Device oriented horizontally, home button on the right
    UIDeviceOrientationLandscapeRight = 4      // Device oriented horizontally, home button on the left
     */
    
    /* AVCaptureVideoOrientation
     AVCaptureVideoOrientationLandscapeRight = 3
     Indicates that video should be oriented horizontally, home button on the right.
     AVCaptureVideoOrientationLandscapeLeft = 4
     Indicates that video should be oriented horizontally, home button on the left.
     */
    
    UIDeviceOrientation orientation = [[UIDevice currentDevice] orientation];
    
    [[(AVCaptureVideoPreviewLayer *)[[self cameraPreview] layer] connection] setVideoOrientation:(AVCaptureVideoOrientation)orientation];
}

#pragma mark 配置Session

/** 创建相机所需对象 */
- (void)setupCamera
{
    // 1.创建AVCaptureSession对象
    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    
    [self setSession:session];
    // 2.将session关联到AVCaptureVideoPreviewLayer
    [[self cameraPreview] setSession:session];
    
    dispatch_queue_t sessionQueue = dispatch_queue_create("session queue", DISPATCH_QUEUE_SERIAL);
    [self setSessionQueue:sessionQueue];
    
    dispatch_async(sessionQueue, ^{
        [self setBackgroundRecordingID:UIBackgroundTaskInvalid];
        
        NSError *error = nil;
        // 3.创建视频设备对象，后置摄像头
        AVCaptureDevice *videoDevice = [[self class] deviceWithMediaType:AVMediaTypeVideo preferringPosition:AVCaptureDevicePositionBack];
        // 4.创建视频输入对象
        AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
        
        if (error)
        {
            NSLog(@"%@", error);
        }
        
        if ([session canAddInput:videoDeviceInput])
        {
            // 5.将视频输入对象加入到AVCaptureSession
            [session addInput:videoDeviceInput];
            [self setVideoDeviceInput:videoDeviceInput];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                // 6.在主线程中设置AVCaptureVideoPreviewLayer方向
                [[(AVCaptureVideoPreviewLayer *)[[self cameraPreview] layer] connection] setVideoOrientation:(AVCaptureVideoOrientation)[[UIDevice currentDevice] orientation]];
            });
        }
        
        // -----------------------------------------------------------
        
        // 7.创建音频设备对象
        AVCaptureDevice *autioDevice = [[AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio] firstObject];
        // 8.创建音频输入对象
        AVCaptureDeviceInput *audioDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:autioDevice error:&error];
        
        if (error)
        {
            NSLog(@"%@", error);
        }
        
        if ([session canAddInput:audioDeviceInput])
        {
            // 9.将音频输入对象加入到AVCaptureSession
            [session addInput:audioDeviceInput];
        }
        
        // -----------------------------------------------------------
        
        // 10.创建视频文件输出对象
        AVCaptureMovieFileOutput *movieFileOutput = [[AVCaptureMovieFileOutput alloc] init];
        if ([session canAddOutput:movieFileOutput])
        {
            // 11.将视频文件输出对象加入到AVCaptureSession
            [session addOutput:movieFileOutput];
            
            // 12.关联到CaptureSession的CaptureDeviceInput和CaptureDeviceOutput的连接
            AVCaptureConnection *connection = [movieFileOutput connectionWithMediaType:AVMediaTypeVideo];
            if ([connection isVideoStabilizationSupported])
            {
                if (JR_OS_VERSION >= 8.0)
                {
                    [connection setPreferredVideoStabilizationMode:AVCaptureVideoStabilizationModeAuto];
                }
                else
                {
                    [connection setEnablesVideoStabilizationWhenAvailable:YES];
                }
                
            }
            [self setMovieFileOutput:movieFileOutput];
        }
        
        // -----------------------------------------------------------
        
        // 13.创建带元数据的高质量照片输出对象
        AVCaptureStillImageOutput *stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
        if ([session canAddOutput:stillImageOutput]) {
            // 14.先指定输出格式，再加入到AVCaptureSession中
            [stillImageOutput setOutputSettings:@{AVVideoCodecKey : AVVideoCodecJPEG}];
            [session addOutput:stillImageOutput];
            [self setStillImageOutput:stillImageOutput];
        }
        
    });
}

/** 检查权限 */
- (void)checkDeviceAuthorizationStatus
{
    NSString *mediaType = AVMediaTypeVideo;
    [AVCaptureDevice requestAccessForMediaType:mediaType completionHandler:^(BOOL granted) {
        if (granted) {
            [self setDeviceAuthorized:YES];
        } else {
            NSLog(@"未获得访问权限！");
            [self setDeviceAuthorized:NO];
        }
    }];
}

/** 拍照时的动画 */
- (void)runStillImageCaptureAnimation
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [[[self cameraPreview] layer] setOpacity:0.0f];
        [UIView animateWithDuration:.25f animations:^{
            [[[self cameraPreview] layer] setOpacity:1.0f];
        }];
    });
}

/** 获取摄像头设备 */
+ (AVCaptureDevice *)deviceWithMediaType:(NSString *)mediaType preferringPosition:(AVCaptureDevicePosition)position
{
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:mediaType];
    AVCaptureDevice *captureDevice = [devices firstObject]; // 这里为后置摄像头
    
    for (AVCaptureDevice *device in devices)
    {
        if ([device position] == position)
        {
            captureDevice = device;
            break;
        }
    }
    
    return captureDevice;
}

#pragma mark Device Configuration

- (void)focusWithMode:(AVCaptureFocusMode)focusMode exposeWithMode:(AVCaptureExposureMode)exposureMode atDevicePoint:(CGPoint)point monitorSubjectAreaChange:(BOOL)monitorSubjectAreaChange
{
    dispatch_async([self sessionQueue], ^{
        AVCaptureDevice *device = [[self videoDeviceInput] device];
        NSError *error = nil;
        // 当试图修改硬件相关的属性时，必须调用lockForConfiguration:锁住配置锁，保证只有当前程序修改它，返回YES说明锁成功，就可以修改配置了。
        if ([device lockForConfiguration:&error])
        {
            if ([device isFocusPointOfInterestSupported])
            {
                // 设置聚焦模式
                [device setFocusMode:focusMode];
                // 设置聚集点
                [device setFocusPointOfInterest:point];
            }
            if ([device isExposurePointOfInterestSupported])
            {
                // 设置曝光模式
                [device setExposureMode:exposureMode];
                // 设置曝光点
                [device setExposurePointOfInterest:point];
            }
            [device setSubjectAreaChangeMonitoringEnabled:monitorSubjectAreaChange];
            // 当修改完配置时需要解开配置锁
            [device unlockForConfiguration];
        }
        else
        {
            NSLog(@"%@", error);
        }
    });
}

// 闪光模式：关闭、打开、自动
+ (void)setFlashMode:(AVCaptureFlashMode)flashMode forDevice:(AVCaptureDevice *)device
{
    if ([device hasFlash] && [device isFlashModeSupported:flashMode])
    {
        NSError *error = nil;
        if ([device lockForConfiguration:&error])
        {
            [device setFlashMode:flashMode];
            
            [device unlockForConfiguration];
        }
        else
        {
            NSLog(@"%@", error);
        }
    }
}

#pragma mark Actions

- (IBAction)toggleMovieRecording:(id)sender
{
    [[self recordButton] setEnabled:NO];
    
    dispatch_async([self sessionQueue], ^{
        if (![[self movieFileOutput] isRecording])
        {
            [self setLockInterfaceRotation:YES];
            
            if ([[UIDevice currentDevice] isMultitaskingSupported]) {
                // Setup background task. This is needed because the captureOutput:didFinishRecordingToOutputFileAtURL: callback is not received until AVCam returns to the foreground unless you request background execution time. This also ensures that there will be time to write the file to the assets library when AVCam is backgrounded. To conclude this background execution, -endBackgroundTask is called in -recorder:recordingDidFinishToOutputFileURL:error: after the recorded file has been saved.
                [self setBackgroundRecordingID:[[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:nil]];
            }
            
            // 设置视频输出的方向为AVCaptureVideoPreviewLayer的方向
            [[[self movieFileOutput] connectionWithMediaType:AVMediaTypeVideo] setVideoOrientation:[[(AVCaptureVideoPreviewLayer *)[[self cameraPreview] layer] connection] videoOrientation]];
            
            // 录像时关闭闪光灯
            [[self class] setFlashMode:AVCaptureFlashModeOff forDevice:[[self videoDeviceInput] device]];
            
            // 保存在一个临时文件中
            // /private/var/mobile/Containers/Data/Application/05E066E4-760C-4EE8-A649-0EA58284CD46/tmp/movie.mov
            NSString *outputFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"movie" stringByAppendingPathExtension:@"mov"]];
            
            // 开始录像到临时文件 并 设置代理，必须用fileURLWithPath:方法，因为是文件路径
            [[self movieFileOutput] startRecordingToOutputFileURL:[NSURL fileURLWithPath:outputFilePath] recordingDelegate:self];
        }
        else
        {
            [[self movieFileOutput] stopRecording];
        }
    });
}

- (IBAction)snapStillImage:(id)sender
{
    dispatch_async([self sessionQueue], ^{
        // 捕获照片之前设置照片的方向为AVCaptureVideoPreviewLayer的方向
        [[[self stillImageOutput] connectionWithMediaType:AVMediaTypeVideo] setVideoOrientation:[[(AVCaptureVideoPreviewLayer *)[[self cameraPreview] layer] connection] videoOrientation]];
        
        // 设置闪光为自动模式
        [[self class] setFlashMode:AVCaptureFlashModeAuto forDevice:[[self videoDeviceInput] device]];
        
        // 捕获照片
        [[self stillImageOutput] captureStillImageAsynchronouslyFromConnection:[[self stillImageOutput] connectionWithMediaType:AVMediaTypeVideo] completionHandler:^(CMSampleBufferRef imageDataSampleBuffer, NSError *error) {
            
            if (imageDataSampleBuffer)
            {
                NSData *imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageDataSampleBuffer];
                UIImage *image = [[UIImage alloc] initWithData:imageData];
                [[[ALAssetsLibrary alloc] init] writeImageToSavedPhotosAlbum:[image CGImage] orientation:(ALAssetOrientation)[image imageOrientation] completionBlock:nil];
            }
        }];
    });
}

- (IBAction)changeCamera:(id)sender
{
    [[self cameraButton] setEnabled:NO];
    [[self recordButton] setEnabled:NO];
    [[self stillButton] setEnabled:NO];
    
    dispatch_async([self sessionQueue], ^{
        AVCaptureDevice *currentVideoDevice = [[self videoDeviceInput] device];
        AVCaptureDevicePosition preferredPosition = AVCaptureDevicePositionUnspecified;
        AVCaptureDevicePosition currentPosition = [currentVideoDevice position];
        
        switch (currentPosition)
        {
            case AVCaptureDevicePositionUnspecified:
                preferredPosition = AVCaptureDevicePositionBack;
                break;
            case AVCaptureDevicePositionBack:
                preferredPosition = AVCaptureDevicePositionFront;
                break;
            case AVCaptureDevicePositionFront:
                preferredPosition = AVCaptureDevicePositionBack;
                break;
        }
        // 重新获取视频设备对象
        AVCaptureDevice *videoDevice = [[self class] deviceWithMediaType:AVMediaTypeVideo preferringPosition:preferredPosition];
        // 创建视频输入对象
        AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:nil];
        
        // 调用beginConfiguration，就可以添加或移除AVCaptureDeviceInput和AVCaptureDeviceOutput，改变sessionPreset，或配置Input和Output的属性
        // 只有调用了commitConfiguration才会真正的做以上改变
        [[self session] beginConfiguration]; // 开始配置
        
        // 移除之前的视频输入对象
        [[self session] removeInput:[self videoDeviceInput]];
        if ([[self session] canAddInput:videoDeviceInput])
        {
            // 移除先前对上一个摄像头视频输入对象的通知监听
            [[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:currentVideoDevice];
            
            [[self class] setFlashMode:AVCaptureFlashModeAuto forDevice:videoDevice];
            
            // 监听切换后的视频输入对象的通知
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(subjectAreaDidChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:videoDevice];
            
            // 将新的视频输入对象加入取session中
            [[self session] addInput:videoDeviceInput];
            // 保存该对象
            [self setVideoDeviceInput:videoDeviceInput];
        }
        else
        {
            // 如果切换后的视频输入对象不能添加到session中，把之前的重新添加到session
            [[self session] addInput:[self videoDeviceInput]];
        }
        
        [[self session] commitConfiguration]; // 提交配置
        
        // 切换完成后在主线程修改UI
        dispatch_async(dispatch_get_main_queue(), ^{
            [[self cameraButton] setEnabled:YES];
            [[self recordButton] setEnabled:YES];
            [[self stillButton] setEnabled:YES];
        });
        
    });
}

- (IBAction)focusAndExposeTap:(UIGestureRecognizer *)gestureRecognizer
{
    CGPoint devicePoint = [(AVCaptureVideoPreviewLayer *)[[self cameraPreview] layer] captureDevicePointOfInterestForPoint:[gestureRecognizer locationInView:[gestureRecognizer view]]];
    
    [self focusWithMode:AVCaptureFocusModeAutoFocus exposeWithMode:AVCaptureExposureModeAutoExpose atDevicePoint:devicePoint monitorSubjectAreaChange:YES];
}

#pragma mark 通知处理

- (void)subjectAreaDidChange:(NSNotification *)notification
{
    CGPoint devicePoint = CGPointMake(.5, .5);
    [self focusWithMode:AVCaptureFocusModeAutoFocus exposeWithMode:AVCaptureExposureModeAutoExpose atDevicePoint:devicePoint monitorSubjectAreaChange:NO];
}


#pragma mark File Output Delegate

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)error
{
    if (error)
        NSLog(@"%@", error);
    
    [self setLockInterfaceRotation:NO];
    
    // 获取后台任务的标识符，如果分配了标识符则下面的判断就会成立从而结束后台任务
    UIBackgroundTaskIdentifier backgroundRecordingID = [self backgroundRecordingID];
    [self setBackgroundRecordingID:UIBackgroundTaskInvalid];
    
    // 把outputFileURL的视频存到相册
    [[[ALAssetsLibrary alloc] init] writeVideoAtPathToSavedPhotosAlbum:outputFileURL completionBlock:^(NSURL *assetURL, NSError *error) {
        if (error)
            NSLog(@"%@", error);
        
        // 删除outputFileURL表示的路径的视频
        [[NSFileManager defaultManager] removeItemAtURL:outputFileURL error:nil];
        
        if (backgroundRecordingID != UIBackgroundTaskInvalid) {
            [[UIApplication sharedApplication] endBackgroundTask:backgroundRecordingID];
        }
    }];
}

#pragma mark KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == CapturingStillImageContext)
    {
        BOOL isCapturingStillImage = [change[NSKeyValueChangeNewKey] boolValue];
        if (isCapturingStillImage)
        {
            [self runStillImageCaptureAnimation];
        }
    }
    else if (context == RecordingContext)
    {
        BOOL isRecording = [change[NSKeyValueChangeNewKey] boolValue];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (isRecording)
            {
                [[self cameraButton] setEnabled:NO];
                [[self recordButton] setTitle:@"停止" forState:UIControlStateNormal];
                [[self recordButton] setEnabled:YES];
            }
            else
            {
                [[self cameraButton] setEnabled:YES];
                [[self recordButton] setTitle:@"录像" forState:UIControlStateNormal];
                [[self recordButton] setEnabled:YES];
            }
        });
    }
    else if (context == SessionRunningAndDeviceAuthorizedContext)
    {
        BOOL isRunningAndDeviceAuthorized = [change[NSKeyValueChangeNewKey] boolValue];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (isRunningAndDeviceAuthorized)
            {
                [[self cameraButton] setEnabled:YES];
                [[self recordButton] setEnabled:YES];
                [[self stillButton] setEnabled:YES];
            }
            else
            {
                [[self cameraButton] setEnabled:NO];
                [[self recordButton] setEnabled:NO];
                [[self stillButton] setEnabled:NO];
            }
        });
    }
    else
    {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}


#pragma mark -

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
