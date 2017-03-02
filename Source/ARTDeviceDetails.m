//
//  ARTDeviceDetails.m
//  Ably
//
//  Created by Ricardo Pereira on 07/02/2017.
//  Copyright © 2017 Ably. All rights reserved.
//

#import "ARTDeviceDetails.h"
#import "ARTDevicePushDetails.h"

NSString *const ARTDevicePlatform = @"ios";

#if TARGET_OS_IOS
#import <UIKit/UIKit.h>
NSString *const ARTDeviceFormFactor = @"phone";
#elif TARGET_OS_TV
NSString *const ARTDeviceFormFactor = @"tv";
#elif TARGET_OS_WATCH
NSString *const ARTDeviceFormFactor = @"watch";
#elif TARGET_OS_SIMULATOR
NSString *const ARTDeviceFormFactor = @"simulator";
#elif TARGET_OS_MAC
NSString *const ARTDeviceFormFactor = @"desktop";
#else
NSString *const ARTDeviceFormFactor = @"embedded";
#endif

@implementation ARTDeviceDetails

- (instancetype)initWithId:(ARTDeviceId *)deviceId {
    if (self = [super init]) {
        _id = deviceId;
        _push = [[ARTDevicePushDetails alloc] init];
    }
    return self;
}

- (NSString *)platform {
    return ARTDevicePlatform;
}

- (NSString *)formFactor {
    switch (UI_USER_INTERFACE_IDIOM()) {
        case UIUserInterfaceIdiomPad:
            return @"tablet";
        case UIUserInterfaceIdiomCarPlay:
            return @"car";
        default:
            return ARTDeviceFormFactor;
    }
}

@end