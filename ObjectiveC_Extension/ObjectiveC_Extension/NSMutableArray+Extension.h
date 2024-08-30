//
//  NSMutableArray+Extension.h
//  ObjectiveC_Extension
//
//  Created by Vitor Marques de Miranda on 24/07/2017.
//  Copyright © 2017 Vitor Marques de Miranda. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSMutableArray<ObjectType> (VMMMutableArray)

-(nonnull NSMutableArray*)map:(_Nullable id (^_Nonnull)(id _Nonnull object))newObjectForObject;
-(nonnull NSMutableArray*)filter:(BOOL (^_Nonnull)(id _Nonnull object))newObjectForObject;

-(void)sortBySelector:(SEL _Nonnull)selector inOrder:(NSArray* _Nonnull)order;

@end
