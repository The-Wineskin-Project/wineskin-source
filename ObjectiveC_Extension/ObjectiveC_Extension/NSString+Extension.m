//
//  NSString+Extension.m
//  ObjectiveC_Extension
//
//  Created by Vitor Marques de Miranda on 22/02/17.
//  Copyright © 2017 Vitor Marques de Miranda. All rights reserved.
//

#import "NSString+Extension.h"

#import "NSData+Extension.h"
#import "NSTask+Extension.h"
#import "VMMAlert.h"
#import "NSFileManager+Extension.h"
#import "NSMutableString+Extension.h"

#import "VMMComputerInformation.h"
#import "VMMLocalizationUtility.h"

@implementation NSString (VMMString)

+(nonnull NSString*)stringWithCFTypeIDDescription:(CFTypeRef _Nonnull)cf_type {
    CFTypeID type_id = (CFTypeID) CFGetTypeID(cf_type);
    CFStringRef typeIdDescription = CFCopyTypeIDDescription(type_id);
    NSString* string = [self stringWithCFString:typeIdDescription];
    CFRelease(typeIdDescription);
    return [NSString stringWithFormat:@"<%@>",string];
}
+(nullable NSString*)stringWithCFString:(CFStringRef _Nonnull)cf_string {
    char * buffer;
    CFIndex len = CFStringGetLength(cf_string);
    buffer = (char *) malloc(sizeof(char) * len + 1);
    CFStringGetCString(cf_string, buffer, len + 1,
                       CFStringGetSystemEncoding());
    NSString* string = [NSString stringWithUTF8String:buffer];
    free(buffer);
    return string;
}
+(nonnull NSString*)stringWithCFNumber:(CFNumberRef _Nonnull)cf_number ofType:(CFNumberType)number_type {
    int number; 
    CFNumberGetValue(cf_number, number_type, &number);
    return [NSString stringWithFormat:@"%d",number];
}
+(nullable NSString*)stringWithCFType:(CFTypeRef _Nonnull)cf_type {
    CFTypeID type_id;
    
    type_id = (CFTypeID) CFGetTypeID(cf_type);
    if (type_id == CFStringGetTypeID())
    {
        return [self stringWithCFString:cf_type];
    }
    else if (type_id == CFNumberGetTypeID())
    {
        return [self stringWithCFNumber:cf_type ofType:kCFNumberIntType];
    }
    else if (type_id == CFDateGetTypeID())
    {
        // TODO: Not tested
        NSDate* date = (__bridge NSDate*)cf_type;
        return [date descriptionWithLocale:[NSLocale currentLocale]];
    }
    
    // TODO: The types below are still unsupported:
    //{CFArrayGetTypeID(),"CFArray"},
    //{CFBooleanGetTypeID(),"CFBoolean"},
    //{CFDataGetTypeID(),"CFData"},
    //{CFDictionaryGetTypeID(),"CFDictionary"},
    
    return nil;
}

-(NSRange)rangeOfUnescapedChar:(char)character
{
    return [self rangeOfUnescapedChar:character range:NSMakeRange(0, self.length)];
}
-(NSRange)rangeOfUnescapedChar:(char)character range:(NSRange)rangeOfReceiverToSearch
{
    NSString* characterString = [NSString stringWithFormat:@"%c",character];
    
    NSUInteger index = rangeOfReceiverToSearch.location;
    NSRange range = [self rangeOfString:characterString options:NSCaseInsensitiveSearch
                                  range:NSMakeRange(index, rangeOfReceiverToSearch.length - index)];
    while (range.location != NSNotFound) {
        BOOL isEscaped = false;
        NSUInteger escapeIndex = range.location-1;
        while (escapeIndex != -1 && [self characterAtIndex:escapeIndex] == '\\') {
            escapeIndex--;
            isEscaped = !isEscaped;
        }
        if (!isEscaped) {
            return range; // SUCCESS (found)
        }
        if (rangeOfReceiverToSearch.length == range.location + 1) return range; // FAILURE (last character reached)
        
        index = range.location + 1;
        range = [self rangeOfString:characterString options:NSCaseInsensitiveSearch
                              range:NSMakeRange(index, rangeOfReceiverToSearch.length - index)];
    }
    
    return range; // FAILURE (don't exist)
}

-(BOOL)contains:(nonnull NSString*)string
{
    return [self rangeOfString:string].location != NSNotFound;
}
-(BOOL)containsWord:(NSString*)word
{
    BOOL result;
    
    @autoreleasepool
    {
        NSArray* words = [self.lowercaseString componentsSeparatedByString:@" "];
        result = [words containsObject:word];
    }
    
    return result;
}
-(BOOL)containsOneOfSynonyms:(NSArray*)words
{
    for (NSString* word in words)
    {
        if ([self containsWord:word])
        {
            return YES;
        }
    }
    
    return NO;
}
-(BOOL)containsAbbreviation:(NSString*)string
{
    @autoreleasepool
    {
        NSString* abbreviation = string.lowercaseString;
        
        NSMutableArray* words = [[self.lowercaseString componentsSeparatedByString:@" "] mutableCopy];
        [words removeObject:@""];
        
        if (words.count < abbreviation.length)
        {
            return false;
        }
        
        int lettersSkipped;
        BOOL patternMatches = NO;
        BOOL letterMatches = NO;
        char letter;
        
        for (int wordIndex = 0; wordIndex <= words.count - abbreviation.length; wordIndex++)
        {
            letter = [abbreviation characterAtIndex:0];
            letterMatches = [words[wordIndex] characterAtIndex:0] == letter;
            
            if (letterMatches)
            {
                patternMatches = NO;
                lettersSkipped = 0;
                
                for (int letterIndex = 1; letterIndex < abbreviation.length; letterIndex++)
                {
                    letter = [abbreviation characterAtIndex:letterIndex];
                    letterMatches = [words[wordIndex+letterIndex+lettersSkipped] characterAtIndex:0] == letter;
                    
                    if (letterMatches && letterIndex == abbreviation.length - 1) patternMatches = YES;
                    
                    if (words.count == wordIndex + letterIndex + lettersSkipped + 1)
                    {
                        break;
                    }
                    
                    if (!letterMatches)
                    {
                        lettersSkipped++;
                        letterIndex--;
                    }
                }
                
                if (patternMatches) break;
            }
            
            if (patternMatches) break;
        }
        
        return patternMatches;
    }
}

-(BOOL)matchesWithRegex:(nonnull NSString*)regexString
{
    BOOL result;
    
    @autoreleasepool
    {
        NSPredicate* regex = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", regexString];
        result = [regex evaluateWithObject:self];
    }
    
    return result;
}
-(nonnull NSArray<NSString*>*)componentsMatchingWithRegex:(nonnull NSString*)regexString
{
    NSMutableArray* matches;
    
    if (IsClassNSRegularExpressionAvailable == false)
    {
        // TODO: Find a different way to replace NSRegularExpression... there must be a better way
        
        @autoreleasepool
        {
            NSString* uuid = [[NSUUID UUID] UUIDString];;
            NSString* pyFileName  = [NSString stringWithFormat:@"pythonRegex%@.py",uuid];
            NSString* datFileName = [NSString stringWithFormat:@"pythonFile%@.dat",uuid];
            
            NSString* pythonScriptPath = [NSString stringWithFormat:@"%@%@",NSTemporaryDirectory(),pyFileName ];
            NSString* stringFilePath   = [NSString stringWithFormat:@"%@%@",NSTemporaryDirectory(),datFileName];
            
            NSArray* pythonScriptContentsArray = @[@"import re",
                                                   @"import os",
                                                   @"dir_path = os.path.dirname(os.path.abspath(__file__))",
                                                   [NSString stringWithFormat:@"text_file = open(dir_path + \"/%@\", \"r\")",datFileName],
                                                   @"text = text_file.read()",
                                                   [NSString stringWithFormat:@"regex = re.compile(r\"(%@)\")",regexString],
                                                   @"matches = regex.finditer(text)",
                                                   @"for match in matches:",
                                                   @"    print match.group()"];
            NSString* pythonScriptContents = [pythonScriptContentsArray componentsJoinedByString:@"\n"];
            
            [self                 writeToFile:stringFilePath   atomically:YES encoding:NSASCIIStringEncoding];
            [pythonScriptContents writeToFile:pythonScriptPath atomically:YES encoding:NSASCIIStringEncoding];
            
            NSString* output = [NSTask runCommand:@[@"python", pythonScriptPath]];
            matches = [[output componentsSeparatedByString:@"\n"] mutableCopy];
            [matches removeObject:@""];
        }
        
        return matches;
    }
    
    @autoreleasepool
    {
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:regexString options:0 error:NULL];
        NSArray* rangeArray = [regex matchesInString:self options:0 range:NSMakeRange(0, self.length)];
        
        matches = [[NSMutableArray alloc] init];
        for (NSTextCheckingResult *match in rangeArray)
        {
            [matches addObject:[self substringWithRange:match.range]];
        }
    }
        
    return matches;
}

+(nonnull NSString*)humanReadableSizeForBytes:(long long int)bytes withDecimalMeasureSystem:(BOOL)measure
{
    NSString* result;
    
    @autoreleasepool
    {
        int degree = 0;
        int minorBytes = 0;
        int divisor = measure ? 1000 : 1024;
        
        while (bytes/divisor && degree < 8)
        {
            minorBytes=bytes%divisor;
            bytes/=divisor;
            degree++;
        }
        
        switch (degree)
        {
            case 0:  result = @"b";  break;
            case 1:  result = @"Kb"; break;
            case 2:  result = @"Mb"; break;
            case 3:  result = @"Gb"; break;
            case 4:  result = @"Tb"; break;
            case 5:  result = @"Pb"; break;
            case 6:  result = @"Eb"; break;
            case 7:  result = @"Zb"; break;
            default: result = @"Yb"; break;
        }
        
        minorBytes = ((minorBytes*1000)/divisor)/100;
        if (minorBytes > 0) result = [NSString stringWithFormat:@".%d%@",minorBytes,result];
        
        result = [NSString stringWithFormat:@"%lld%@",bytes,result];
    }
    
    return result;
}

-(nonnull NSString*)hexadecimalUTF8String
{
    NSString* hexStr;
    
    @autoreleasepool
    {
        const char* cString = [self cStringUsingEncoding:NSUTF8StringEncoding];
        hexStr = [NSString stringWithFormat:@"%@", [NSData dataWithBytes:cString length:strlen(cString)]];
        hexStr = [hexStr stringByRemovingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"<> "]];
    }
    
    return hexStr;
}
+(nullable NSString*)stringWithHexadecimalUTF8String:(nonnull NSString*)string
{
    NSMutableString* newString;
    
    @autoreleasepool
    {
        newString = [[NSMutableString alloc] init];
        NSScanner* scanner = [[NSScanner alloc] initWithString:string];
        unsigned value;
        while ([scanner scanHexInt:&value])
        {
            if (value==0) [newString appendString:@"\0"];
            else [newString appendFormat:@"%c",(char)(value & 0xFF)];
        }
    }
    
    return newString;
}

+(nonnull NSString*)stringByRemovingEvenCharsFromString:(nonnull NSString*)text
{
    NSMutableString* text2;
    
    @autoreleasepool
    {
        text2 = [NSMutableString stringWithString:@""];
        
        for (int x = 0; x < text.length; x = x+2)
        {
            [text2 appendString:[text substringWithRange:NSMakeRange(x,1)]];
        }
    }
    
    return text2;
}

-(NSRange)rangeAfterString:(nullable NSString*)before andBeforeString:(nullable NSString*)after
{
    NSRange result;
    
    @autoreleasepool
    {
        NSRange beforeRange = before ? [self rangeOfString:before] : NSMakeRange(0, 0);
        
        if (beforeRange.location == NSNotFound)
        {
            return NSMakeRange(NSNotFound, 0);
        }
        
        CGFloat afterBeforeRangeStart = beforeRange.location + beforeRange.length;
        NSRange afterBeforeRange = NSMakeRange(afterBeforeRangeStart, self.length - afterBeforeRangeStart);
        NSRange afterRange = after ? [self rangeOfString:after options:0 range:afterBeforeRange] : NSMakeRange(NSNotFound, 0);
        
        if (afterRange.location == NSNotFound)
        {
            return afterBeforeRange;
        }
        
        result = NSMakeRange(afterBeforeRangeStart, afterRange.location - afterBeforeRangeStart);
    }
    
    return result;
}
-(nullable NSString*)getFragmentAfter:(nullable NSString*)before andBefore:(nullable NSString*)after
{
    NSRange range = [self rangeAfterString:before andBeforeString:after];
    if (range.location == NSNotFound) return nil;
    return [self substringWithRange:range];
}

-(nullable NSNumber*)initialIntegerValue
{
    NSNumber* numberValue;
    
    @autoreleasepool
    {
        NSMutableString* originalString = [self mutableCopy];
        NSMutableString* newString = [NSMutableString stringWithString:@""];
        NSRange firstCharRange = NSMakeRange(0, 1);
        
        while (originalString.length > 0 && [originalString characterAtIndex:0] >= '0' && [originalString characterAtIndex:0] <= '9')
        {
            [newString appendString:[originalString substringWithRange:firstCharRange]];
            [originalString deleteCharactersInRange:firstCharRange];
        }
        
        if (newString.length > 0) numberValue = [[NSNumber alloc] initWithInt:newString.intValue];
    }
    
    return numberValue;
}

+(nullable NSString*)stringWithContentsOfFile:(nonnull NSString*)file
{
    if (![[NSFileManager defaultManager] regularFileExistsAtPath:file]) return nil;
    
    @autoreleasepool
    {
        for (NSNumber* encoding in @[@(NSUTF8StringEncoding),@(NSASCIIStringEncoding),@(NSISOLatin1StringEncoding)])
        {
            NSError* error;
            NSString* string = [self stringWithContentsOfFile:file encoding:encoding.unsignedIntegerValue error:&error];
            
            if (error == nil && string != nil)
            {
                return string;
            }
        }
    }
    
    return nil;
}
+(nullable NSString*)stringWithContentsOfFile:(nonnull NSString*)file encoding:(NSStringEncoding)enc
{
    if (![[NSFileManager defaultManager] regularFileExistsAtPath:file]) return nil;
    
    NSError* error;
    NSString* string = [self stringWithContentsOfFile:file encoding:enc error:&error];
    
    if (error != nil)
    {
        [VMMAlert showAlertOfType:VMMAlertTypeError withMessage:[NSString stringWithFormat:VMMLocalizedString(@"Error while reading file text: %@"), error.localizedDescription]];
    }
    
    return string;
}
+(void)stringWithContentsOfURL:(nonnull NSURL *)url encoding:(NSStringEncoding)enc timeoutInterval:(long long int)timeoutInterval withCompletionHandler:(void (^)(NSUInteger statusCode, NSString* string, NSError* error))completion
{
    @autoreleasepool
    {
        [NSData dataWithContentsOfURL:url timeoutInterval:timeoutInterval withCompletionHandler:
         ^(NSUInteger statusCode, NSData *data, NSError *error)
        {
            NSString* stringValue = (data != nil) ? [[NSString alloc] initWithData:data encoding:enc] : nil;

            if (completion != nil) {
                completion(statusCode, stringValue, error);
            }
        }];
    }
}

-(BOOL)writeToFile:(nonnull NSString*)path atomically:(BOOL)useAuxiliaryFile encoding:(NSStringEncoding)enc
{
    if (![[NSFileManager defaultManager] regularFileExistsAtPath:path])
    {
        [[NSFileManager defaultManager] createEmptyFileAtPath:path];
    }
    
    NSError* error;
    BOOL created = [self writeToFile:path atomically:useAuxiliaryFile encoding:enc error:&error];
    
    if (error != nil)
    {
        [VMMAlert showAlertOfType:VMMAlertTypeError withMessage:[NSString stringWithFormat:VMMLocalizedString(@"Error while writting file: %@"), error.localizedDescription]];
    }
    
    return created;
}

-(nonnull NSData*)dataWithBase64Encoding
{
    if (!IS_SYSTEM_MAC_OS_10_9_OR_SUPERIOR)
    {
        return [[NSData alloc] initWithBase64Encoding:self];
    }
    
    return [[NSData alloc] initWithBase64EncodedString:self options:0];
}

-(BOOL)isAValidURL
{
    BOOL isValid = true;
    
    @autoreleasepool
    {
        if (![self hasPrefix:@"http://"] && ![self hasPrefix:@"https://"] && ![self hasPrefix:@"ftp://"])
        {
            isValid = false;
        }
        
        if (isValid)
        {
            NSURL *candidateURL = [NSURL URLWithString:self];
            isValid = candidateURL && candidateURL.scheme && candidateURL.host;
        }
    }
    
    return isValid;
}

-(NSString*)stringByReplacingCharactersInSet:(NSCharacterSet *)characterset withString:(NSString *)string
{
    NSString *result = self;
    NSRange range = [result rangeOfCharacterFromSet:characterset];
    
    while (range.location != NSNotFound) {
        result = [result stringByReplacingCharactersInRange:range withString:string];
        range = [result rangeOfCharacterFromSet:characterset];
    }
    return result;
}
-(NSString*)stringByRemovingCharactersInSet:(NSCharacterSet *)characterset
{
    return [self stringByReplacingCharactersInSet:characterset withString:@""];
}

@end
