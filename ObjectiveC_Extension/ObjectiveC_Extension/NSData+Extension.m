//
//  NSData+Extension.m
//  ObjectiveC_Extension
//
//  Created by Vitor Marques de Miranda on 22/02/17.
//  Copyright © 2017 Vitor Marques de Miranda. All rights reserved.
//

#import "NSData+Extension.h"
#import "VMMAlert.h"
#import "NSMutableString+Extension.h"
#import "VMMComputerInformation.h"
#import "VMMLocalizationUtility.h"

@implementation NSData (VMMData)

+(void)dataWithContentsOfURL:(nonnull NSURL *)url timeoutInterval:(long long int)timeoutInterval withCompletionHandler:(void (^_Nullable)(NSUInteger statusCode, NSData* _Nullable data, NSError* _Nullable error))completion
{
    NSData* stringData;
    
    @autoreleasepool
    {
        NSURLRequest* request = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                             timeoutInterval:timeoutInterval];
        
        NSError *error = nil;
        NSHTTPURLResponse *response = nil;
        stringData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
        
        if (completion != nil) {
            completion(response.statusCode, stringData, error);
        }
    }
}
-(nonnull NSString*)base64EncodedString
{
    if (![self respondsToSelector:@selector(base64EncodedStringWithOptions:)])
    {
        return [self base64Encoding];
    }
    
    return [self base64EncodedStringWithOptions:0];
}

@end
