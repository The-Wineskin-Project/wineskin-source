//
//  NSBundle+Extension.h
//  ObjectiveC_Extension
//
//  Created by Vitor Marques de Miranda on 25/11/2017.
//  Copyright © 2017 VitorMM. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface NSBundle (VMMBundle)

-(nonnull NSUserDefaults*)userDefaults;

-(nonnull NSString*)bundleName;
-(nullable NSImage*)bundleIcon;

@end
