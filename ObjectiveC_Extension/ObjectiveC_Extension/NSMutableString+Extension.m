//
//  NSMutableString+Extension.m
//  ObjectiveC_Extension
//
//  Created by Vitor Marques de Miranda on 04/11/2017.
//  Copyright © 2017 VitorMM. All rights reserved.
//

#import "NSMutableString+Extension.h"
#import "NSString+Extension.h"

@implementation NSMutableString (VMMMutableString)

-(void)replaceOccurrencesOfString:(nonnull NSString *)target withString:(nonnull NSString *)replacement
{
    [self replaceOccurrencesOfString:target withString:replacement options:0 range:NSMakeRange(0, self.length)];
}

-(nonnull NSMutableString*)trim
{
    // We used to use the method below, but the method in use today is about 2 to 5 times faster
    
    //    while ([self hasPrefix:@" "] || [self hasPrefix:@"\n"] || [self hasPrefix:@"\t"])
    //        [self replaceCharactersInRange:NSMakeRange(0, 1) withString:@""];
    //    while ([self hasSuffix:@" "] || [self hasSuffix:@"\n"] || [self hasSuffix:@"\t"])
    //        [self replaceCharactersInRange:NSMakeRange(self.length-1, 1) withString:@""];
    
    @autoreleasepool
    {
        NSUInteger stringLength = self.length;
        if (stringLength == 0) return self;
        
        NSUInteger indexBegin = 0;
        unichar invalidCharacters[] = {' ', '\n', '\t', '\0'};
        int invalidCharactersSize = 4;
        
        unichar actualChar;
        int charIndex;
        BOOL invalid;
        while (indexBegin < stringLength) {
            invalid = false;
            actualChar = [self characterAtIndex:indexBegin];
            for (charIndex = 0; charIndex < invalidCharactersSize; charIndex++) {
                if (invalidCharacters[charIndex] == actualChar) invalid = true;
            }
            if (invalid) indexBegin++;
            else break;
        }
        if (indexBegin > 0) {
            [self replaceCharactersInRange:NSMakeRange(0, indexBegin) withString:@""];
        }
        if (indexBegin == stringLength) return self;
        
        
        stringLength = self.length;
        NSUInteger indexEnd = stringLength - 1;
        
        while (indexEnd >= 0) {
            invalid = false;
            actualChar = [self characterAtIndex:indexEnd];
            for (charIndex = 0; charIndex < invalidCharactersSize; charIndex++) {
                if (invalidCharacters[charIndex] == actualChar) invalid = true;
            }
            if (invalid) indexEnd--;
            else break;
        }
        if (stringLength - indexEnd - 1 > 0) {
            [self replaceCharactersInRange:NSMakeRange(indexEnd + 1, stringLength - indexEnd - 1) withString:@""];
        }
    }
    
    return self;
}

@end
