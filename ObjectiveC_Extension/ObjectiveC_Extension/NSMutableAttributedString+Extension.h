//
//  NSMutableAttributedString+Extension.h
//  ObjectiveC_Extension
//
//  Created by Vitor Marques de Miranda on 22/02/17.
//  Copyright © 2017 Vitor Marques de Miranda. All rights reserved.
//

#ifndef NSMutableAttributedString_Extension_Class
#define NSMutableAttributedString_Extension_Class

#import <Cocoa/Cocoa.h>

@interface NSMutableAttributedString (VMMMutableAttributedString)

-(instancetype)initWithString:(NSString*)str fontNamed:(NSString*)fontName size:(CGFloat)size;

-(void)replaceOccurrencesOfString:(NSString*)oldString withString:(NSString*)newString;

-(void)addAttribute:(NSString *)name value:(id)value;

-(void)setFontColor:(NSColor*)color range:(NSRange)range;
-(void)setFontColor:(NSColor*)color;
-(void)setFont:(NSFont*)font range:(NSRange)range;
-(void)setFont:(NSFont*)font;

-(void)appendString:(NSString*)aString;

-(BOOL)adjustExpansionToFitWidth:(CGFloat)width;

@end

#endif
