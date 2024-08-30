//
//  NSMutableAttributedString+Extension.m
//  ObjectiveC_Extension
//
//  Created by Vitor Marques de Miranda on 22/02/17.
//  Copyright © 2017 Vitor Marques de Miranda. All rights reserved.
//

#import "NSMutableAttributedString+Extension.h"

#import "VMMComputerInformation.h"

@implementation NSMutableAttributedString (VMMMutableAttributedString)

-(instancetype)initWithString:(NSString*)str fontNamed:(NSString*)fontName size:(CGFloat)size
{
    self = [self initWithString:str];
    
    if (self)
    {
        NSFont* font = [NSFont fontWithName:fontName size:size];
        [self addAttribute:NSFontAttributeName value:font];
    }
    
    return self;
}

-(void)replaceOccurrencesOfString:(NSString*)oldString withString:(NSString*)newString
{
    NSRange downloadRange = [self.string rangeOfString:oldString];
    while (downloadRange.location != NSNotFound && downloadRange.length != 0)
    {
        [self replaceCharactersInRange:downloadRange withString:newString];
        downloadRange = [self.string rangeOfString:oldString];
    }
}

-(void)addAttribute:(NSString *)name value:(id)value
{
    [self addAttribute:name value:value range:NSMakeRange(0, self.length)];
}

-(void)setFontColor:(NSColor*)color range:(NSRange)range
{
    [self addAttribute:NSForegroundColorAttributeName value:color range:range];
}
-(void)setFontColor:(NSColor*)color
{
    [self addAttribute:NSForegroundColorAttributeName value:color];
}
-(void)setFont:(NSFont*)font range:(NSRange)range
{
    [self addAttribute:NSFontAttributeName value:font range:range];
}
-(void)setFont:(NSFont*)font
{
    [self addAttribute:NSFontAttributeName value:font];
}

-(void)appendString:(NSString*)aString
{
    [self appendAttributedString:[[NSAttributedString alloc] initWithString:aString]];
}

-(BOOL)adjustExpansionToFitWidth:(CGFloat)width
{
    CGFloat originalWidth = self.size.width;
    
    BOOL sizeChanged = false;
    CGFloat resizeRate = 0.0;
    
    if (originalWidth > width)
    {
        sizeChanged = true;
        resizeRate = 1 - originalWidth/width;
    }
    
    [self addAttribute:NSExpansionAttributeName value:@(resizeRate)];
    return sizeChanged;
}

@end

