//
//  WineskinAppDelegate.m
//  Wineskin
//
//  Copyright 2014 by The Wineskin Project and Urge Software LLC All rights reserved.
//  Licensed for use under the LGPL <http://www.gnu.org/licenses/lgpl-2.1.txt>
//

#import "WineskinLauncherAppDelegate.h"
#import <ObjectiveC_Extension/ObjectiveC_Extension.h>
#import "NSPathUtilities.h"
#import "NSPortDataLoader.h"
#import "WineskinLauncher_Prefix.pch"
#import "NSWineskinEngine.h"

@implementation WineskinLauncherAppDelegate

-(NSString*)wrapperPath
{
    return [[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent];
}

static NSPortManager* portManager;

-(NSPortManager*)portManager
{
    @synchronized([self class])
    {
        if (!portManager) {
            portManager = [NSPortManager managerForWrapperAtPath:[[NSBundle mainBundle] bundlePath]];
        }

        return portManager;
    }
}

- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls;
{
    for (NSURL *url in urls) {
        NSString *urlString = [url absoluteString];

        NSRange replaceRange = [urlString rangeOfString:@"file://"];
        if (replaceRange.location == 0) {
            urlString = [urlString stringByReplacingCharactersInRange:replaceRange withString:@""];
        }

        [globalFilesToOpen addObject:urlString];
    }
    if (wrapperRunning) {
        [NSThread detachNewThreadSelector:@selector(secondaryRun:) toTarget:self withObject:[globalFilesToOpen copy]];
        [globalFilesToOpen removeAllObjects];
    }
}

- (void)application:(NSApplication *)sender openFiles:(NSArray *)filenames
{
    [globalFilesToOpen addObjectsFromArray:filenames];
    if (wrapperRunning) {
        [NSThread detachNewThreadSelector:@selector(secondaryRun:) toTarget:self withObject:[globalFilesToOpen copy]];
        [globalFilesToOpen removeAllObjects];
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    if (![fm fileExistsAtPath:pathToWineFolder]) {
        [VMMAlert showAlertOfType:VMMAlertTypeWarning withMessage:[NSString stringWithFormat:@"No Engine installed.\n\nDon't direcly launch %@.app you need to use \"Wineskin Winery\" \nto create a working wrapper", appName]];
        exit(0);
    }

	[window setLevel:NSStatusWindowLevel];
	[waitWheel startAnimation:self];

	if ([globalFilesToOpen containsObject:@"WSS-InstallICE"]) exit(0);

	// Normal run
    [NSThread detachNewThreadSelector:@selector(mainRun:) toTarget:self withObject:[globalFilesToOpen copy]];
    [globalFilesToOpen removeAllObjects];
    wrapperRunning=YES;
}

- (void)applicationWillFinishLaunching:(NSNotification*)aNotification
{
    NSString *uid = [NSString stringWithFormat: @"%d", getuid()];
    appNameWithPath = self.portManager.path;
    contentsFold = [NSString stringWithFormat:@"%@/Contents",appNameWithPath];
    resourcesFold = [NSString stringWithFormat:@"%@/Resources",contentsFold];
    frameworksFold = [NSString stringWithFormat:@"%@/Frameworks",contentsFold];
    moltenvkcxFold = [NSString stringWithFormat:@"%@/moltenvkcx",frameworksFold];
    sharedsupportFold = [NSString stringWithFormat:@"%@/SharedSupport",contentsFold];
    winePrefix = [NSString stringWithFormat:@"%@/prefix",sharedsupportFold];
    pathToWineFolder = [NSString stringWithFormat:@"%@/wine",sharedsupportFold];
    pathToWineBinFolder = [NSString stringWithFormat:@"%@/bin",pathToWineFolder];
    appName = appNameWithPath.lastPathComponent.stringByDeletingPathExtension;
    tmpFolder = [NSString stringWithFormat:@"/tmp/%@",[appNameWithPath stringByReplacingOccurrencesOfString:@"/" withString:@"xWSx"]];
    tmpwineFolder = [NSString stringWithFormat:@"/tmp/.wine-%@",uid];

    
    gstreamerFold = [NSString stringWithFormat:@"%@/GStreamer.framework/Libraries",frameworksFold];
    gstPluginPath = [NSString stringWithFormat:@"%@/gstreamer-1.0",gstreamerFold];

    
    if ([[self.portManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_MSYNC] intValue] == 1) {
        // Set esync & msync together to avoid D3DMetal using it's own crappy sync
        wineEsync = @"WINEESYNC=1";
        wineMsync = @"WINEMSYNC=1";
    } else if ([[self.portManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_ESYNC] intValue] == 1) {
        wineEsync = @"WINEESYNC=1";
        wineMsync = @"";
    } else {
        wineEsync = @"";
        wineMsync = @"";
    }

    globalFilesToOpen = [[NSMutableArray alloc] init];
    fm = [NSFileManager defaultManager];
    wrapperRunning = NO;
    removeX11TraceFromLog = NO;
    primaryRun = YES;

    CGEventRef event = CGEventCreate(NULL);
    CGEventFlags modifiers = CGEventGetFlags(event);
    CFRelease(event);

    if ((modifiers & kCGEventFlagMaskAlternate)   == kCGEventFlagMaskAlternate || (modifiers & kCGEventFlagMaskSecondaryFn) == kCGEventFlagMaskSecondaryFn) {
        [self doSpecialStartup];
    }
}

- (void)doSpecialStartup
{
    //when holding modifier key
    NSString* theSystemCommand = [NSString stringWithFormat: @"open \"%@/Contents/Wineskin.app\"", [[NSBundle mainBundle] bundlePath]];
    system([theSystemCommand UTF8String]);
    [NSApp terminate:nil];
}

- (NSString *)systemCommand:(NSString *)command
{
	FILE *fp;
	char buff[512];
	NSMutableString *returnString = [[NSMutableString alloc] init];
	fp = popen([command cStringUsingEncoding:NSUTF8StringEncoding], "r");
	while (fgets( buff, sizeof buff, fp)) {
        [returnString appendString:[NSString stringWithCString:buff encoding:NSUTF8StringEncoding]];
    }
	pclose(fp);

    //cut out trailing new line
	if ([returnString hasSuffix:@"\n"]) {
        [returnString deleteCharactersInRange:NSMakeRange([returnString length]-1,1)];
    }
	return [NSString stringWithString:returnString];
}

- (void)mainRun:(NSArray*)filesToOpen
{
    @autoreleasepool
    {
        // TODO need to add option to make wrapper run in AppSupport (shadowcopy) so that no files will ever be written in the app
        // TODO need to make all the temp files inside the wrapper run correctly using BundleID and in /tmp.  If they don't exist, assume everything is fine.
        // TODO add blocks to sections that need them for variables to free up memory.

        //TODO: Seems this is not used for bundle name on created but recreation works?
        // set CFBundleID too
        srand((unsigned)time(0));
        bundleRandomInt1 = (int)(rand()%999999999);
        if (bundleRandomInt1 < 0) {
            bundleRandomInt1 = bundleRandomInt1*(-1);
        }

        NSMutableArray *filesToRun = [[NSMutableArray alloc] init];
        NSMutableString *wineRunLocation = [[NSMutableString alloc] init];
        NSMutableString *programNameAndPath = [[NSMutableString alloc] init];
        NSMutableString *cliCustomCommands = [[NSMutableString alloc] init];
        NSMutableString *programFlags = [[NSMutableString alloc] init];
        NSMutableString *vdResolution = [[NSMutableString alloc] init];
        fullScreenResolutionBitDepth = [[NSMutableString alloc] init];
        [fullScreenResolutionBitDepth setString:@"unset"];
        BOOL runWithStartExe = NO;
        fullScreenOption = NO;
        debugEnabled = NO;
        BOOL cexeRun = NO;
        BOOL nonStandardRun = NO;
        BOOL openingFiles = NO;

        NSString *wssCommand;
        if (filesToOpen.count > 0) {
            wssCommand = filesToOpen[0];
        } else {
            wssCommand = @"nothing";
        }
        if ([wssCommand isEqualToString:@"CustomEXE"]) cexeRun = YES;

        [fm createDirectoryAtPath:tmpFolder withIntermediateDirectories:YES];
        [self systemCommand:[NSString stringWithFormat:@"chmod -R 777 \"%@\"",tmpFolder]];

        lockfile        = [NSString stringWithFormat:@"%@/lockfile",tmpFolder];
        wineLogFile     = [NSString stringWithFormat:@"%@/Logs/LastRunWine.log",sharedsupportFold];
        wineTempLogFile = [NSString stringWithFormat:@"%@/LastRunWineTemp.log",sharedsupportFold];
        x11LogFile      = [NSString stringWithFormat:@"%@/Logs/LastRunX11.log",sharedsupportFold];
        useMacDriver    = [self checkToUseMacDriver];

        //exit if the lock file exists, another user is running this wrapper currently
        BOOL lockFileAlreadyExisted = NO;
        if ([fm fileExistsAtPath:lockfile]) {
            //read in lock file to get user name of who locked it, if same user name ignore
            if (![[[self readFileToStringArray:lockfile] objectAtIndex:0] isEqualToString:NSUserName()]) {
                CFUserNotificationDisplayNotice(0, 0, NULL, NULL, NULL, CFSTR("ERROR"), CFSTR("Another user on this system is currently using this application\n\nThey must exit the application before you can use it."), NULL);
                return;
            }
                lockFileAlreadyExisted = YES;
        } else {
            //create lockfile that we are already in use
            [self writeStringArray:@[NSUserName()] toFile:lockfile];
            [self systemCommand:[NSString stringWithFormat:@"chmod -R 777 \"%@\"",tmpFolder]];
        }

        //open Info.plist to read all needed info
        NSPortManager *cexeManager = nil;
        NSString *resolutionTemp;

        //check to make sure CFBundleName is not WineskinNavyWrapper, if it is, change it to current wrapper name
        if ([[self.portManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_NAME] isEqualToString:@"WineskinNavyWrapper"]) {
            [self.portManager setPlistObject:appName forKey:WINESKIN_WRAPPER_PLIST_KEY_NAME];
        }

        //TODO: BundleID Generation
        //Strip all invalid characters including spaces for a more valid BundleID
        NSString* validCharactersString = @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
         NSCharacterSet* invalidCharacters = [[NSCharacterSet characterSetWithCharactersInString:validCharactersString] invertedSet];
         NSString* wrapperName = appName;
         wrapperName = [wrapperName stringByReplacingOccurrencesOfString:@":"   withString:@""];
         wrapperName = [wrapperName stringByReplacingOccurrencesOfString:@" & " withString:@"and"];
         wrapperName = [wrapperName stringByRemovingCharactersInSet:invalidCharacters];
         wrapperName = [wrapperName stringByTrimmingCharactersInSet:
         [NSCharacterSet whitespaceAndNewlineCharacterSet]];

        //Only touch the BundleID once
        if ([[self.portManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_IDENTIFIER] isEqualToString:@"com.WineskinNavyWrapper.Wineskin"] || ![[self.portManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_IDENTIFIER] contains:wrapperName]) {
            [self.portManager setPlistObject:[NSString stringWithFormat:@"com.%@%d.wineskin",wrapperName,bundleRandomInt1] forKey:WINESKIN_WRAPPER_PLIST_KEY_IDENTIFIER];
        }
        [self.portManager synchronizePlist];

        //need to handle it different if its a cexe
        if (!cexeRun) {
            [programNameAndPath setString:[self.portManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_RUN_PATH]];
            [programFlags       setString:[self.portManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_RUN_PATH_FLAGS]];
            fullScreenOption = [[self.portManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_SCREEN_OPTIONS_IS_FULLSCREEN] intValue];
            resolutionTemp   =  [self.portManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_SCREEN_OPTIONS_CONFIGURATIONS];
            runWithStartExe  = [[self.portManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_RUN_PATH_IS_NOT_EXE] intValue];
        } else {
            cexeManager = [NSPortManager managerForCustomExeAtPath:[NSString stringWithFormat:@"%@/Contents/%@",
                                                                    appNameWithPath,[filesToOpen objectAtIndex:1]]];
            [programNameAndPath setString:[cexeManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_RUN_PATH]];
            [programFlags       setString:[cexeManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_RUN_PATH_FLAGS]];
            fullScreenOption           = [[cexeManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_SCREEN_OPTIONS_IS_FULLSCREEN] intValue];
            resolutionTemp             =  [cexeManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_SCREEN_OPTIONS_CONFIGURATIONS];
            runWithStartExe            = [[cexeManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_RUN_PATH_IS_NOT_EXE] intValue];
        }

        debugEnabled = [[self.portManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_DEBUG_MODE] intValue];

        if ([[self.portManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_MOLTENVK_CX] intValue] == 1) {
            dyldFallBackLibraryPath = [NSString stringWithFormat:@"%@:%@/lib:%@/lib/external:%@/lib64:%@:/opt/wine/lib:%@:/usr/lib:/usr/libexec:/usr/lib/system:/opt/X11/lib",moltenvkcxFold,pathToWineFolder,pathToWineFolder,pathToWineFolder,frameworksFold,gstreamerFold];
        } else {
            dyldFallBackLibraryPath = [NSString stringWithFormat:@"%@/lib:%@/lib/external:%@/lib64:%@:/opt/wine/lib:%@:/usr/lib:/usr/libexec:/usr/lib/system:/opt/X11/lib",pathToWineFolder,pathToWineFolder,pathToWineFolder,frameworksFold,gstreamerFold];
        }
        //1st (app)/Contents/SharedSupport/wine/lib/
        //2nd (app)/Contents/SharedSupport/wine/lib/external/
        //3rd (app)/Contents/SharedSupport/wine/lib64/
        //4th (app)/Contents/Frameworks/
        //5th /opt/wine/lib/
        //6th (gstreamerFold)
        //7th system locations
        //8th /opt/X11/lib/ (XQuartz)

        //MoltenVK overrides
        FENCES    = @"MVK_ALLOW_METAL_FENCES=1"; //For legacy MoltenVK versions
        RESUME    = @"MVK_CONFIG_RESUME_LOST_DEVICE=1"; //Required by WINE (doesn't handle VK_ERROR_DEVICE_LOST correctly)
        SEMAPHORE = @"MVK_CONFIG_VK_SEMAPHORE_SUPPORT_STYLE=MVK_CONFIG_VK_SEMAPHORE_SUPPORT_STYLE_SINGLE_QUEUE"; //MoltenVK-v1.1.12+
        SWIZZLE   = @"MVK_CONFIG_FULL_IMAGE_VIEW_SWIZZLE=1";

        //Custom wine env
        HIDEBOOT  = @"WINEBOOT_HIDE_DIALOG=1";

        //TODO: MTL_HUD_ENABLED
        if ([[self.portManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_METAL_HUD] intValue] == 1) {
            metalHUD = @"MTL_HUD_ENABLED=1";
        } else {
            metalHUD = @"MTL_HUD_ENABLED=0";
        }

        if ([[self.portManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_MOLTENVK_FASTMATH] intValue] == 1) {
            FASTMATH  = @"MVK_CONFIG_FAST_MATH_ENABLED=1";
        } else {
            FASTMATH  = @"MVK_CONFIG_FAST_MATH_ENABLED=0";
        }

        //TODO: .Net 7 and later segfault under Rosetta2
        // https://github.com/dotnet/runtime/issues/94909
        DOTNET = @"DOTNET_EnableWriteXorExecute=0";

        //set the wine executable to be used.
        //we can't trust the Engine is named correctly so check the actual binary files
        if ([fm fileExistsAtPath:[NSString stringWithFormat:@"%@/wine64",pathToWineBinFolder]]) {
            wineExecutable = @"wine64";
        // CX19|CX20|CX21 used this binary, CX22|upstream wow64 uses wine64
        } else if ([fm fileExistsAtPath:[NSString stringWithFormat:@"%@/wine32on64",pathToWineBinFolder]] && IS_SYSTEM_MAC_OS_10_15_OR_SUPERIOR) {
            wineExecutable = @"wine32on64";
        } else {
            wineExecutable = @"wine";
        }

        //if any program flags, need to add a space to the front of them
        if (!([programFlags isEqualToString:@""])) {
            [programFlags insertString:@" " atIndex:0];
        }

        [cliCustomCommands setString:[self.portManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_UNIX_COMMANDS]];
        if (!([cliCustomCommands hasSuffix:@";"]) && ([cliCustomCommands length] > 0)) {
            [cliCustomCommands appendString:@";"];
        }

        //******* fix all data correctly
        //list of possile options
        //WSS-installer {path/file}	- Installer is calling the program
        //WSS-winecfg 				- need to run winecfg
        //WSS-cmd					- need to run cmd
        //WSS-regedit 				- need to run regedit
        //WSS-taskmgr 				- need to run taskmgr
        //WSS-uninstaller			- run uninstaller
        //WSS-wineprefixcreate		- need to run wineboot, refresh wrapper
        //WSS-wineprefixcreatenoregs- same as above, doesn't load default regs
        //WSS-wineboot				- run simple wineboot, no deletions or loading regs. mshtml=disabled
        //WSS-winetricks {command}	- winetricks is being run
        //WSS-wineserverkill        - tell winesever to kill all wine processes from wrapper
        //debug 					- run in debug mode, keep logs
        //CustomEXE {appname}		- running a custom EXE with appname
        //starts with a"/" 			- will be 1+ path/filename to open
        //no command line args		- normal run

        NSMutableArray *winetricksCommands = [[NSMutableArray alloc] init];
        if ([filesToOpen count] > 1) {
            [winetricksCommands addObjectsFromArray:[filesToOpen subarrayWithRange:NSMakeRange(1, [filesToOpen count]-1)]];
        }
        if ([filesToOpen count] > 0) {
            // if wssCommand starts with a / its file(s) passed in to open or url schema
            if ([wssCommand hasPrefix:@"/"] ||
                [wssCommand rangeOfString:@"[A-Za-z][A-Za-z0-9\\.\\+-]+:" options:NSRegularExpressionSearch].location == 0) {
                for (NSString *item in filesToOpen) {
                    [filesToRun addObject:item];
                }
                openingFiles=YES;
            //if wssCommand starts with WSS- its a special command
            } else if ([wssCommand hasPrefix:@"WSS-"]) {
                debugEnabled = YES; //need logs in special commands

                //if its in the installer, need to know if normal windows are forced
                if ([wssCommand isEqualToString:@"WSS-installer"]) {
                    if ([[self.portManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_INSTALLER_WITH_NORMAL_WINDOWS] intValue] == 1) {
                        [fullScreenResolutionBitDepth setString:@"24"];
                        [vdResolution setString:WINESKIN_WRAPPER_PLIST_VALUE_SCREEN_OPTIONS_NO_VIRTUAL_DESKTOP];
                        fullScreenOption = NO;
                        //sleepNumber = 0;
                    }
                    [programNameAndPath setString:[filesToOpen objectAtIndex:1]]; // second argument full path and file name to run
                    runWithStartExe = YES; //installer always uses start.exe
                //any WSS that isn't the installer
                } else {
                    [fullScreenResolutionBitDepth setString:@"24"]; // all should force normal windows
                    [vdResolution setString:WINESKIN_WRAPPER_PLIST_VALUE_SCREEN_OPTIONS_NO_VIRTUAL_DESKTOP];
                    fullScreenOption = NO;
                    //sleepNumber = 0;

                    //should only use this line for winecfg cmd regedit and taskmgr, other 2 do nonstandard runs and wont use this line
                    if ([wssCommand isEqualToString:@"WSS-regedit"]) {
                        [programNameAndPath setString:@"/windows/regedit.exe"];
                    //This stops wineserverkill.exe from showing in "LastRunWine.log"
                    } else if ([wssCommand isEqualToString:@"WSS-wineserverkill"]) {
                        NSArray* command = @[
                            [NSString stringWithFormat:@"export PATH=\"%@:/usr/bin:/bin:/usr/sbin:/sbin\";",pathToWineBinFolder],
                            [NSString stringWithFormat:@"DYLD_FALLBACK_LIBRARY_PATH=\"%@\"",dyldFallBackLibraryPath],
                            [NSString stringWithFormat:@"export WINEPREFIX=\"%@\";",winePrefix],@"wineserver -k"];
                        [self systemCommand:[command componentsJoinedByString:@" "]];
                        usleep(3000000);

                        //****** if "IsFnToggleEnabled" is enabled
                        if ([[self.portManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_ENABLE_FNTOGGLE] intValue] == 1) {
                            [self systemCommand:[NSString stringWithFormat:@"\"%@/Wineskin.app/Contents/Resources/fntoggle\" off",contentsFold]];
                        }
                    } else {
                        if ([wssCommand isEqualToString:@"WSS-cmd"]) {
                            runWithStartExe=YES;
                        }
                        [programNameAndPath setString:[NSString stringWithFormat:@"/windows/system32/%@.exe",[wssCommand stringByReplacingOccurrencesOfString:@"WSS-" withString:@""]]];
                    }
                    [programFlags setString:@""]; // just in case there were some flags... don't use on these.
                    if ([wssCommand isEqualToString:@"WSS-wineboot"] || [wssCommand isEqualToString:@"WSS-wineprefixcreate"] || [wssCommand isEqualToString:@"WSS-wineprefixcreatenoregs"]) {
                        nonStandardRun=YES;
                    }
                }
            //if wssCommand is debug, run in debug mode
            } else if ([wssCommand isEqualToString:@"debug"]) {
                debugEnabled=YES;
                NSLog(@"Debug Mode enabled");
            }
        }

        //if vdResolution is bigger than currentResolution, need to downsize it
        if (![vdResolution isEqualToString:WINESKIN_WRAPPER_PLIST_VALUE_SCREEN_OPTIONS_NO_VIRTUAL_DESKTOP]) {
            int xRes = [[vdResolution getFragmentAfter:nil andBefore:@" "] intValue];
            int yRes = [[vdResolution getFragmentAfter:@" " andBefore:nil] intValue];
            int xResMax = [[currentResolution getFragmentAfter:nil andBefore:@" "] intValue];
            int yResMax = [[currentResolution getFragmentAfter:@" " andBefore:nil] intValue];
            if (xRes > xResMax || yRes > yResMax) {
                [vdResolution setString:currentResolution];
            }
        }

        //fix wine run paths
        if (![programNameAndPath hasPrefix:@"/"]) {
            [programNameAndPath insertString:@"/" atIndex:0];
        }

        [wineRunLocation setString:[programNameAndPath substringToIndex:[programNameAndPath rangeOfString:@"/" options:NSBackwardsSearch].location]];
        NSString *wineRunFile = programNameAndPath.lastPathComponent;

        //add path to drive C if its not an installer
        if (!([wssCommand isEqualToString:@"WSS-installer"])) {
            [wineRunLocation insertString:[NSString stringWithFormat:@"%@/drive_c",winePrefix] atIndex:0];
        }

        //**********make sure that the set executable is found if normal run
        if (!openingFiles && !([wssCommand hasPrefix:@"WSS-"]) &&
            !([fm fileExistsAtPath:[NSString stringWithFormat:@"%@/%@",wineRunLocation,wineRunFile]])) {
            //error, file doesn't exist, and its not a special command
            NSLog(@"Error! Set executable not found.  Wineskin.app running instead.");
            system([[NSString stringWithFormat:@"open \"%@/Contents/Wineskin.app\"",appNameWithPath] UTF8String]);
            [fm removeItemAtPath:lockfile];
            [fm removeItemAtPath:tmpFolder];
            //[fm removeItemAtPath:tmpwineFolder];
            exit(0);
        }
        //********** Wineskin Customizer start up script
        system([[NSString stringWithFormat:@"\"%@/Scripts/WineskinStartupScript\"",resourcesFold] UTF8String]);

        //****** if "IsFnToggleEnabled" is enabled
        if ([[self.portManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_ENABLE_FNTOGGLE] intValue] == 1) {
            [self systemCommand:[NSString stringWithFormat:@"\"%@/Wineskin.app/Contents/Resources/fntoggle\" on",contentsFold]];
        }

        //TODO: CPU Disabled does not work on current macOS versions, still need a replacement
        //****** if CPUs Disabled, disable all but 1 CPU
        NSString *cpuCountInput;
        if ([[self.portManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_SINGLE_CPU] intValue] == 1) {
            cpuCountInput = [self systemCommand:@"hwprefs cpu_count 2>/dev/null"];
            int i, cpuCount = [cpuCountInput intValue];
            for (i = 2; i <= cpuCount; ++i) {
                [self systemCommand:[NSString stringWithFormat:@"hwprefs cpu_disable %d",i]];
            }
        }

        if (lockFileAlreadyExisted) {
            //if lockfile already existed, then this instance was launched when another is the main one.
            //We need to pass the parameters given to WineskinLauncher over to the correct run of this program
            WineStart *wineStartInfo = [[WineStart alloc] init];
            [wineStartInfo setWssCommand:wssCommand];
            [wineStartInfo setWinetricksCommands:winetricksCommands];
            [self secondaryRun:filesToOpen];
            BOOL killWineskin = YES;

            if (killWineskin) {
                exit(0);
                //[NSApp terminate:nil];
            }
        }

        //**********set user folders
        [self setUserFolders:([[self.portManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_SYMLINK_USERS] intValue] == 1)];

        //********** fix wineprefix
        //[self fixWinePrefixForCurrentUser];

        //********** If setting GPU info, do it
        if ([[self.portManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_AUTOMATICALLY_DETECT_GPU] intValue] == 1) {
            [self tryToUseGPUInfo];
        }

        //**********start wine
        WineStart *wineStartInfo = [[WineStart alloc] init];
        [wineStartInfo setFilesToRun:filesToRun];
        [wineStartInfo setProgramFlags:programFlags];
        [wineStartInfo setWineRunLocation:wineRunLocation];
        [wineStartInfo setVdResolution:vdResolution];
        [wineStartInfo setCliCustomCommands:cliCustomCommands];
        [wineStartInfo setRunWithStartExe:runWithStartExe];
        [wineStartInfo setNonStandardRun:nonStandardRun];
        [wineStartInfo setOpeningFiles:openingFiles];
        [wineStartInfo setWssCommand:wssCommand];
        [wineStartInfo setWineDebugLine:[self.portManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_WINEDEBUG]];
        [wineStartInfo setWinetricksCommands:winetricksCommands];
        [wineStartInfo setWineRunFile:wineRunFile];
        [self startWine:wineStartInfo];

        //change fullscreen reso if needed
        if (fullScreenOption) {
            [self setResolution:vdResolution];
        }

        //for xorg1.11.0+, log files are put in ~/Library/Logs.  Need to move to correct place if in Debug

        //********** Write system info to end X11 log file
        if (debugEnabled) {
            NSString *versionFile = [NSString stringWithFormat:@"%@/wine/version",contentsFold];
            if ([fm fileExistsAtPath:versionFile]) {
                NSArray *tempArray = [self readFileToStringArray:versionFile];
                [self systemCommand:[NSString stringWithFormat:@"echo \"Engine Used: %@\" >> \"%@\"",[tempArray objectAtIndex:0],x11LogFile]];
            }
            //use mini detail level so no personal information can be displayed
            [self systemCommand:[NSString stringWithFormat:@"system_profiler -detailLevel mini SPHardwareDataType SPDisplaysDataType >> \"%@\"",x11LogFile]];
        }

        //**********sleep and monitor in background while app is running
        [self sleepAndMonitor];

        //****** if "IsFnToggleEnabled" is enabled, revert
        if ([[self.portManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_ENABLE_FNTOGGLE] intValue] == 1) {
            [self systemCommand:[NSString stringWithFormat:@"\"%@/Wineskin.app/Contents/Resources/fntoggle\" off",contentsFold]];
        }

        //****** if CPUs Disabled, re-enable them
        if ([[self.portManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_SINGLE_CPU] intValue] == 1) {
            int i, cpuCount = [cpuCountInput intValue];
            for ( i = 2; i <= cpuCount; ++i) {
                [self systemCommand:[NSString stringWithFormat:@"hwprefs cpu_enable %d",i]];
            }
        }

        //********** Wineskin Customizer shut down script
        system([[NSString stringWithFormat:@"\"%@/Scripts/WineskinShutdownScript\"",resourcesFold] UTF8String]);

        //********** app finished, time to clean up and shut down
        if ([[self.portManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_AUTOMATICALLY_DETECT_GPU] intValue] == 1) {
            [self removeGPUInfo];
        }
        [self cleanUpAndShutDown];
        return;
	}
}

- (void)secondaryRun:(NSArray*)filesToOpen
{
    @autoreleasepool
    {
        primaryRun = NO;
        NSMutableArray *filesToRun = [[NSMutableArray alloc] init];
        NSMutableString *wineRunLocation = [[NSMutableString alloc] init];
        NSMutableString *programNameAndPath = [[NSMutableString alloc] init];
        NSMutableString *cliCustomCommands = [[NSMutableString alloc] init];
        NSMutableString *programFlags = [[NSMutableString alloc] init];
        BOOL runWithStartExe = NO;
        BOOL nonStandardRun = NO;
        BOOL openingFiles = NO;
        NSString *wssCommand;

        if ([filesToOpen count] > 0) {
            wssCommand = [filesToOpen objectAtIndex:0];
        } else {
            wssCommand = @"nothing";
        }

        NSPortManager *cexeManager;
        NSString *resolutionTemp;
        //need to handle it different if its a cexe
        if ([wssCommand isEqualToString:@"CustomEXE"]) {
            cexeManager = [NSPortManager managerForCustomExeAtPath:[NSString stringWithFormat:@"%@/Contents/%@",
                                                                    appNameWithPath,[filesToOpen objectAtIndex:1]]];
            [programNameAndPath setString:[cexeManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_RUN_PATH]];
            [programFlags setString:[cexeManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_RUN_PATH_FLAGS]];
            resolutionTemp = [cexeManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_SCREEN_OPTIONS_CONFIGURATIONS];
            runWithStartExe = [[cexeManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_RUN_PATH_IS_NOT_EXE] intValue];
        } else {
            [programNameAndPath setString:[self.portManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_RUN_PATH]];
            [programFlags setString:[self.portManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_RUN_PATH_FLAGS]];
            resolutionTemp = [self.portManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_SCREEN_OPTIONS_CONFIGURATIONS];
            runWithStartExe = [[self.portManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_RUN_PATH_IS_NOT_EXE] intValue];
        }

        //if any program flags, need to add a space to the front of them
        if (!([programFlags isEqualToString:@""])) {
            [programFlags insertString:@" " atIndex:0];
        }

        [cliCustomCommands setString:[self.portManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_UNIX_COMMANDS]];
        if (!([cliCustomCommands hasSuffix:@";"]) && ([cliCustomCommands length] > 0)) {
            [cliCustomCommands appendString:@";"];
        }

        //******* fix all data correctly
        //list of possile options
        //WSS-installer {path/file}	- Installer is calling the program
        //WSS-winecfg 				- need to run winecfg
        //WSS-cmd					- need to run cmd
        //WSS-regedit 				- need to run regedit
        //WSS-taskmgr 				- need to run taskmgr
        //WSS-uninstaller			- run uninstaller
        //WSS-wineprefixcreate		- need to run wineboot, refresh wrapper
        //WSS-wineprefixcreatenoregs- same as above, doesn't load default regs
        //WSS-wineboot				- run simple wineboot, no deletions or loading regs. mshtml=disabled
        //WSS-winetricks {command}	- winetricks is being run
        //WSS-wineserverkill        - tell winesever to kill all wine processes from wrapper
        //debug 					- run in debug mode, keep logs
        //CustomEXE {appname}		- running a custom EXE with appname
        //starts with a"/" 			- will be 1+ path/filename to open
        //no command line args		- normal run

        NSMutableArray *winetricksCommands = [[NSMutableArray alloc] init];
        if ([filesToOpen count] > 1) {
            [winetricksCommands addObjectsFromArray:[filesToOpen subarrayWithRange:NSMakeRange(1, filesToOpen.count-1)]];
        }
        if ([filesToOpen count] > 0) {
            // if wssCommand starts with a / its file(s) passed in to open or url schema
            if ([wssCommand hasPrefix:@"/"] ||
                [wssCommand rangeOfString:@"[A-Za-z][A-Za-z0-9\\.\\+-]+:" options:NSRegularExpressionSearch].location == 0) {
                for (NSString *item in filesToOpen) {
                    [filesToRun addObject:item];
                }
                openingFiles=YES;
            //if wssCommand starts with WSS- its a special command
            } else if ([wssCommand hasPrefix:@"WSS-"]) {
                //if its in the installer, need to know if normal windows are forced
                if ([wssCommand isEqualToString:@"WSS-installer"]) {
                    // do not run the installer if the wrapper is already running!
                    CFUserNotificationDisplayNotice(0, 0, NULL, NULL, NULL, CFSTR("ERROR"), CFSTR("Error: Do not try to run the Installer if the wrapper is already running something else!"), NULL);
                    NSLog(@"Error: Do not try to run the Installer if the wrapper is already running something else!");
                    return;
                //any WSS that isn't the installer
                } else {
                    //should only use this line for winecfg cmd regedit and taskmgr, other 2 do nonstandard runs and wont use this line
                    if ([wssCommand isEqualToString:@"WSS-regedit"]) {
                        [programNameAndPath setString:@"/windows/regedit.exe"];
                    //this will stop wineserverkill.exe from showing in "LastRunWine.log"
                    } else if ([wssCommand isEqualToString:@"WSS-wineserverkill"]) {
                        return;
                    } else {
                        if ([wssCommand isEqualToString:@"WSS-cmd"]) {
                            runWithStartExe=YES;
                        }
                        [programNameAndPath setString:[NSString stringWithFormat:@"/windows/system32/%@.exe",[wssCommand stringByReplacingOccurrencesOfString:@"WSS-" withString:@""]]];
                    }
                    [programFlags setString:@""]; // just in case there were some flags... don't use on these.
                    if ([wssCommand isEqualToString:@"WSS-wineboot"] || [wssCommand isEqualToString:@"WSS-wineprefixcreate"] || [wssCommand isEqualToString:@"WSS-wineprefixcreatenoregs"]) {
                        nonStandardRun=YES;
                    }
                }
            }
        }

        //fix wine run paths
        if (![programNameAndPath hasPrefix:@"/"]) {
            [programNameAndPath insertString:@"/" atIndex:0];
        }

        [wineRunLocation setString:[programNameAndPath substringToIndex:[programNameAndPath rangeOfString:@"/" options:NSBackwardsSearch].location]];
        NSString *wineRunFile = programNameAndPath.lastPathComponent;

        //add path to drive C if its not an installer
        if (!([wssCommand isEqualToString:@"WSS-installer"])) {
            [wineRunLocation insertString:[NSString stringWithFormat:@"%@/drive_c",winePrefix] atIndex:0];
        }

        //**********start wine
        WineStart *wineStartInfo = [[WineStart alloc] init];
        [wineStartInfo setFilesToRun:filesToRun];
        [wineStartInfo setProgramFlags:programFlags];
        [wineStartInfo setWineRunLocation:wineRunLocation];
        [wineStartInfo setVdResolution:@"secondary"];
        [wineStartInfo setCliCustomCommands:cliCustomCommands];
        [wineStartInfo setRunWithStartExe:runWithStartExe];
        [wineStartInfo setNonStandardRun:nonStandardRun];
        [wineStartInfo setOpeningFiles:openingFiles];
        [wineStartInfo setWssCommand:wssCommand];
        [wineStartInfo setWineDebugLine:[self.portManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_WINEDEBUG]];
        [wineStartInfo setWinetricksCommands:winetricksCommands];
        [wineStartInfo setWineRunFile:wineRunFile];
        [self startWine:wineStartInfo];
	}
}

- (void)setResolution:(NSString *)reso
{
    NSString* xRes = [reso getFragmentAfter:nil andBefore:@" "];
    NSString* yRes = [reso getFragmentAfter:@" " andBefore:nil];

    //if XxY doesn't exist, we will ignore for now... in the future maybe add way to find the closest reso that is available.
	//change the resolution using Xrandr
    NSArray* command = @[
        [NSString stringWithFormat:@"export PATH=\"%@:/usr/bin:/bin:/usr/sbin:/sbin\";",pathToWineBinFolder],
        [NSString stringWithFormat:@"export WINEPREFIX=\"%@\";",winePrefix],
        [NSString stringWithFormat:@"cd \"%@\";",pathToWineBinFolder],
        [NSString stringWithFormat:@"DYLD_FALLBACK_LIBRARY_PATH=\"%@\"",dyldFallBackLibraryPath],
        [NSString stringWithFormat:@"xrandr -s %@x%@ > /dev/null 2>&1",xRes,yRes]];
	system([[command componentsJoinedByString:@" "] UTF8String]);
}

- (NSString *)getScreenResolution
{
	CGRect screenFrame = CGDisplayBounds(kCGDirectMainDisplay);
	CGSize screenSize  = screenFrame.size;
	return [NSString stringWithFormat:@"%.0f %.0f",screenSize.width,screenSize.height];
}

- (NSArray *)makePIDArray:(NSString *)processToLookFor
{
	NSString *resultString = [NSString stringWithFormat:@"00000\n%@",[self systemCommand:[NSString stringWithFormat:@"ps axc|awk \"{if (\\$5==\\\"%@\\\") print \\$1}\"",processToLookFor]]];
	return [resultString componentsSeparatedByString:@"\n"];
}

- (NSString *)getNewPid:(NSString *)processToLookFor from:(NSArray *)firstPIDlist confirm:(bool)confirm_pid;
{
    //do loop compare to find correct PID, try 8 times, doubling the delay each try ... up to 102.2 secs of total waiting
    int i = 0;
    int sleep_duration = 200000; // start off w/ 0.2 secs and double each iteration

    //re-usable array
    NSMutableArray *secondPIDlist = [[NSMutableArray alloc] init];
    for (i = 0; i < 9; ++i) {
        // log delay if it will take longer than 1 second
        if (sleep_duration / 1000000 > 1) {
            NSLog(@"Wineskin: Waiting %d seconds for %@ to start.", sleep_duration / 1000000, processToLookFor);
        }

        // sleep a bit before checking for current pid list
        usleep(sleep_duration);
        sleep_duration = sleep_duration * 2;
        [secondPIDlist removeAllObjects];
        [secondPIDlist addObjectsFromArray:[self makePIDArray:processToLookFor]];
        for (NSString *secondPIDlistItem in secondPIDlist) {
            if ([secondPIDlistItem isEqualToString:wrapperBundlePID]) {
                continue;
            }
            BOOL match = NO;
            for (NSString *firstPIDlistItem in firstPIDlist) {
                if ([secondPIDlistItem isEqualToString:firstPIDlistItem]) {
                    match = YES;
                }
            }
            if (!match) {
                if (!confirm_pid) {
                    return secondPIDlistItem;
                } else {
                    // sleep another duration (+ 0.25 secs) to confirm pid is still valid
                    sleep_duration = (sleep_duration / 2) + 250000;
                    
                    // log delay if it will take longer than 1 second
                    if (sleep_duration / 1000000 > 1) {
                        NSLog(@"Wineskin: Waiting %d more seconds to confirm PID (%@) is valid for %@.", sleep_duration / 1000000, secondPIDlistItem, processToLookFor);
                    }

                    // sleep a bit before checking for current pid list
                    usleep(sleep_duration);

                    // return PID if still valid
                    if ([self isPID:secondPIDlistItem named:processToLookFor]) {
                        return secondPIDlistItem;
                    }
                }

                // pid isn't valid
                NSLog(@"Wineskin: Found invalid %@ pid: %@.", processToLookFor, secondPIDlistItem);
            }
        }
    }
    NSLog(@"Wineskin: Could not find PID for %@", processToLookFor);
    return @"-1";
}

-(NSString*)createWrapperHomeSymlinkFolder:(NSString*)folderName forMacFolder:(NSString*)macFolder
{
    NSString* defaultPath = [NSString stringWithFormat:@"$HOME/%@",macFolder];
    NSString* origSymlink = [[self.portManager plistObjectForKey:[NSString stringWithFormat:@"Symlink %@",folderName]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (origSymlink == nil || origSymlink.length < 1) {
        origSymlink = defaultPath;
    }

    NSMutableString *symlink = [[NSMutableString alloc] initWithString:origSymlink];
    [symlink replaceOccurrencesOfString:@"$HOME" withString:NSHomeDirectory() options:NSLiteralSearch
                                  range:NSMakeRange(0, symlink.length)];

    if (![fm directoryExistsAtPath:symlink]) {
        [fm createDirectoryAtPath:symlink withIntermediateDirectories:YES];
    }
    BOOL error = ![fm directoryExistsAtPath:symlink];
    if (error) {
        NSString* macPath = [NSString stringWithFormat:@"%@/%@",NSHomeDirectory(),macFolder];
        NSLog(@"ERROR: \"%@\" requested to be linked to \"%@\", but folder does not exist and could not be created. Using \"%@\" instead.",symlink,folderName,macPath);
        return macPath;
    }

    return symlink;
}

-(void)createWrapperHomeFolder:(NSString*)folderName withSymlinkTo:(NSString*)symlink
{
    NSString* folderPath = [NSString stringWithFormat:@"%@/drive_c/users/Wineskin/%@",winePrefix,folderName];

    if (symlink) {
        [fm removeItemAtPath:folderPath];
        [fm createSymbolicLinkAtPath:folderPath withDestinationPath:symlink error:nil];
        [self systemCommand:[NSString stringWithFormat:@"chmod -h 777 \"%@\"",folderPath]];
    } else {
        [fm createDirectoryAtPath:folderPath withIntermediateDirectories:NO];
    }
}

- (void)setUserFolders:(BOOL)doSymlinks
{
    NSString* symlinkMyDocuments = [self createWrapperHomeSymlinkFolder:@"Documents" forMacFolder:@"Documents"];
    NSString* symlinkDesktop     = [self createWrapperHomeSymlinkFolder:@"Desktop"   forMacFolder:@"Desktop"];
    NSString* symlinkDownloads   = [self createWrapperHomeSymlinkFolder:@"Downloads" forMacFolder:@"Downloads"];
    NSString* symlinkMyVideos    = [self createWrapperHomeSymlinkFolder:@"Videos"    forMacFolder:@"Movies"];
    NSString* symlinkMyMusic     = [self createWrapperHomeSymlinkFolder:@"Music"     forMacFolder:@"Music"];
    NSString* symlinkMyPictures  = [self createWrapperHomeSymlinkFolder:@"Pictures"  forMacFolder:@"Pictures"];
    NSString* symlinkTemplates   = [self createWrapperHomeSymlinkFolder:@"Templates" forMacFolder:@"Templates"];

    //set the symlinks
	if ([fm fileExistsAtPath:[NSString stringWithFormat:@"%@/drive_c/users/Wineskin",winePrefix]]) {
        if (!doSymlinks) symlinkMyDocuments = nil;
        [self createWrapperHomeFolder:@"Documents" withSymlinkTo:symlinkMyDocuments];

        if (!doSymlinks) symlinkDesktop = nil;
        [self createWrapperHomeFolder:@"Desktop" withSymlinkTo:symlinkDesktop];

        if (!doSymlinks) symlinkDownloads = nil;
        [self createWrapperHomeFolder:@"Downloads" withSymlinkTo:symlinkDownloads];

        if (!doSymlinks) symlinkMyVideos = nil;
        [self createWrapperHomeFolder:@"Videos" withSymlinkTo:symlinkMyVideos];

        if (!doSymlinks) symlinkMyMusic = nil;
        [self createWrapperHomeFolder:@"Music" withSymlinkTo:symlinkMyMusic];

        if (!doSymlinks) symlinkMyPictures = nil;
        [self createWrapperHomeFolder:@"Pictures" withSymlinkTo:symlinkMyPictures];

        if (!doSymlinks) symlinkTemplates = nil;
        [self createWrapperHomeFolder:@"Templates" withSymlinkTo:symlinkTemplates];
	}

    NSString* usersFolder     = [NSString stringWithFormat:@"%@/drive_c/users/%@",winePrefix,NSUserName()];
    NSString* crossoverFolder = [NSString stringWithFormat:@"%@/drive_c/users/crossover",winePrefix];

    for (NSString* folder in @[usersFolder, crossoverFolder]) {
        [fm createSymbolicLinkAtPath:folder withDestinationPath:@"Wineskin" error:nil];
        [self systemCommand:[NSString stringWithFormat:@"chmod -h 777 \"%@\"",folder]];
    }
}

- (void)fixWinePrefixForCurrentUser
{
	// changing owner just fails, need this to work for normal users without admin password on the fly.
	// Needed folders are set to 777, so just make a new resources folder and move items, should always work.
	// NSFileManager changing posix permissions still failing to work right, using chmod as a system command

	//make ResoTemp
	[fm createDirectoryAtPath:[NSString stringWithFormat:@"%@/ResoTemp",contentsFold] withIntermediateDirectories:NO];

    //move everything from Resources to ResoTemp
	NSArray *tmpy = [fm contentsOfDirectoryAtPath:winePrefix];
	for (NSString *item in tmpy) {
		[fm moveItemAtPath:[NSString stringWithFormat:@"%@/Resources/%@",contentsFold,item]
                    toPath:[NSString stringWithFormat:@"%@/ResoTemp/%@",contentsFold,item]];
    }

    //delete Resources
	[fm removeItemAtPath:winePrefix];

    //rename ResoTemp to Resources
	[fm moveItemAtPath:[NSString stringWithFormat:@"%@/ResoTemp",contentsFold]
                toPath:[NSString stringWithFormat:@"%@/Resources",contentsFold]];

    //fix Resources to 777
	[self systemCommand:[NSString stringWithFormat:@"chmod -R 777 \"%@\"",winePrefix]];
}

- (void)setGpuInfoVendorID:(NSString*)nvendorID deviceID:(NSString*)ndeviceID memorySize:(NSString*)nVRAM
{
    //if user.reg doesn't exist, don't do anything
    if (!([fm fileExistsAtPath:[NSString stringWithFormat:@"%@/user.reg",winePrefix]])) {
        return;
    }

    NSString* direct3dHeader = @"[Software\\\\Wine\\\\Direct3D]";
    NSMutableString* direct3dReg = [[self.portManager getRegistryEntry:direct3dHeader fromRegistryFileNamed:USER_REG] mutableCopy];

    [self.portManager setValue:nVRAM     forKey:@"VideoMemorySize"  atRegistryEntryString:direct3dReg];
    [self.portManager setValue:ndeviceID forKey:@"VideoPciDeviceID" atRegistryEntryString:direct3dReg];
    [self.portManager setValue:nvendorID forKey:@"VideoPciVendorID" atRegistryEntryString:direct3dReg];

    [self.portManager deleteRegistry:direct3dHeader fromRegistryFileNamed:USER_REG];
    [self.portManager addRegistry:[NSString stringWithFormat:@"%@\n%@\n",direct3dHeader,direct3dReg] fromRegistryFileNamed:USER_REG];

    [self systemCommand:[NSString stringWithFormat:@"chmod 666 \"%@/user.reg\"",winePrefix]];
}

- (void)tryToUseGPUInfo
{
    VMMVideoCard* vc = [VMMVideoCardManager bestInternalVideoCard];

    NSMutableString *deviceID = [vc.deviceID mutableCopy];
    NSMutableString *vendorID = [vc.vendorID mutableCopy];
    NSString *VRAM = [NSString stringWithFormat:@"%d",vc.memorySizeInMegabytes.intValue];

    //need to strip 0x off the front of deviceID and vendorID, and pad with 0's in front until its a total of 8 digits long.
    if (vendorID) {
        vendorID = [[vendorID substringFromIndex:2] mutableCopy];

        while (vendorID.length < 8) {
            [vendorID insertString:@"0" atIndex:0];
        }
    }
    if (deviceID) {
        deviceID = [[deviceID substringFromIndex:2] mutableCopy];

        while ([deviceID length] < 8) {
            [deviceID insertString:@"0" atIndex:0];
        }
    }

    NSString* nVRAM = VRAM ? [NSString stringWithFormat:@"\"%@\"",VRAM] : nil;
    NSString* ndeviceID = deviceID ? [NSString stringWithFormat:@"dword:%@",deviceID] : nil;
    NSString* nvendorID = vendorID ? [NSString stringWithFormat:@"dword:%@",vendorID] : nil;

    [self setGpuInfoVendorID:nvendorID deviceID:ndeviceID memorySize:nVRAM];
}

- (void)removeGPUInfo
{
    [self setGpuInfoVendorID:nil deviceID:nil memorySize:nil];
}

- (BOOL)checkToUseMacDriver
{
    //TODO: This is how to check engine via NSWineskinEngine
    return [NSPortDataLoader macDriverIsEnabledAtPort:self.portManager];
}

- (NSArray *)readFileToStringArray:(NSString *)theFile
{
	return [[NSString stringWithContentsOfFile:theFile encoding:NSUTF8StringEncoding] componentsSeparatedByString:@"\n"];
}

- (void)writeStringArray:(NSArray *)theArray toFile:(NSString *)theFile
{
	[fm removeItemAtPath:theFile];
	[[theArray componentsJoinedByString:@"\n"] writeToFile:theFile atomically:YES encoding:NSUTF8StringEncoding];
	[self systemCommand:[NSString stringWithFormat:@"chmod 777 \"%@\"",theFile]];
}

- (BOOL)isPID:(NSString *)pid named:(NSString *)name
{
    if ([pid isEqualToString:@""]) {
        NSLog(@"INVALID PID SENT TO isPID!!!");
    }
	if ([[self systemCommand:[NSString stringWithFormat:@"ps -p \"%@\" | grep \"%@\"",pid,name]] length] < 1) {
        return NO;
    }
	return YES;
}

- (BOOL)isWineserverRunning
{
    return ([[self systemCommand:[NSString stringWithFormat:@"killall -0 \"wineserver\" 2>&1"]] length] < 1);
}

- (void)wineBootStuckProcess
{
    //kills Wine if a Wine process is stuck with 90%+ usage.  Very hacky work around
    usleep(5000000);
    int loopCount = 30;
    int i;
    int hit = 0;
    for (i=0; i < loopCount; ++i) {
        NSArray *resultArray = [[self systemCommand:@"ps -eo pcpu,pid,args | grep \"wineboot.exe --init\""] componentsSeparatedByString:@" "];
        if ([[resultArray objectAtIndex:1] floatValue] > 90.0) {
            if (hit > 5) {
                usleep(5000000);
                char *tmp;
                kill((pid_t)(strtoimax([[resultArray objectAtIndex:2] UTF8String], &tmp, 10)), 9);
                break;
            } else {
                ++hit;
            }
        }
        usleep(1000000);
    }
}

- (void)startWine:(WineStart *)wineStartInfo
{
    @autoreleasepool
    {
        NSString *wssCommand = [wineStartInfo getWssCommand];
        //make sure the /tmp/.wine-uid folder and lock file are correct since Wine is buggy about it
        if (primaryRun) {
            NSDictionary *info = [fm attributesOfItemAtPath:winePrefix error:nil];
            NSString *uid = [NSString stringWithFormat: @"%d", getuid()];
            NSString *inode = [NSString stringWithFormat:@"%lx", (unsigned long)[info[NSFileSystemFileNumber] unsignedIntegerValue]];
            NSString *deviceId = [NSString stringWithFormat:@"%lx", (unsigned long)[info[NSFileSystemNumber] unsignedIntegerValue]];
            NSString *pathToWineLockFolder = [NSString stringWithFormat:@"/tmp/.wine-%@/server-%@-%@",uid,deviceId,inode];

            if ([fm fileExistsAtPath:pathToWineLockFolder]) {
                [fm removeItemAtPath:pathToWineLockFolder];
            }
            [fm createDirectoryAtPath:pathToWineLockFolder withIntermediateDirectories:YES];
            [self systemCommand:[NSString stringWithFormat:@"chmod -R 700 \"/tmp/.wine-%@\"",uid]];
        }

        if ([wineStartInfo isNonStandardRun]) {
            NSString *wineDebugLine = @"err-all,warn-all,fixme-all,trace-all";

            //remove the .update-timestamp file
            [fm removeItemAtPath:[NSString stringWithFormat:@"%@/.update-timestamp",winePrefix]];

            NSString *gecko = @"";
            if ( [[self.portManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_DISABLE_GECKO] intValue] == 1) {
                gecko = @"mshtml";
            }

            NSString *mono = @"";
            if ( [[self.portManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_DISABLE_MONO] intValue] == 1 ) {
                mono = @"mscoree";
            }

            if ([wssCommand isEqualToString:@"WSS-wineboot"])
            //launch monitor thread for killing stuck wineboots (work-a-round Macdriver bug for 1.5.28)
            [NSThread detachNewThreadSelector:@selector(wineBootStuckProcess) toTarget:self withObject:nil];
            NSArray* command = @[
                [NSString stringWithFormat:@"export WINEDLLOVERRIDES=\"%@,%@=\";",gecko,mono],
                [NSString stringWithFormat:@"export WINEDEBUG=%@;",wineDebugLine],
                [NSString stringWithFormat:@"export PATH=\"%@/:/usr/bin:/bin:/usr/sbin:/sbin\";",pathToWineBinFolder],
                [NSString stringWithFormat:@"export WINEPREFIX=\"%@\";",winePrefix],
                [NSString stringWithFormat:@"DYLD_FALLBACK_LIBRARY_PATH=\"%@\"",dyldFallBackLibraryPath],
                [NSString stringWithFormat:@"%@",HIDEBOOT],
                [NSString stringWithFormat:@"%@ wineboot -u",wineExecutable]];
            [self systemCommand:[command componentsJoinedByString:@" "]];
            usleep(3000000);

            // apparently wineboot doesn't wait for the prefix to be ready
            // (to reproduce, run 'wine wineboot ; ls ~/.wine' it will often return before the .reg files are present
            // https://github.com/Winetricks/winetricks/commit/e9e9f9b6f0bb4289dbf5e6c2d5642c029c547eff
            NSArray* postcommand = @[
                [NSString stringWithFormat:@"export WINEDEBUG=%@;",wineDebugLine],
                [NSString stringWithFormat:@"export PATH=\"%@/:/usr/bin:/bin:/usr/sbin:/sbin\";",pathToWineBinFolder],
                [NSString stringWithFormat:@"export WINEPREFIX=\"%@\";",winePrefix],
                [NSString stringWithFormat:@"DYLD_FALLBACK_LIBRARY_PATH=\"%@\"",dyldFallBackLibraryPath],
                [NSString stringWithFormat:@"wineserver -w"]];
            [self systemCommand:[postcommand componentsJoinedByString:@" "]];

            //only runs on build new wrapper, and rebuild
            if ([wssCommand isEqualToString:@"WSS-wineprefixcreate"]) {
                //make sure windows/profiles is using users folder
                NSString* profilesFolderPath = [NSString stringWithFormat:@"%@/drive_c/windows/profiles",winePrefix];
                [fm removeItemAtPath:profilesFolderPath];
                [fm createSymbolicLinkAtPath:profilesFolderPath withDestinationPath:@"../users" error:nil];
                [self systemCommand:[NSString stringWithFormat:@"chmod -h 777 \"%@\"",profilesFolderPath]];

                //rename new user folder to Wineskin and make symlinks
                NSString* usersUserFolderPath = [NSString stringWithFormat:@"%@/drive_c/users/%@",winePrefix,NSUserName()];
                NSString* usersWineskinFolderPath = [NSString stringWithFormat:@"%@/drive_c/users/Wineskin",winePrefix];
                NSString* usersCrossOverFolderPath = [NSString stringWithFormat:@"%@/drive_c/users/crossover",winePrefix];

                if ([fm fileExistsAtPath:usersUserFolderPath]) {
                    [fm moveItemAtPath:usersUserFolderPath toPath:usersWineskinFolderPath];
                    [fm createSymbolicLinkAtPath:usersUserFolderPath withDestinationPath:@"Wineskin" error:nil];
                    [self systemCommand:[NSString stringWithFormat:@"chmod -h 777 \"%@\"",usersUserFolderPath]];
                } else if ([fm fileExistsAtPath:usersCrossOverFolderPath]) {
                    [fm moveItemAtPath:usersCrossOverFolderPath toPath:usersWineskinFolderPath];
                    [fm createSymbolicLinkAtPath:usersCrossOverFolderPath withDestinationPath:@"Wineskin" error:nil];
                    [self systemCommand:[NSString stringWithFormat:@"chmod -h 777 \"%@\"",usersCrossOverFolderPath]];
                //this shouldn't ever happen.. but what the heck
                } else {
                    [fm createDirectoryAtPath:usersWineskinFolderPath withIntermediateDirectories:YES];
                    [fm createSymbolicLinkAtPath:usersUserFolderPath withDestinationPath:@"Wineskin" error:nil];
                    [self systemCommand:[NSString stringWithFormat:@"chmod -h 777 \"%@\"",usersUserFolderPath]];
                }

                //load Wineskin default reg entries
                NSArray* loadRegCommand = @[
                    [NSString stringWithFormat:@"export WINEDEBUG=%@;",wineDebugLine],
                    [NSString stringWithFormat:@"export PATH=\"%@:/usr/bin:/bin:/usr/sbin:/sbin\";",pathToWineBinFolder],
                    [NSString stringWithFormat:@"export WINEPREFIX=\"%@\";",winePrefix],
                    [NSString stringWithFormat:@"DYLD_FALLBACK_LIBRARY_PATH=\"%@\"",dyldFallBackLibraryPath],
                    [NSString stringWithFormat:@"%@ regedit \"%@/Wineskin.app/Contents/Resources/remakedefaults.reg\" > \"/dev/null\" 2>&1",wineExecutable, contentsFold]];
                [self systemCommand:[loadRegCommand componentsJoinedByString:@" "]];
                usleep(5000000);
            }

            NSString* userFolderWindowsPath = [NSString stringWithFormat:@"C:\\users\\%@",NSUserName()];
            NSString* wineskinUserFolderWindowsPath = @"C:\\users\\Wineskin";

            //fix user name entires over to Wineskin
            NSString* userRegPath = [NSString stringWithFormat:@"%@/user.reg",winePrefix];
            NSArray *userReg = [self readFileToStringArray:userRegPath];
            NSMutableArray *newUserReg = [NSMutableArray arrayWithCapacity:userReg.count];
            for (NSString *item in userReg) {
                [newUserReg addObject:[item stringByReplacingOccurrencesOfString:userFolderWindowsPath
                                                                      withString:wineskinUserFolderWindowsPath]];
            }
            [self writeStringArray:newUserReg toFile:userRegPath];
            [self systemCommand:[NSString stringWithFormat:@"chmod 666 \"%@\"",userRegPath]];

            NSString* userDefRegPath = [NSString stringWithFormat:@"%@/userdef.reg",winePrefix];
            NSArray *userDefReg = [self readFileToStringArray:userDefRegPath];
            NSMutableArray *newUserDefReg = [NSMutableArray arrayWithCapacity:userDefReg.count];
            for (NSString *item in userDefReg) {
                [newUserDefReg addObject:[item stringByReplacingOccurrencesOfString:userFolderWindowsPath
                                                                         withString:wineskinUserFolderWindowsPath]];
            }
            [self writeStringArray:newUserDefReg toFile:userDefRegPath];


            // need Temp folder in Wineskin folder
            [fm createDirectoryAtPath:[NSString stringWithFormat:@"%@/drive_c/users/Wineskin/Temp",winePrefix] withIntermediateDirectories:YES];

            // do a chmod on the whole wrapper to 755... shouldn't break anything but should prevent issues.
            // Task Number 3221715 Fix Wrapper Permissions
            //cocoa command don't seem to be working right, but chmod system command works fine.
            // cannot 755 the whole wrapper and then change to 777s or this can break the wrapper for non-Admin users.
            //[self systemCommand:[NSString stringWithFormat:@"chmod 755 \"%@\"",appNameWithPath]];
            // need to chmod 777 on Contents, Resources, and Resources/* for multiuser fix on same machine
            [self systemCommand:[NSString stringWithFormat:@"chmod 777 \"%@\"",contentsFold]];
            [self systemCommand:[NSString stringWithFormat:@"chmod 777 \"%@\"",winePrefix]];
            [self systemCommand:[NSString stringWithFormat:@"chmod 777 \"%@\"",frameworksFold]];
            [self systemCommand:[NSString stringWithFormat:@"chmod 777 \"%@/wine\"",contentsFold]];
            [self systemCommand:[NSString stringWithFormat:@"chmod -R 777 \"%@/drive_c\"",winePrefix]];
            NSArray *tmpy2 = [fm contentsOfDirectoryAtPath:winePrefix];
            for (NSString *item in tmpy2) {
                [self systemCommand:[NSString stringWithFormat:@"chmod 777 \"%@/%@\"",winePrefix,item]];
            }
            NSString* dosdevicesPath = [NSString stringWithFormat:@"%@/dosdevices",winePrefix];
            NSArray *tmpy3 = [fm contentsOfDirectoryAtPath:dosdevicesPath];
            for (NSString *item in tmpy3) {
                [self systemCommand:[NSString stringWithFormat:@"chmod -h 777 \"%@/%@\"",dosdevicesPath,item]];
            }
            return;
        }

        if (primaryRun) { //Normal Wine Run
        }
        NSString *wineDebugLine;
        NSString *wineLogFileLocal = [NSString stringWithFormat:@"%@",wineLogFile];

        if (debugEnabled && !fullScreenOption) { //set log file names, and stuff
            wineDebugLine = [NSString stringWithFormat:@"%@",[wineStartInfo getWineDebugLine]];
        } else if (debugEnabled && fullScreenOption) { //always need a log with x11settings
            NSString *setWineDebugLine = [wineStartInfo getWineDebugLine];
            if ([setWineDebugLine rangeOfString:@"trace+x11settings"].location == NSNotFound) {
                removeX11TraceFromLog = YES;
                wineDebugLine = [NSString stringWithFormat:@"%@,trace+x11settings",setWineDebugLine];
            } else {
                wineDebugLine = setWineDebugLine;
            }
        } else if (!debugEnabled && fullScreenOption) { //need log for reso changes
            wineDebugLine = @"err-all,warn-all,fixme-all,trace+x11settings";
        } else { //this should be rootless with no debug... don't need a log of any type.
            wineLogFileLocal = @"/dev/null";
            wineDebugLine = @"err-all,warn-all,fixme-all,trace-all";
        }

        //fix start.exe line
        NSString *startExeLine = @"";
        if ([wineStartInfo isRunWithStartExe]) {
            startExeLine = @" start /unix";
        }

        //Wine start section
        if ([wssCommand isEqualToString:@"WSS-winetricks"]) {
            if ([[self.portManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_WINETRICKS_NOLOGS] intValue] == 1) {
                wineDebugLine = @"err-all,warn-all,fixme-all,trace-all";
            } else { // Ignore plugplay messages
                wineDebugLine = @"err+all,warn-all,fixme+all,trace-all,-plugplay";
            }

            NSString *silentMode = @"";
            if ([[self.portManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_WINETRICKS_SILENT] intValue] == 1) {
                silentMode = @"-q";
            }

            NSString *forceMode = @"";
            if ([[self.portManager plistObjectForKey:WINESKIN_WRAPPER_PLIST_KEY_WINETRICKS_FORCE] intValue] == 1) {
                forceMode = @"-f";
            }

            NSArray *winetricksCommands = [wineStartInfo getWinetricksCommands];
            if ((winetricksCommands.count == 2 &&  [winetricksCommands[1] isEqualToString:@"list"]) ||
                (winetricksCommands.count == 1 && ([winetricksCommands[0] isEqualToString:@"list"]  ||
                                                   [winetricksCommands[0] hasPrefix:@"list-"])))
            {
                //TODO: Change winetricks to NSArray
                // just getting a list of verbs
                [self systemCommand:[NSString stringWithFormat:@"export WINETRICKS_FALLBACK_LIBRARY_PATH=\"%@\";export WINEDEBUG=%@;cd \"%@/Wineskin.app/Contents/Resources\";export PATH=\"$PWD:%@:/usr/bin:/bin:/usr/sbin:/sbin\";export WINEPREFIX=\"%@\";DYLD_FALLBACK_LIBRARY_PATH=\"%@\" winetricks --no-isolate %@ > \"%@/Logs/WinetricksTemp.log\"",dyldFallBackLibraryPath,wineDebugLine,contentsFold,pathToWineBinFolder,winePrefix,dyldFallBackLibraryPath,[winetricksCommands componentsJoinedByString:@" "],sharedsupportFold]];
            } else {
                [self systemCommand:[NSString stringWithFormat:@"export WINETRICKS_FALLBACK_LIBRARY_PATH=\"%@\";export WINEDEBUG=%@;cd \"%@/Wineskin.app/Contents/Resources\";export PATH=\"$PWD:%@:/usr/bin:/bin:/usr/sbin:/sbin\";export WINEPREFIX=\"%@\";%@DYLD_FALLBACK_LIBRARY_PATH=\"%@\" winetricks %@ %@ --no-isolate \"%@\" > \"%@/Logs/Winetricks.log\" 2>&1",dyldFallBackLibraryPath,wineDebugLine,contentsFold,pathToWineBinFolder,winePrefix,[wineStartInfo getCliCustomCommands],dyldFallBackLibraryPath,forceMode,silentMode,[winetricksCommands componentsJoinedByString:@"\" \""],sharedsupportFold]];
            }
            usleep(5000000); // sometimes it dumps out slightly too fast... just hold for a few seconds
            return;
        }

        if ([wineStartInfo isOpeningFiles]) {
            //start wine with files
            for (NSString *item in [wineStartInfo getFilesToRun]) {

                //don't try to run things xorg sometimes passes back stupidly...
                BOOL breakOut = NO;
                NSArray *breakStrings = @[@"/opt/X11/share/fonts",@"/usr/X11/share/fonts",@"/opt/local/share/fonts",
                        @"/usr/X11/lib/X11/fonts",@"/usr/X11R6/lib/X11/fonts"];

                for (NSString *breakItem in breakStrings) {
                    if ([item hasPrefix:breakItem]) {
                        breakOut = YES;
                        break;
                    }
                }
                if (breakOut) {
                    break;
                }

                if ([item hasPrefix:@"/"]) {
                    NSArray* launchWineCommand = @[
                        [NSString stringWithFormat:@"export WINEDEBUG=%@;",wineDebugLine],
                        [NSString stringWithFormat:@"export PATH=\"%@:/usr/bin:/bin:/usr/sbin:/sbin\";",pathToWineBinFolder],
                        [NSString stringWithFormat:@"export CX_ROOT=\"%@\";",pathToWineFolder],
                        [NSString stringWithFormat:@"export WINEPREFIX=\"%@\";",winePrefix],
                        [NSString stringWithFormat:@"%@cd \"%@\";",[wineStartInfo getCliCustomCommands],[wineStartInfo getWineRunLocation]],
                        [NSString stringWithFormat:@"DYLD_FALLBACK_LIBRARY_PATH=\"%@\"",dyldFallBackLibraryPath],
                        [NSString stringWithFormat:@"GST_PLUGIN_PATH=\"%@\"",gstPluginPath],
                        //[NSString stringWithFormat:@"%@",FENCES],
                        [NSString stringWithFormat:@"%@",RESUME],
                        [NSString stringWithFormat:@"%@",SWIZZLE],
                        [NSString stringWithFormat:@"%@",wineEsync],
                        [NSString stringWithFormat:@"%@",wineMsync],
                        [NSString stringWithFormat:@"%@",metalHUD],
                        [NSString stringWithFormat:@"%@",FASTMATH],
                        [NSString stringWithFormat:@"%@",DOTNET],
                        [NSString stringWithFormat:@"%@ start /unix \"%@\" > \"%@\" 2>&1 &",wineExecutable, item, wineLogFileLocal]];
                   [self systemCommand:[launchWineCommand componentsJoinedByString:@" "]];
                } else {
                     NSArray* launchWineCommand = @[
                         [NSString stringWithFormat:@"export WINEDEBUG=%@;",wineDebugLine],
                         [NSString stringWithFormat:@"export PATH=\"%@:/usr/bin:/bin:/usr/sbin:/sbin\";",pathToWineBinFolder],
                         [NSString stringWithFormat:@"export CX_ROOT=\"%@\";",pathToWineFolder],
                         [NSString stringWithFormat:@"export WINEPREFIX=\"%@\";",winePrefix],
                         [NSString stringWithFormat:@"%@cd \"%@\";",[wineStartInfo getCliCustomCommands],[wineStartInfo getWineRunLocation]],
                         [NSString stringWithFormat:@"DYLD_FALLBACK_LIBRARY_PATH=\"%@\"",dyldFallBackLibraryPath],
                         [NSString stringWithFormat:@"GST_PLUGIN_PATH=\"%@\"",gstPluginPath],
                         //[NSString stringWithFormat:@"%@",FENCES],
                         [NSString stringWithFormat:@"%@",RESUME],
                         [NSString stringWithFormat:@"%@",SWIZZLE],
                         [NSString stringWithFormat:@"%@",wineEsync],
                         [NSString stringWithFormat:@"%@",wineMsync],
                         [NSString stringWithFormat:@"%@",metalHUD],
                         [NSString stringWithFormat:@"%@",FASTMATH],
                         [NSString stringWithFormat:@"%@",DOTNET],
                         [NSString stringWithFormat:@"%@ start \"%@\" > \"%@\" 2>&1 &",wineExecutable, item, wineLogFileLocal]];
                    [self systemCommand:[launchWineCommand componentsJoinedByString:@" "]];
                }
            }
        } else {
            //launch Wine normally
            NSArray* launchWineCommand = @[
                [NSString stringWithFormat:@"export WINEDEBUG=%@;",wineDebugLine],
                [NSString stringWithFormat:@"export PATH=\"%@:$PATH:/opt/local/bin:/opt/local/sbin\";",pathToWineBinFolder],
                [NSString stringWithFormat:@"export CX_ROOT=\"%@\";",pathToWineFolder],
                [NSString stringWithFormat:@"export WINEPREFIX=\"%@\";",winePrefix],
                [NSString stringWithFormat:@"%@cd \"%@\";",[wineStartInfo getCliCustomCommands],[wineStartInfo getWineRunLocation]],
                [NSString stringWithFormat:@"DYLD_FALLBACK_LIBRARY_PATH=\"%@\"",dyldFallBackLibraryPath],
                [NSString stringWithFormat:@"GST_PLUGIN_PATH=\"%@\"",gstPluginPath],
                //[NSString stringWithFormat:@"%@",FENCES],
                [NSString stringWithFormat:@"%@",RESUME],
                [NSString stringWithFormat:@"%@",SWIZZLE],
                [NSString stringWithFormat:@"%@",wineEsync],
                [NSString stringWithFormat:@"%@",wineMsync],
                [NSString stringWithFormat:@"%@",metalHUD],
                [NSString stringWithFormat:@"%@",FASTMATH],
                [NSString stringWithFormat:@"%@",DOTNET],
                [NSString stringWithFormat:@"%@ %@ \"%@\"%@ > \"%@\" 2>&1 &",wineExecutable, startExeLine,[wineStartInfo getWineRunFile],[wineStartInfo getProgramFlags],wineLogFileLocal]];
            system([[launchWineCommand componentsJoinedByString:@" "] UTF8String]);
        }

        NSMutableString *vdResolution = [[wineStartInfo getVdResolution] mutableCopy];
        [vdResolution replaceOccurrencesOfString:@"x" withString:@" " options:NSLiteralSearch range:NSMakeRange(0, vdResolution.length)];
        [wineStartInfo setVdResolution:vdResolution];

        // give wineserver a minute to start up
        for (int s=0; s<480; ++s) {
            if ([self isWineserverRunning]) break;
            usleep(125000);
        }
	}
}

- (void)sleepAndMonitor
{
    NSString* logsFolderPath = [NSString stringWithFormat:@"%@/Logs",sharedsupportFold];
    NSString *timeStampFile = [NSString stringWithFormat:@"%@/.timestamp",logsFolderPath];
	NSMutableString *newScreenReso = [[NSMutableString alloc] init];
    NSString *timestampChecker = [NSString stringWithFormat:@"find \"%@\" -type f -newer \"%@\"",logsFolderPath,timeStampFile];
    if (fullScreenOption) {
        [self systemCommand:[NSString stringWithFormat:@"> \"%@\"",timeStampFile]];
        [self systemCommand:[NSString stringWithFormat:@"> \"%@\"",wineTempLogFile]];
    }
    if (useMacDriver) {
        //use most efficent checking for background loop
    }
	while ([self isWineserverRunning]) {
		//if running in override fullscreen, need to handle resolution changes
		if (fullScreenOption) {
			//compare to timestamp, if log is newer, we need to check it out.
            if ([self systemCommand:timestampChecker]) {
				NSArray *tempArray = [self readFileToStringArray:wineLogFile];
				[self systemCommand:[NSString stringWithFormat:@"> \"%@\"",wineLogFile]];
                [self systemCommand:[NSString stringWithFormat:@"> \"%@\"",timeStampFile]];

				if (debugEnabled) {
                    NSArray *oldDataArray = [self readFileToStringArray:wineTempLogFile];
                    NSMutableArray *temp = [NSMutableArray arrayWithCapacity:[oldDataArray count]];
                    [temp addObjectsFromArray:oldDataArray];
                    [temp addObjectsFromArray:tempArray];
                    [self writeStringArray:temp toFile:wineTempLogFile];
                }

				//now find resolution, and change it
				for (NSString *item in tempArray) {
					if ([item hasPrefix:@"trace:x11settings:X11DRV_ChangeDisplaySettingsEx width="]) {
						[newScreenReso setString:[item substringToIndex:[item rangeOfString:@" bpp="].location]];
                        [newScreenReso replaceOccurrencesOfString:@"trace:x11settings:X11DRV_ChangeDisplaySettingsEx width=" withString:@"" options:NSLiteralSearch range:NSMakeRange(0, [newScreenReso length])];
                        [newScreenReso replaceOccurrencesOfString:@"height=" withString:@"" options:NSLiteralSearch range:NSMakeRange(0, [newScreenReso length])];
						[self setResolution:newScreenReso];
					}
				}
			}
		}
		usleep(1000000); // sleeping in background 1 second
	}
    [fm removeItemAtPath:timeStampFile];
}

- (void)cleanUpAndShutDown
{
    //fix user folders back
    for (NSString* userFolder in @[@"Documents", @"Desktop", @"Downloads", @"Videos", @"Music", @"Pictures", @"Templates"]) {
        NSString* userFolderPath = [NSString stringWithFormat:@"%@/drive_c/users/Wineskin/%@",winePrefix,userFolder];
        if ([[[fm attributesOfItemAtPath:userFolderPath error:nil] fileType] isEqualToString:@"NSFileTypeSymbolicLink"]) {
            [self systemCommand:[NSString stringWithFormat:@"rm \"%@/drive_c/users/Wineskin/%@\"",winePrefix,userFolder]];
        }
    }

	//clean up log files
	if (!debugEnabled) {
		[fm removeItemAtPath:wineLogFile];
		[fm removeItemAtPath:x11LogFile];
	} else if (fullScreenOption) {
        NSArray *tempArray = [self readFileToStringArray:wineLogFile];
        NSArray *oldDataArray = [self readFileToStringArray:wineTempLogFile];
        NSMutableArray *temp = [NSMutableArray arrayWithCapacity:[oldDataArray count]];
        if (removeX11TraceFromLog) {
            for (NSString *item in oldDataArray) {
                if ([item rangeOfString:@"trace:x11settings"].location == NSNotFound) {
                    [temp addObject:item];
                }
            } for (NSString *item in tempArray) {
                if ([item rangeOfString:@"trace:x11settings"].location == NSNotFound) {
                    [temp addObject:item];
                }
            }
        } else {
            [temp addObjectsFromArray:oldDataArray];
            [temp addObjectsFromArray:tempArray];
        }
        [self writeStringArray:temp toFile:wineLogFile];
    }

    //kill wine processes
    NSArray* command = @[
        [NSString stringWithFormat:@"export PATH=\"%@:/usr/bin:/bin:/usr/sbin:/sbin\";",pathToWineBinFolder],
        [NSString stringWithFormat:@"DYLD_FALLBACK_LIBRARY_PATH=\"%@\"",dyldFallBackLibraryPath],
        [NSString stringWithFormat:@"export WINEPREFIX=\"%@\";",winePrefix],@"wineserver -k"];
    [self systemCommand:[command componentsJoinedByString:@" "]];
    usleep(3000000);

    //fixes for multi-user use
    NSArray *tmpy3 = [fm contentsOfDirectoryAtPath:[NSString stringWithFormat:@"%@/dosdevices",winePrefix]];
    for (NSString *item in tmpy3) {
        [self systemCommand:[NSString stringWithFormat:@"chmod -h 777 \"%@/dosdevices/%@\"",winePrefix,item]];
    }

    for (NSString* regFile in @[USERDEF_REG, SYSTEM_REG, USER_REG]) {
        [self systemCommand:[NSString stringWithFormat:@"chmod 666 \"%@/%@.reg\"",winePrefix,regFile]];
    }

    [self systemCommand:[NSString stringWithFormat:@"chmod 666 \"%@/Info.plist\"",contentsFold]];
    [self systemCommand:[NSString stringWithFormat:@"chmod -h 666 \"%@/dosdevices\"",winePrefix]];
    [self systemCommand:[NSString stringWithFormat:@"chmod -h 777 \"%@/dosdevices\"",winePrefix]];
    [self systemCommand:[NSString stringWithFormat:@"chmod -R 666 \"%@/drive_c\"",winePrefix]];
    [self systemCommand:[NSString stringWithFormat:@"chmod -R 777 \"%@/drive_c\"",winePrefix]];
    [self systemCommand:[NSString stringWithFormat:@"chmod -R 777 \"%@/Logs\"",sharedsupportFold]];

    //Fix the windata only folder (created by cxmenu)
    if ([fm fileExistsAtPath:[NSString stringWithFormat:@"%@/windata",winePrefix]]) {
        [self systemCommand:[NSString stringWithFormat:@"chmod -R 777 \"%@/windata\"",winePrefix]];
    }

    //get rid of the preference file
    [fm removeItemAtPath:lockfile];
    [fm removeItemAtPath:tmpFolder];

    //get rid of OS X saved state file
    [fm removeItemAtPath:[NSString stringWithFormat:@"%@/Library/Saved Application State/com.%@%@.wineskin.savedState",NSHomeDirectory(),[[NSNumber numberWithLong:bundleRandomInt1] stringValue],[[NSNumber numberWithLong:bundleRandomInt2] stringValue]]];

    //attempt to clear out any stuck processes in launchd for the wrapper
    //this may prevent -10810 errors on next launch with 10.9, and *shouldn't* hurt anything.
    NSArray *results = [[self systemCommand:[NSString stringWithFormat:@"launchctl list | grep \"%@\"",appName]] componentsSeparatedByString:@"\n"];
    for (NSString *result in results) {
        NSString *entryToRemove = [result getFragmentAfter:@"-" andBefore:nil];
        if (entryToRemove != nil) {
            // clear in front of - in case launchd has it as anonymous, then clear after first [
            entryToRemove = [entryToRemove stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSRange theBracket = [entryToRemove rangeOfString:@"["];
            if (theBracket.location != NSNotFound) {
                entryToRemove = [entryToRemove substringFromIndex:theBracket.location];
            }
            NSLog(@"launchctl remove \"%@\"",entryToRemove);
            [self systemCommand:[NSString stringWithFormat:@"launchctl remove \"%@\"",entryToRemove]];
        }
    }
    [fm removeItemAtPath:tmpwineFolder];
    [NSApp terminate:nil];
}
@end
