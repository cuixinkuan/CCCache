//
//  CCCache.h
//  CCCache
//
//  Created by admin on 16/1/8.
//  Copyright © 2016年 CXK. All rights reserved.
//

#import <Foundation/Foundation.h>

#if __has_include(<CCCache/CCCache.h>)

FOUNDATION_EXPORT double CCCacheVersionNumber;
FOUNDATION_EXPORT const unsigned char CCCacheVersionString[];
#import <CCCache/CCMemoryCache.h>
#import <CCCache/CCDiskCache.h>
#import <CCCache/CCKVStorage.h>
#elif __has_include(<CCWebImage/CCCache.h>)
#else
#import "CCMemoryCache.h"
#import "CCDiskCache.h"
#import "CCKVStorage.h"
#endif

/**
 *  'CCCaxhe' is a thread safe key-value cache.
 It use 'CCMemoryCache' to store objects in a small and fast memory cache, and use 'CCDiskCache' to persisting objects to a large and slow disk cache.
 See 'CCMemoryCache' and 'CCDiskCache' for more information.
 */
@interface CCCache : NSObject

@property (copy,readonly) NSString * name;
@property (strong,readonly) CCMemoryCache * memoryCache;
@property (strong,readonly) CCDiskCache * diskCache;

/**
 *  Create a new instance with the specified name.
 Multipe instances with the same name will make the cache unstable.
 */
- (instancetype)initWithName:(NSString *)name;
/**
 *  Designated Initializer
 */
- (instancetype)initWithPath:(NSString *)path NS_DESIGNATED_INITIALIZER;

- (instancetype)init UNAVAILABLE_ATTRIBUTE;
- (instancetype)new UNAVAILABLE_ATTRIBUTE;

#pragma mark - Access Methods - 
/**
 *  Return a boolean value that indicates whether a given key is in cache.
 *
 *  @param key
 *
 *  @return whether the key is in cache.
 */
- (BOOL)containsObjectForKey:(NSString *)key;
/**
 *  Return a boolean value that indicates whether a given key is in cache.
 *  This method returns immediately and invoke the passed block in background queue when the operation finished.
 *  @param key   a string, if nil , just return NO.
 *  @param block a block which will be invoked in background queue when finised.
 */
- (void)containsObjectForKey:(NSString *)key withBlock:(void(^)(NSString * key,BOOL contains))block;
/**
 *  Returns the value associated eith a given key.
 *  This method may blocks the calling thread until file read finished.
 *  @param key  a string, if nil , just return nil.
 *
 *  @return the value associated with key or nil if no value is associated with key.
 */
- (id<NSCoding>)objectForKey:(NSString *)key;
/**
 *  Returns the value associated eith a given key.
 *  This method returns immediately and invoke the passed block in background queue when the operation finished.
 *  @param key   a string, if nil , just return nil.
 *  @param block a block which will be invoked in background queue when finised.
 */
- (void)objectForKey:(NSString *)key withBlock:(void(^)(NSString * key,id<NSCoding> object))block;

- (void)setObject:(id<NSCoding>)object forKey:(NSString *)key;

- (void)setObject:(id<NSCoding>)object forKey:(NSString *)key withBlock:(void (^)(void))block;

- (void)removeObjectForKey:(NSString *)key;

- (void)removeObjectForKey:(NSString *)key withBlock:(void(^)(NSString * key))block;

- (void)removeAllObjects;

- (void)removeAllObjectsWithBlock:(void(^)(void))block;
/**
 *  Empties the cache with block.
 *  This method returns immediately and executes the clear operation with block in background.
 *  @param progress This block will be invoked during removing, pass nil to ignore.
 *  @param end This block will be invoked at the end, pass nil to ignore.
 */
- (void)removeAllObjectsWithProgressBlock:(void (^)(int removedCount,int totalCount))progress endBlock:(void (^)(BOOL error))end;

@end
