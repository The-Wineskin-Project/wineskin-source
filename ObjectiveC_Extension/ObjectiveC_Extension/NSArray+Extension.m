//
//  NSArray+Extension.m
//  ObjectiveC_Extension
//
//  Created by Vitor Marques de Miranda on 15/05/17.
//  Copyright © 2017 Vitor Marques de Miranda. All rights reserved.
//

#import "NSArray+Extension.h"

#import "NSMutableArray+Extension.h"

@implementation NSArray (VMMArray)

-(nonnull NSMutableArray*)map:(_Nullable id (^_Nonnull)(id _Nonnull object))newObjectForObject
{
    return [[self mutableCopy] map:newObjectForObject];
}
-(nonnull NSMutableArray*)filter:(BOOL (^_Nonnull)(id _Nonnull object))newObjectForObject
{
    return [[self mutableCopy] filter:newObjectForObject];
}

-(nonnull instancetype)forEach:(void (^_Nonnull)(id _Nonnull object))newObjectForObject
{
    for (id object in self) {
        newObjectForObject(object);
    }
    return self;
}

-(nonnull NSArray*)arrayByRemovingRepetitions
{
    return [NSSet setWithArray:self].allObjects;
}

-(nonnull NSArray*)arrayByRemovingObjectsFromArray:(nonnull NSArray*)otherArray
{
    NSMutableArray* newArray = [self mutableCopy];
    
    [newArray removeObjectsInArray:otherArray];
    
    return newArray;
}

-(NSIndexSet* _Nonnull)indexesOfObject:(id _Nonnull)object inRange:(NSRange)range
{
    return [self indexesOfObjectsPassingTest:^BOOL(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop)
    {
        if (idx < range.location)                 return false;
        if (idx >= range.location + range.length) return false;
        return obj == object || [obj isEqual:object];
    }];
}
-(NSIndexSet* _Nonnull)indexesOfObject:(id _Nonnull)object
{
    return [self indexesOfObjectsPassingTest:^BOOL(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop)
    {
        return obj == object || [obj isEqual:object];
    }];
}

-(NSInteger)lastIndexOfObject:(id _Nonnull)object inRange:(NSRange)range
{
    return (NSInteger)[self indexesOfObject:object inRange:range].lastIndex;
}

-(void)differencesFromArray:(NSArray* _Nonnull)otherArray indexPaths:(void (^_Nonnull)(NSArray<NSIndexSet*>* _Nonnull addedIndexes, NSArray<NSIndexSet*>* _Nonnull removedIndexes))indexPaths
{
    NSMutableArray* removedIndexPaths = [[NSMutableArray alloc] init];
    NSMutableArray* addedIndexPaths   = [[NSMutableArray alloc] init];
    NSInteger indexSelf  = self.count - 1;
    NSInteger indexOther = otherArray.count - 1;
    
    while (indexSelf != -1 && indexOther != -1)
    {
        NSInteger nextSelfObjectInOther = [otherArray lastIndexOfObject:[self objectAtIndex:indexSelf]
                                                                inRange:NSMakeRange(0, indexOther + 1)];
        NSInteger nextOtherObjectInSelf = [self lastIndexOfObject:[otherArray objectAtIndex:indexOther]
                                                          inRange:NSMakeRange(0, indexSelf + 1)];
        
        if (nextOtherObjectInSelf == NSNotFound)
        {
            [addedIndexPaths addObject:[NSIndexSet indexSetWithIndex:indexSelf+1]];
            indexOther -= 1;
            continue;
        }
        
        if (nextSelfObjectInOther == NSNotFound)
        {
            [removedIndexPaths addObject:[NSIndexSet indexSetWithIndex:indexSelf]];
            indexSelf -= 1;
            continue;
        }
        
        if (nextOtherObjectInSelf != -1 && nextOtherObjectInSelf == indexSelf)
        {
            indexSelf -=1;
            indexOther -=1;
            continue;
        }
    }
    
    while (indexSelf != -1)
    {
        [removedIndexPaths addObject:[NSIndexSet indexSetWithIndex:indexSelf]];
        indexSelf -= 1;
    }
    
    while (indexOther != -1)
    {
        [addedIndexPaths addObject:[NSIndexSet indexSetWithIndex:0]];
        indexOther -= 1;
    }
    
    indexPaths(addedIndexPaths, removedIndexPaths);
}


@end
