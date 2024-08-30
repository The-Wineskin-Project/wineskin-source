//
//  VMMAlert.m
//  ObjectiveC_Extension
//
//  Created by Vitor Marques de Miranda on 22/02/17.
//  Copyright © 2017 Vitor Marques de Miranda. All rights reserved.
//
//  Reference for runModalWithWindow:
//  https://github.com/adobe/brackets-app/blob/master/src/mac/cefclient/NSAlert%2BSynchronousSheet.m

#import "VMMAlert.h"

#import "VMMComputerInformation.h"
#import "NSBundle+Extension.h"
#import "NSThread+Extension.h"
#import "NSMutableAttributedString+Extension.h"

#import "VMMLogUtility.h"
#import "VMMLocalizationUtility.h"

#define ALERT_WITH_ATTRIBUTED_MESSAGE_PARAGRAPH_SPACING  2.0f
#define ALERT_WITH_ATTRIBUTED_MESSAGE_WIDTH_MARGIN       50
#define ALERT_WITH_ATTRIBUTED_MESSAGE_WIDTH_LIMIT_MARGIN 200

#define ALERT_WITH_BUTTON_OPTIONS_BUTTONS_LATERAL       0
#define ALERT_WITH_BUTTON_OPTIONS_BUTTONS_SPACE         10
#define ALERT_WITH_BUTTON_OPTIONS_ICON_WIDTH            80
#define ALERT_WITH_BUTTON_OPTIONS_ICON_HEIGHT           80
#define ALERT_WITH_BUTTON_OPTIONS_ICON_BORDER_WITH_TEXT 30
#define ALERT_WITH_BUTTON_OPTIONS_ICON_BORDER           10
#define ALERT_WITH_BUTTON_OPTIONS_ICON_IMAGE_BORDER     10
#define ALERT_WITH_BUTTON_OPTIONS_ICONS_AT_X            3

#define ALERT_WITH_BUTTON_OPTIONS_WINDOW_MIN_X_MARGIN   105
#define ALERT_WITH_BUTTON_OPTIONS_WINDOW_MAX_X_MARGIN   18
#define ALERT_WITH_BUTTON_OPTIONS_WINDOW_X_EXTRA_MARGIN 40

#define INPUT_DIALOG_MESSAGE_FIELD_FRAME NSMakeRect(0, 0, 260, 24)

#define ALERT_ICON_SIZE 512

@interface NSImage (VMMImageForAlert)
@end

@implementation NSImage (VMMImageForAlert)
-(NSImage*)getTintedImageWithColor:(NSColor*)color
{
    NSImage* tinted;
    
    @autoreleasepool
    {
        tinted = [[NSImage alloc] initWithSize:self.size];
        [tinted lockFocus];
        
        NSRect imageRect = NSMakeRect(0, 0, self.size.width, self.size.height);
        [self drawInRect:imageRect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
        
        [color set];
        NSRectFillUsingOperation(imageRect, NSCompositeSourceAtop);
        
        [tinted unlockFocus];
    }
    
    return tinted;
}
+(NSImage*)stopProgressIcon
{
    NSImage* icon = [NSImage imageNamed:NSImageNameStopProgressFreestandingTemplate];
    [icon setSize:NSMakeSize(ALERT_ICON_SIZE, ALERT_ICON_SIZE)];
    return [icon getTintedImageWithColor:[NSColor redColor]];
}
+(NSImage*)cautionIcon
{
    NSImage* icon = [NSImage imageNamed:NSImageNameCaution];
    [icon setSize:NSMakeSize(ALERT_ICON_SIZE, ALERT_ICON_SIZE)];
    return icon;
}
@end

@implementation VMMAlert

+(NSString*)titleForAlertType:(VMMAlertType)alertType
{
    switch (alertType)
    {
        case VMMAlertTypeSuccess:
            return VMMLocalizedString(@"Success");
            
        case VMMAlertTypeWarning:
            return VMMLocalizedString(@"Warning");
            
        case VMMAlertTypeError:
            return VMMLocalizedString(@"Error");
            
        case VMMAlertTypeCritical:
            return VMMLocalizedString(@"Error");
            
        case VMMAlertTypeCustom:
        default: break;
    }
    
    return [[NSBundle mainBundle] bundleName];
}
-(void)setIconWithAlertType:(VMMAlertType)alertType
{
    switch (alertType)
    {
        case VMMAlertTypeWarning:
            [self setAlertStyle:NSCriticalAlertStyle];
            break;
            
        case VMMAlertTypeError:
            [self setIcon:[NSImage cautionIcon]];
            break;
            
        case VMMAlertTypeCritical:
            [self setIcon:[NSImage stopProgressIcon]];
            break;
            
        default: break;
    }
}

-(IBAction)BE_stopSynchronousSheet:(id)sender
{
    NSUInteger clickedButtonIndex = [[self buttons] indexOfObject:sender];
    NSInteger modalCode = NSAlertFirstButtonReturn + clickedButtonIndex;
    [NSApp stopModalWithCode:modalCode];
}
-(void)BE_beginSheetModalForWindow:(NSWindow *)aWindow
{
    [self beginSheetModalForWindow:aWindow modalDelegate:nil didEndSelector:nil contextInfo:nil];
}

static NSWindow* _alertsWindow;
static NSWindow* _temporaryAlertsWindow;
static int _temporaryCounter;
+(NSWindow*)modalsWindow
{
    if (_temporaryCounter > 0)
    {
        _temporaryCounter--;
        return _temporaryAlertsWindow;
    }
    
    return _alertsWindow;
}

-(NSUInteger)runModalWithWindow
{
    NSWindow* window = [VMMAlert modalsWindow];
    NSInteger modalCode;
    
    if (window != nil)
    {
        for (NSButton *button in self.buttons)
        {
            [button setTarget:self];
            [button setAction:@selector(BE_stopSynchronousSheet:)];
        }
        
        [self performSelectorOnMainThread:@selector(BE_beginSheetModalForWindow:) withObject:window waitUntilDone:YES];
        
        modalCode = [NSApp runModalForWindow:[self window]];
        
        [NSApp performSelectorOnMainThread:@selector(endSheet:) withObject:[self window] waitUntilDone:YES];
        [[self window] performSelectorOnMainThread:@selector(orderOut:) withObject:self waitUntilDone:YES];
        
        return modalCode;
    }
    else
    {
        modalCode = [self runModal];
    }
    
    switch (modalCode)
    {
        case -1000: // NSModalResponseStop
        case -1001: // NSModalResponseAbort
        case 0:     // NSModalResponseCancel
            
            // Selecting last button, which is supposed to be the Cancel button, or a Ok button in a single button dialog
            modalCode = NSAlertFirstButtonReturn + ((self.buttons.count > 0) ? (self.buttons.count - 1) : 0);
            break;
            
        case 1:     // NSModalResponseOK
            
            // Selecting first button, which is supposed to be the confirmation button, or a Ok button in a single button dialog
            modalCode = NSAlertFirstButtonReturn;
            break;
            
        default:
            break;
    }
    
    return modalCode;
}

+(NSUInteger)runThreadSafeModalWithAlert:(VMMAlert* (^)(void))alert
{
    if ([NSThread isMainThread])
    {
        return [alert() runModalWithWindow];
    }
    
    NSCondition* lock = [[NSCondition alloc] init];
    __block NSUInteger value;
    
    [NSThread dispatchBlockInMainQueue:^
    {
        value = [alert() runModalWithWindow];
        
        [lock signal];
    }];
    
    [lock lock];
    [lock wait];
    [lock unlock];
    
    return value;
}

+(void)showAlertOfType:(VMMAlertType)alertType withMessage:(NSString*)message
{
    @autoreleasepool
    {
        NSString* alertTitle = [self titleForAlertType:alertType];
        
        [self showAlertWithTitle:alertTitle message:message andSettings:^(VMMAlert* alert)
        {
            [alert setIconWithAlertType:alertType];
        }];
    }
}
+(void)showAlertWithTitle:(NSString*)title message:(NSString*)message andSettings:(void (^)(VMMAlert* alert))optionsForAlert
{
    [self runThreadSafeModalWithAlert:^VMMAlert *
    {
        VMMAlert* msgBox = [[VMMAlert alloc] init];
        [msgBox setMessageText:title];
        [msgBox addButtonWithTitle:VMMLocalizedString(@"OK")];
        if (message != nil) [msgBox setInformativeText:message];
        
        if (optionsForAlert != nil) optionsForAlert(msgBox);
        
        return msgBox;
    }];
}

+(void)showAlertWithTitle:(NSString*)title subtitle:(NSString*)subtitle andAttributedMessage:(NSAttributedString*)message withWidth:(CGFloat)fixedWidth
{
    __block NSTextView* informativeText = [[NSTextView alloc] init];
    [informativeText setBackgroundColor:[NSColor clearColor]];
    [informativeText.textStorage setAttributedString:message];
    [informativeText setEditable:false];
    
    NSMutableParagraphStyle *paragrapStyle = [[NSMutableParagraphStyle alloc] init];
    [paragrapStyle setParagraphSpacing:ALERT_WITH_ATTRIBUTED_MESSAGE_PARAGRAPH_SPACING];
    [informativeText.textStorage addAttribute:NSParagraphStyleAttributeName value:paragrapStyle];
    
    CGFloat width = fixedWidth;
    if (width < 0.01) {
        width = informativeText.textStorage.size.width + ALERT_WITH_ATTRIBUTED_MESSAGE_WIDTH_MARGIN;
    }
    
    CGFloat screenLimit = [[NSScreen mainScreen] visibleFrame].size.width - ALERT_WITH_ATTRIBUTED_MESSAGE_WIDTH_LIMIT_MARGIN;
    if (width > screenLimit) width = screenLimit;
    [informativeText setFrame:NSMakeRect(0, 0, width, informativeText.textStorage.size.height)];
    
    [self showAlertWithTitle:title message:subtitle andSettings:^(VMMAlert *alert)
    {
        [alert setAccessoryView:informativeText];
    }];
}

+(BOOL)showBooleanAlertOfType:(VMMAlertType)alertType withMessage:(NSString*)message highlighting:(BOOL)highlight
{
    BOOL result;
    
    @autoreleasepool
    {
        NSString* alertTitle = [self titleForAlertType:alertType];
        
        result = [self showBooleanAlertWithTitle:alertTitle message:message highlighting:highlight withSettings:^(VMMAlert* alert)
        {
            [alert setIconWithAlertType:alertType];
        }];
    }
    
    return result;
}
+(BOOL)showBooleanAlertWithTitle:(NSString*)title message:(NSString*)message highlighting:(BOOL)highlight withSettings:(void (^)(VMMAlert* alert))optionsForAlert
{
    BOOL value = !highlight;
    NSString* defaultButton;
    NSString* alternateButton;
    
    if (highlight)
    {
        defaultButton = VMMLocalizedString(@"Yes");
        alternateButton = VMMLocalizedString(@"No");
    }
    else
    {
        defaultButton = VMMLocalizedString(@"No");
        alternateButton = VMMLocalizedString(@"Yes");
    }
    
    NSUInteger alertResult = [self runThreadSafeModalWithAlert:^VMMAlert *
    {
        VMMAlert* alert = [[VMMAlert alloc] init];
        [alert setMessageText:title != nil ? title : @""];
        [alert addButtonWithTitle:defaultButton];
        [alert addButtonWithTitle:alternateButton];
        [alert setInformativeText:message];
        optionsForAlert(alert);
        return alert;
    }];
    
    if (alertResult == NSAlertFirstButtonReturn) value = highlight;
    return value;
}

@end

