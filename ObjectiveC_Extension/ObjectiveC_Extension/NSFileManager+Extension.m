//
//  NSFileManager+Extension.m
//  ObjectiveC_Extension
//
//  Created by Vitor Marques de Miranda on 22/02/17.
//  Copyright © 2017 Vitor Marques de Miranda. All rights reserved.
//

#import "NSFileManager+Extension.h"

#import "VMMAlert.h"
#import "NSArray+Extension.h"
#import "NSData+Extension.h"
#import "NSTask+Extension.h"
#import "NSString+Extension.h"
#import "NSThread+Extension.h"

#import "VMMComputerInformation.h"
#import "VMMLocalizationUtility.h"

@implementation NSFileManager (VMMFileManager)

-(BOOL)createSymbolicLinkAtPath:(nonnull NSString *)path withDestinationPath:(nonnull NSString *)destPath
{
    NSError* error;
    BOOL created = [self createSymbolicLinkAtPath:path withDestinationPath:destPath error:&error];
    
    if (error != nil)
    {
        [VMMAlert showAlertOfType:VMMAlertTypeError withMessage:[NSString stringWithFormat:VMMLocalizedString(@"Error while creating symbolic link: %@"), error.localizedDescription]];
    }
    
    return created;
}
-(BOOL)createDirectoryAtPath:(nonnull NSString*)path withIntermediateDirectories:(BOOL)interDirs
{
    NSError* error;
    BOOL created = [self createDirectoryAtPath:path withIntermediateDirectories:interDirs attributes:nil error:&error];
    
    if (error != nil)
    {
        [VMMAlert showAlertOfType:VMMAlertTypeError withMessage:[NSString stringWithFormat:VMMLocalizedString(@"Error while creating folder: %@"), error.localizedDescription]];
    }
    
    return created;
}
-(BOOL)createEmptyFileAtPath:(nonnull NSString*)path
{
    return [self createFileAtPath:path contents:nil attributes:nil];
}

-(BOOL)moveItemAtPath:(nonnull NSString*)path toPath:(nonnull NSString*)destination
{
    NSError* error;
    BOOL created = [self moveItemAtPath:path toPath:destination error:&error];
    
    if (error != nil)
    {
        [VMMAlert showAlertOfType:VMMAlertTypeError
            withMessage:[NSString stringWithFormat:VMMLocalizedString(@"Error while moving file: %@"), error.localizedDescription]];
    }
    
    return created;
}
-(BOOL)copyItemAtPath:(nonnull NSString*)path toPath:(nonnull NSString*)destination
{
    NSError* error;
    BOOL created = [self copyItemAtPath:path toPath:destination error:&error];
    
    if (error != nil)
    {
        [VMMAlert showAlertOfType:VMMAlertTypeError withMessage:[NSString stringWithFormat:VMMLocalizedString(@"Error while copying file: %@"), error.localizedDescription]];
    }
    
    return created;
}
-(BOOL)removeItemAtPath:(nonnull NSString*)path
{
    if ([self fileExistsAtPath:path] == false) return YES;
    
    NSError* error;
    BOOL created = [self removeItemAtPath:path error:&error];
    
    if (error != nil)
    {
        [VMMAlert showAlertOfType:VMMAlertTypeError withMessage:[NSString stringWithFormat:VMMLocalizedString(@"Error while removing file: %@"), error.localizedDescription]];
    }
    
    return created;
}
-(BOOL)directoryExistsAtPath:(nonnull NSString*)path
{
    BOOL isDir = NO;
    return [self fileExistsAtPath:path isDirectory:&isDir] && isDir;
}
-(BOOL)regularFileExistsAtPath:(nonnull NSString*)path
{
    BOOL isDir = NO;
    return [self fileExistsAtPath:path isDirectory:&isDir] && !isDir;
}
-(nullable NSArray<NSString*>*)contentsOfDirectoryAtPath:(nonnull NSString*)path
{
    if (![self fileExistsAtPath:path])
    {
        [VMMAlert showAlertOfType:VMMAlertTypeError withMessage:[NSString stringWithFormat:VMMLocalizedString(@"Error while listing folder contents: %@ doesn't exist."), path.lastPathComponent]];
        return @[];
    }
    
    if (![self directoryExistsAtPath:path])
    {
        [VMMAlert showAlertOfType:VMMAlertTypeError withMessage:[NSString stringWithFormat:VMMLocalizedString(@"Error while listing folder contents: %@ is not a folder."), path.lastPathComponent]];
        return @[];
    }
    
    NSError* error;
    NSArray* created = [self contentsOfDirectoryAtPath:path error:&error];
    
    if (error != nil)
    {
        [VMMAlert showAlertOfType:VMMAlertTypeError withMessage:[NSString stringWithFormat:VMMLocalizedString(@"Error while listing folder contents: %@"), error.localizedDescription]];
        return @[];
    }
    
    NSMutableArray* createdMutable = [created mutableCopy];
    [createdMutable removeObject:@".DS_Store"];
    
    return createdMutable;
}
-(nullable NSArray<NSString*>*)subpathsAtPath:(nonnull NSString *)path ofFilesNamed:(nonnull NSString*)fileName
{
    @autoreleasepool
    {
        return [[[[NSTask runProgram:@"find" withFlags:@[path,@"-name",fileName]] componentsSeparatedByString:@"\n"]
                    filter:^BOOL(NSString* object) { return ![object hasPrefix:@"find: "]; }]
                       map:^id(NSString* object)   { return  [object stringByReplacingOccurrencesOfString:@"//" withString:@"/"];}];
    }
}
-(nullable NSString*)destinationOfSymbolicLinkAtPath:(nonnull NSString *)path
{
    NSError* error;
    NSString* destination = [self destinationOfSymbolicLinkAtPath:path error:&error];
    
    if (error != nil)
    {
        [VMMAlert showAlertOfType:VMMAlertTypeError withMessage:[NSString stringWithFormat:VMMLocalizedString(@"Error while retrieving symbolic link destination: %@"),error.localizedDescription]];
    }
    
    return destination;
}

-(unsigned long long int)sizeOfRegularFileAtPath:(nonnull NSString*)path
{
    unsigned long long int result = 0;
    
    @autoreleasepool
    {
        NSDictionary *fileDictionary = [self attributesOfItemAtPath:path error:nil];
        if (fileDictionary != nil) result = [fileDictionary[NSFileSize] unsignedLongLongValue];
    }
    
    return result;
}
-(unsigned long long int)sizeOfDirectoryAtPath:(nonnull NSString*)path
{
    unsigned long long int fileSize = 0;
    
    @autoreleasepool
    {
        NSArray *filesArray = [[NSFileManager defaultManager] subpathsOfDirectoryAtPath:path error:nil];
        
        for (NSString* file in filesArray)
        {
            NSString* filePath = [path stringByAppendingPathComponent:file];
            
            if (![self destinationOfSymbolicLinkAtPath:filePath error:nil])
            {
                fileSize += [self sizeOfRegularFileAtPath:filePath];
            }
        }
    }
    
    return fileSize;
}

-(nullable NSString*)checksum:(NSChecksumType)checksum ofFileAtPath:(nonnull NSString*)file
{
    NSString* result;
    
    @autoreleasepool
    {
        NSString* algorithm;
        
        switch (checksum)
        {
            case NSChecksumTypeGOSTMac:     algorithm = @"-gost-mac";    break;
            case NSChecksumTypeStreebog512: algorithm = @"-streebog512"; break;
            case NSChecksumTypeStreebog256: algorithm = @"-streebog256"; break;
            case NSChecksumTypeGOST94:      algorithm = @"-md_gost94";   break;
            case NSChecksumTypeMD4:         algorithm = @"-md4";         break;
            case NSChecksumTypeMD5:         algorithm = @"-md5";         break;
            case NSChecksumTypeRIPEMD160:   algorithm = @"-ripemd160";   break;
            case NSChecksumTypeSHA:         algorithm = @"-sha";         break;
            case NSChecksumTypeSHA1:        algorithm = @"-sha1";        break;
            case NSChecksumTypeSHA224:      algorithm = @"-sha224";      break;
            case NSChecksumTypeSHA256:      algorithm = @"-sha256";      break;
            case NSChecksumTypeSHA384:      algorithm = @"-sha384";      break;
            case NSChecksumTypeSHA512:      algorithm = @"-sha512";      break;
            case NSChecksumTypeWrirlpool:   algorithm = @"-whirlpool";   break;
            default: return nil;
        }
        
        NSString* output = [NSTask runCommand:@[@"openssl", @"dgst", algorithm, file]];
        if (output == nil) return nil;
        
        NSRange lastSpaceRange = [output rangeOfString:@" " options:NSBackwardsSearch];
        if (lastSpaceRange.location == NSNotFound) return nil;
        
        CGFloat checkSumWithSkipLineStartLocation = lastSpaceRange.location + lastSpaceRange.length;
        NSRange checkSumWithSkipLineStartRange = NSMakeRange(checkSumWithSkipLineStartLocation, output.length - checkSumWithSkipLineStartLocation);
        
        NSRange checkSumWithSkipLineEndRange = [output rangeOfString:@"\n" options:0 range:checkSumWithSkipLineStartRange];
        CGFloat checkSumWithSkipLineLength = checkSumWithSkipLineEndRange.location - checkSumWithSkipLineStartLocation;
        
        result = [output substringWithRange:NSMakeRange(checkSumWithSkipLineStartLocation, checkSumWithSkipLineLength)];
    }
    
    return result;
}

@end
