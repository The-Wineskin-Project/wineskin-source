//
//  NSImage+Extension.m
//  ObjectiveC_Extension
//
//  Created by Vitor Marques de Miranda on 12/03/17.
//  Copyright © 2017 Vitor Marques de Miranda. All rights reserved.
//

#import <CoreImage/CoreImage.h>

#import "NSFileManager+Extension.h"
#import "NSImage+Extension.h"
#import "NSString+Extension.h"
#import "NSTask+Extension.h"

#import "VMMComputerInformation.h"
#import "VMMLogUtility.h"

#define SMALLER_ICONSET_NEEDED_SIZE 16
#define BIGGEST_ICONSET_NEEDED_SIZE 1024

#define TIFF2ICNS_ICON_SIZE 512

@implementation NSBitmapImageRep (VMMBitmapImageRep)
@end

@implementation NSImage (VMMImage)

+(NSImage*)imageWithData:(NSData*)data
{
    NSImage* image;
    
    @try
    {
        image = [[NSImage alloc] initWithData:data];
    }
    @catch (NSException* exception)
    {
        return nil;
    }
    
    return image;
}

+(NSImage*)transparentImageWithSize:(NSSize)size
{
    NSImage* clearImage = [[NSImage alloc] initWithSize:size];
    [clearImage lockFocus];
    [[NSColor clearColor] setFill];
    [NSBezierPath fillRect:NSMakeRect(0, 0, size.height, size.width)];
    [clearImage unlockFocus];
    
    return clearImage;
}

-(BOOL)saveAsPngImageWithSize:(int)size atPath:(NSString*)pngPath
{
    @autoreleasepool
    {
        CIImage *ciimage = [CIImage imageWithData:[self TIFFRepresentation]];
        CIFilter *scaleFilter = [CIFilter filterWithName:@"CILanczosScaleTransform"];
        
        int originalWidth  = [ciimage extent].size.width;
        float scale = (float)size / (float)originalWidth;
        
        [scaleFilter setValue:@(scale) forKey:@"inputScale"];
        [scaleFilter setValue:@(1.0)   forKey:@"inputAspectRatio"];
        [scaleFilter setValue:ciimage  forKey:@"inputImage"];
        
        ciimage = [scaleFilter valueForKey:@"outputImage"];
        if (ciimage == nil) return false;
        
        NSBitmapImageRep* rep;
        
        @try
        {
            rep = [[NSBitmapImageRep alloc] initWithCIImage:ciimage];
        }
        @catch (NSException* exception)
        {
            return false;
        }
        
        NSData *data = [rep representationUsingType:NSPNGFileType properties:@{}];
        [data writeToFile:pngPath atomically:YES];
    }
        
    return true;
}
-(BOOL)saveIconsetWithSize:(int)size atFolder:(NSString*)folder
{
    BOOL result = [self saveAsPngImageWithSize:size atPath:[NSString stringWithFormat:@"%@/icon_%dx%d.png",folder,size,size]];
    if (result == false) return false;
    
    result = [self saveAsPngImageWithSize:size*2 atPath:[NSString stringWithFormat:@"%@/icon_%dx%d@2x.png",folder,size,size]];
    return result;
}
-(BOOL)saveAsIcnsAtPath:(NSString*)icnsPath
{
    if (icnsPath == nil) return false;
    
    BOOL result;

    if (IS_SYSTEM_MAC_OS_10_7_OR_SUPERIOR)
    {
        @autoreleasepool
        {
            if (![icnsPath hasSuffix:@".icns"]) icnsPath = [icnsPath stringByAppendingString:@".icns"];
            NSString* iconsetPath = [[icnsPath substringToIndex:icnsPath.length - 5] stringByAppendingString:@".iconset"];
            
            [[NSFileManager defaultManager] createDirectoryAtPath:iconsetPath withIntermediateDirectories:NO];
            for (int validSize = SMALLER_ICONSET_NEEDED_SIZE; validSize <= BIGGEST_ICONSET_NEEDED_SIZE; validSize=validSize*2)
                [self saveIconsetWithSize:validSize atFolder:iconsetPath];
            
            [[NSFileManager defaultManager] removeItemAtPath:icnsPath];
            [NSTask runCommand:@[@"iconutil", @"-c", @"icns", iconsetPath]];
            [[NSFileManager defaultManager] removeItemAtPath:iconsetPath];
            
            result = ([[NSFileManager defaultManager] sizeOfRegularFileAtPath:icnsPath] > 10);
        }
        
        if (result) return true;
    }
    
    @autoreleasepool
    {
        NSString *tiffPath = [NSString stringWithFormat:@"%@.tiff",icnsPath];
        
        CGFloat correctIconSize = TIFF2ICNS_ICON_SIZE/[[NSScreen mainScreen] backingScaleFactor];
        NSImage *resizedImage = [[NSImage alloc] initWithSize:NSMakeSize(correctIconSize,correctIconSize)];
        [resizedImage lockFocus];
        [self drawInRect:NSMakeRect(0,0,correctIconSize, correctIconSize) fromRect:self.alignmentRect
               operation:NSCompositeSourceOver fraction:1.0];
        [resizedImage unlockFocus];
        
        [[resizedImage TIFFRepresentation] writeToFile:tiffPath atomically:YES];
        [[NSFileManager defaultManager] removeItemAtPath:icnsPath];
        [NSTask runCommand:@[@"tiff2icns", @"-noLarge", tiffPath, icnsPath]];
        [[NSFileManager defaultManager] removeItemAtPath:tiffPath];
        
        result = [[NSFileManager defaultManager] regularFileExistsAtPath:icnsPath];
    }
    
    return result;
}

-(NSData*)dataForImageWithType:(NSBitmapImageFileType)type {
    NSBitmapImageRep *imageRep = [NSBitmapImageRep imageRepWithData:[self TIFFRepresentation]];
    return [imageRep representationUsingType:type properties:@{}];
}

-(BOOL)writeToFile:(NSString*)file atomically:(BOOL)useAuxiliaryFile
{
    @autoreleasepool
    {
        NSString* extension = file.pathExtension.lowercaseString;
        NSDictionary* typeForExtension = @{@"bmp" : @(IS_SYSTEM_MAC_OS_10_12_OR_SUPERIOR ? NSBitmapImageFileTypeBMP      : NSBMPFileType     ),
                                           @"gif" : @(IS_SYSTEM_MAC_OS_10_12_OR_SUPERIOR ? NSBitmapImageFileTypeGIF      : NSGIFFileType     ),
                                           @"jpg" : @(IS_SYSTEM_MAC_OS_10_12_OR_SUPERIOR ? NSBitmapImageFileTypeJPEG     : NSJPEGFileType    ),
                                           @"jp2" : @(IS_SYSTEM_MAC_OS_10_12_OR_SUPERIOR ? NSBitmapImageFileTypeJPEG2000 : NSJPEG2000FileType),
                                           @"png" : @(IS_SYSTEM_MAC_OS_10_12_OR_SUPERIOR ? NSBitmapImageFileTypePNG      : NSPNGFileType     ),
                                           @"tiff": @(IS_SYSTEM_MAC_OS_10_12_OR_SUPERIOR ? NSBitmapImageFileTypeTIFF     : NSTIFFFileType    )};
        
        if ([typeForExtension.allKeys containsObject:extension] == false)
        {
            @throw [NSException exceptionWithName:NSInvalidArgumentException
                                           reason:[NSString stringWithFormat:@"Invalid extension for saving image file: %@",extension]
                                         userInfo:nil];
            return false;
        }
        
        NSData* data = [self dataForImageWithType:(NSBitmapImageFileType)[typeForExtension[extension] unsignedLongValue]];
        if (data == nil) return false;
        
        return [data writeToFile:file atomically:useAuxiliaryFile];
    }
}

@end
