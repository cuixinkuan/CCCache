//
//  CCMemoryCache.h
//  CCCache
//
//  Created by admin on 15/12/17.
//  Copyright © 2015年 CXK. All rights reserved.
//

#import <Foundation/Foundation.h>
/**
 *  CCMemoryCache is a fast in-memory cache that stores key-value pairs
 In contrast to NSDictionary,keys are retained and not copied.
 */

@interface CCMemoryCache : NSObject

#pragma mark - Attributes -
@property (copy)NSString * name;
@property (readonly)NSUInteger totalCount;
@property (readonly)NSUInteger totalCost;

#pragma mark - Limit - 
@property (assign)NSUInteger countLimit;
@property (assign)NSUInteger costLimit;
@property (assign)NSTimeInterval ageLimit;
@property (assign)NSTimeInterval autoTrimInterval;

@property (assign)BOOL shouldRemoveAllObjectsOnMemoryWarning;
@property (assign)BOOL shouldRemoveAllObjectsWhenEnteringBackground;
@property (copy)void(^didReceiveMemoryWarningBlock)(CCMemoryCache * cache);
@property (copy)void(^didEnterBackgroundBlock)(CCMemoryCache * cache);
@property (assign)BOOL releaseOnMainThread;
@property (assign)BOOL releaseAsynchronously;

#pragma mark - Access Methods -

- (BOOL)containsObjectForKey:(id)key;

- (id)objectForKey:(id)key;

- (void)setObject:(id)object forKey:(id)key;

- (void)setObject:(id)object forKey:(id)key withCost:(NSUInteger)cost;

- (void)removeObjectForKey:(id)key;

- (void)removeAllObjects;


#pragma mark - Trim -

- (void)trimToCount:(NSUInteger)count;

- (void)trimToCost:(NSUInteger)cost;

- (void)trimToAge:(NSTimeInterval)age;























@end
