//
//  NSTask+Extension.m
//  ObjectiveC_Extension
//
//  Created by Vitor Marques de Miranda on 22/02/17.
//  Copyright © 2017 Vitor Marques de Miranda. All rights reserved.
//

#import "NSTask+Extension.h"

#import "VMMAlert.h"
#import "NSMutableString+Extension.h"
#import "NSThread+Extension.h"
#import "NSFileManager+Extension.h"

#import "VMMLogUtility.h"
#import "VMMLocalizationUtility.h"

@implementation NSTask (VMMTask)

static NSMutableDictionary* binaryPaths;

+(NSString*)runCommand:(NSArray<NSString*>*)programAndFlags
{
    return [self runCommand:programAndFlags atRunPath:nil];
}
+(NSString*)runCommand:(NSArray<NSString*>*)programAndFlags atRunPath:(NSString*)path
{
    return [self runCommand:programAndFlags atRunPath:path andWait:YES];
}
+(NSString*)runCommand:(NSArray<NSString*>*)programAndFlags atRunPath:(NSString*)path andWait:(BOOL)shouldWait
{
    NSArray* flags = [programAndFlags objectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, programAndFlags.count - 1)]];
    return [self runProgram:programAndFlags.firstObject withFlags:flags atRunPath:path andWaiting:shouldWait];
}

+(void)runAsynchronousCommand:(NSArray<NSString*>*)programAndFlags
{
    [self runCommand:programAndFlags atRunPath:nil andWait:NO];
}

+(NSString*)runProgram:(NSString*)program
{
    return [self runProgram:program withFlags:nil atRunPath:nil andWaiting:YES];
}
+(NSString*)runProgram:(NSString*)program withFlags:(NSArray<NSString*>*)flags
{
    return [self runProgram:program withFlags:flags atRunPath:nil andWaiting:YES];
}
+(NSString*)runProgram:(NSString*)program withFlags:(NSArray<NSString*>*)flags outputEncoding:(NSStringEncoding)encoding
{
    return [self runProgram:program withFlags:flags atRunPath:nil withEnvironment:nil
                 andWaiting:YES forTimeInterval:0 outputEncoding:encoding];
}
+(NSString*)runProgram:(NSString*)program withFlags:(NSArray<NSString*>*)flags atRunPath:(NSString*)path andWaiting:(BOOL)wait
{
    return [self runProgram:program withFlags:flags atRunPath:path withEnvironment:nil
                 andWaiting:wait forTimeInterval:0 outputEncoding:NSUTF8StringEncoding];
}
+(NSString*)runProgram:(NSString*)program withFlags:(NSArray<NSString*>*)flags withEnvironment:(NSDictionary*)env
{
    return [self runProgram:program withFlags:flags atRunPath:@"/" withEnvironment:env
                 andWaiting:YES forTimeInterval:0 outputEncoding:NSUTF8StringEncoding];
}
+(NSString*)runProgram:(NSString*)program withFlags:(NSArray<NSString*>*)flags atRunPath:(NSString*)path withEnvironment:(NSDictionary*)env
{
    return [self runProgram:program withFlags:flags atRunPath:path withEnvironment:env
                 andWaiting:YES forTimeInterval:0 outputEncoding:NSUTF8StringEncoding];
}
+(NSString*)runProgram:(NSString*)program withFlags:(NSArray<NSString*>*)flags waitingForTimeInterval:(unsigned int)timeout
{
    return [self runProgram:program withFlags:flags atRunPath:@"/" withEnvironment:nil
                 andWaiting:YES forTimeInterval:timeout outputEncoding:NSUTF8StringEncoding];
}

+(NSString*)runProgram:(NSString*)program withFlags:(NSArray<NSString*>*)flags atRunPath:(NSString*)path withEnvironment:(NSDictionary*)env andWaiting:(BOOL)wait forTimeInterval:(unsigned int)timeout outputEncoding:(NSStringEncoding)encoding
{
    if (program && ![program hasPrefix:@"/"])
    {
        NSString* newProgramPath = [self getPathOfProgram:program withEnvironment:env];
        
        if (newProgramPath == nil)
        {
            [VMMAlert showAlertOfType:VMMAlertTypeError
                          withMessage:[NSString stringWithFormat:VMMLocalizedString(@"Path for %@ not found."), program]];
            return @"";
        }
        
        program = newProgramPath;
    }
    
#ifdef DEBUG
    if (path && flags)        NSDebugLog(@"Running %@ at path %@ with flags %@",program,path,[flags componentsJoinedByString:@" "]);
    else if (path && !flags)  NSDebugLog(@"Running %@ at path %@",program,path);
    else if (!path && flags)  NSDebugLog(@"Running %@ with flags %@",program,[flags componentsJoinedByString:@" "]);
    else if (!path && !flags) NSDebugLog(@"Running %@",program);
#endif
    
    if (path != nil && ![path hasSuffix:@"/"]) path = [path stringByAppendingString:@"/"];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:program])
    {
        [VMMAlert showAlertOfType:VMMAlertTypeError
                      withMessage:[NSString stringWithFormat:VMMLocalizedString(@"File %@ not found."), program]];
        return @"";
    }
    
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:program])
    {
        [VMMAlert showAlertOfType:VMMAlertTypeError
                      withMessage:[NSString stringWithFormat:VMMLocalizedString(@"File %@ not runnable."), program]];
        return @"";
    }
    
    if (path && ![[NSFileManager defaultManager] directoryExistsAtPath:path])
    {
        [VMMAlert showAlertOfType:VMMAlertTypeError
                      withMessage:[NSString stringWithFormat:VMMLocalizedString(@"Directory %@ does not exists."), path]];
        return @"";
    }
    
    @autoreleasepool
    {
        @try
        {
            NSTask *server = [NSTask new];
            [server setLaunchPath:program];
            if (path != nil)  [server setCurrentDirectoryPath:path];
            if (flags != nil) [server setArguments:flags];
            if (env != nil)   [server setEnvironment:env];
            
            NSFileHandle *errorFileHandle = [NSFileHandle fileHandleWithNullDevice];
            [server setStandardError:errorFileHandle];
            
            if (!wait)
            {
                [server setStandardInput:[NSPipe pipe]];
                [server launch];
                
                NSDebugLog(@"Instruction finished");
                return @"";
            }
            
            NSPipe *outputPipe = [NSPipe pipe];
            [server setStandardInput:[NSPipe pipe]];
            [server setStandardOutput:outputPipe];
            [server launch];
            
            if (timeout == 0)
            {
                [server waitUntilExit];
            }
            else
            {
                __block NSCondition* lock = [[NSCondition alloc] init];
                
                [NSThread dispatchQueueWithName:"wait-until-task-exit" priority:DISPATCH_QUEUE_PRIORITY_DEFAULT concurrent:NO withBlock:^
                {
                    [server waitUntilExit];
                    
                    @synchronized (lock)
                    {
                        if (lock != nil) [lock signal];
                    }
                }];
                
                [NSThread dispatchQueueWithName:"wait-to-kill-task" priority:DISPATCH_QUEUE_PRIORITY_DEFAULT concurrent:NO withBlock:^
                {
                    [NSThread sleepForTimeInterval:timeout];
                    
                    @synchronized (lock)
                    {
                        if (lock != nil)
                        {
                            [lock signal];
                            [server terminate];
                        }
                    }
                }];
                
                [lock lock];
                [lock wait];
                [lock unlock];
                lock = nil;
            }
            
            NSFileHandle *file = [outputPipe fileHandleForReading];
            NSData *outputData = [file readDataToEndOfFile];
            [file closeFile];
            
            NSDebugLog(@"Instruction finished");
            return [[NSString alloc] initWithData:outputData encoding:encoding];
        }
        @catch (NSException* exception)
        {
            // Sometimes (very rarely) the app might fail to retrieve the output of a command; with that, your app won't stop
            NSDebugLog(@"Failed to retrieve instruction output: %@", exception.reason);
            return @"";
        }
    }
}

+(NSString*)getPathOfProgram:(NSString*)programName
{
    return [self getPathOfProgram:programName withEnvironment:nil];
}
+(NSString*)getPathOfProgram:(NSString*)programName withEnvironment:(NSDictionary*)env
{
    if (programName == nil) return nil;
    if (binaryPaths != nil && binaryPaths[programName]) return binaryPaths[programName];
    
    NSString* programPath;
    
    @autoreleasepool
    {
        if (binaryPaths == nil) binaryPaths = [[NSMutableDictionary alloc] init];
        
        programPath = [self runProgram:@"/usr/bin/type" withFlags:@[@"-a",programName] withEnvironment:env];
        if (programPath == nil) return nil;
        
        programPath = [[programPath componentsSeparatedByString:@" "] lastObject];
        if (programPath.length == 0) return nil;
        
        programPath = [programPath substringToIndex:programPath.length-1];
    }
    
    if (programPath != nil) binaryPaths[programName] = programPath;
    return programPath;
}

@end

