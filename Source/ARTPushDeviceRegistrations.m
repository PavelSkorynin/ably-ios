//
//  ARTPushDeviceRegistrations.m
//  Ably
//
//  Created by Ricardo Pereira on 20/02/2017.
//  Copyright © 2017 Ably. All rights reserved.
//

#import "ARTPushDeviceRegistrations.h"
#import "ARTHttp.h"
#import "ARTLog.h"
#import "ARTPaginatedResult+Private.h"
#import "ARTDeviceDetails.h"
#import "ARTDevicePushDetails.h"
#import "ARTClientOptions.h"
#import "ARTEncoder.h"

@implementation ARTPushDeviceRegistrations {
    id<ARTHTTPAuthenticatedExecutor> _httpExecutor;
    __weak ARTLog* _logger;
}

- (instancetype)init:(id<ARTHTTPAuthenticatedExecutor>)httpExecutor {
    if (self = [super init]) {
        _httpExecutor = httpExecutor;
        _logger = [httpExecutor logger];
    }
    return self;
}

- (void)save:(ARTDeviceDetails *)deviceDetails callback:(void (^)(ARTErrorInfo *error))callback {
    if (!deviceDetails.updateToken) {
        [_logger error:@"%@: update token is missing", NSStringFromClass(self.class)];
        return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[[NSURL URLWithString:@"/push/deviceRegistrations"] URLByAppendingPathComponent:deviceDetails.id]];
    NSData *tokenData = [deviceDetails.updateToken dataUsingEncoding:NSUTF8StringEncoding];
    NSString *tokenBase64 = [tokenData base64EncodedStringWithOptions:0];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", tokenBase64] forHTTPHeaderField:@"Authorization"];
    request.HTTPMethod = @"PUT";
    request.HTTPBody = [[_httpExecutor defaultEncoder] encodeDeviceDetails:deviceDetails];
    [request setValue:[[_httpExecutor defaultEncoder] mimeType] forHTTPHeaderField:@"Content-Type"];

    [_logger debug:__FILE__ line:__LINE__ message:@"save device with request %@", request];
    [_httpExecutor executeRequest:request completion:^(NSHTTPURLResponse *response, NSData *data, NSError *error) {
        if (response.statusCode == 200 /*OK*/) {
            [_logger debug:__FILE__ line:__LINE__ message:@"%@: save device successfully", NSStringFromClass(self.class)];
            ARTDeviceDetails *deviceDetails = [[_httpExecutor defaultEncoder] decodeDeviceDetails:data error:nil];
            deviceDetails.updateToken = deviceDetails.updateToken;
        }
        else if (error) {
            [_logger error:@"%@: save device failed (%@)", NSStringFromClass(self.class), error.localizedDescription];
        }
        else {
            [_logger error:@"%@: save device failed with status code %ld", NSStringFromClass(self.class), (long)response.statusCode];
        }
    }];
}

- (void)list:(NSDictionary<NSString *, NSString *> *)params callback:(void (^)(ARTPaginatedResult<ARTDeviceDetails *> *result, ARTErrorInfo *error))callback {
    NSURLComponents *components = [[NSURLComponents alloc] initWithURL:[NSURL URLWithString:@"/push/deviceRegistrations"] resolvingAgainstBaseURL:NO];
    components.queryItems = [params asURLQueryItems];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[components URL]];
    request.HTTPMethod = @"GET";

    ARTPaginatedResultResponseProcessor responseProcessor = ^(NSHTTPURLResponse *response, NSData *data) {
        return [[_httpExecutor defaultEncoder] decodeDevicesDetails:data error:nil];
    };
    [ARTPaginatedResult executePaginated:_httpExecutor withRequest:request andResponseProcessor:responseProcessor callback:callback];
}

- (void)remove:(NSString *)deviceId callback:(void (^)(ARTErrorInfo *error))callback {
    [self removeWhere:@{@"deviceId": deviceId} callback:callback];
}

- (void)removeWhere:(NSDictionary<NSString *, NSString *> *)params callback:(void (^)(ARTErrorInfo *error))callback {
    NSURLComponents *components = [[NSURLComponents alloc] initWithURL:[NSURL URLWithString:@"/push/deviceRegistrations"] resolvingAgainstBaseURL:NO];
    components.queryItems = [params asURLQueryItems];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[components URL]];
    request.HTTPMethod = @"DELETE";

    [_logger debug:__FILE__ line:__LINE__ message:@"remove device with request %@", request];
    [_httpExecutor executeRequest:request withAuthOption:ARTAuthenticationOn completion:^(NSHTTPURLResponse *response, NSData *data, NSError *error) {
        if (response.statusCode == 200 /*OK*/) {
            [_logger debug:__FILE__ line:__LINE__ message:@"%@: remove device successfully", NSStringFromClass(self.class)];
        }
        else if (error) {
            [_logger error:@"%@: remove device failed (%@)", NSStringFromClass(self.class), error.localizedDescription];
        }
        else {
            [_logger error:@"%@: remove device failed with status code %ld", NSStringFromClass(self.class), (long)response.statusCode];
        }
    }];
}

@end
