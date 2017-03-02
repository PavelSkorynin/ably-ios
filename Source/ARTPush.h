//
//  ARTPush.h
//  Ably
//
//  Created by Ricardo Pereira on 07/02/2017.
//  Copyright © 2017 Ably. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ARTTypes.h"

@class ARTRest;
@class ARTDeviceDetails;

@protocol ARTHTTPAuthenticatedExecutor;

// More context
typedef NSString ARTDeviceId;
typedef NSData ARTDeviceToken;
typedef NSString ARTUpdateToken;
typedef ARTJsonObject ARTPushRecipient;


#pragma mark ARTPushRegisterer interface

@protocol ARTPushRegistererDelegate

- (void)ablyPushActivateCallback:(nullable ARTErrorInfo *)error;
- (void)ablyPushDeactivateCallback:(nullable ARTErrorInfo *)error;

@optional

- (void)ablyPushUpdateFailedCallback:(nullable ARTErrorInfo *)error;

- (void)ablyPushCustomRegister:(nullable ARTErrorInfo *)error deviceDetails:(nullable ARTDeviceDetails *)deviceDetails callback:(void (^ _Nonnull)(ARTUpdateToken * _Nonnull, ARTErrorInfo * _Nullable))callback;
- (void)ablyPushCustomDeregister:(nullable ARTErrorInfo *)error deviceId:(nullable ARTDeviceId *)deviceId callback:(void (^ _Nullable)(ARTErrorInfo * _Nullable))callback;

@end


#pragma mark ARTPush type

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ARTDeviceIdKey;
extern NSString *const ARTDeviceUpdateTokenKey;
extern NSString *const ARTDeviceTokenKey;

@interface ARTPush : NSObject

@property (nonatomic, readonly) ARTDeviceDetails *device;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)init:(id<ARTHTTPAuthenticatedExecutor>)httpExecutor;

/// Publish a push notification.
- (void)publish:(ARTPushRecipient *)recipient jsonObject:(ARTJsonObject *)jsonObject;

#ifdef TARGET_OS_IOS
/// Push Registration token
+ (void)didRegisterForRemoteNotificationsWithDeviceToken:(nonnull NSData *)deviceToken rest:(ARTRest *)rest;
+ (void)didFailToRegisterForRemoteNotificationsWithError:(nonnull NSError *)error rest:(ARTRest *)rest;

/// Register a device, including the information necessary to deliver push notifications to it.
- (void)activate;

/// Unregister a device.
- (void)deactivate;
#endif

@end

NS_ASSUME_NONNULL_END