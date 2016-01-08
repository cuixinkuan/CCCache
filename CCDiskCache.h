//
//  CCDiskCache.h
//  CCCache
//
//  Created by admin on 15/12/16.
//  Copyright © 2015年 CXK. All rights reserved.
//

#import <Foundation/Foundation.h>
/**
 *  CCDiskCache is a thread-safe cache that stores key-value pairs backed by SQLite and file system.
 */

@interface CCDiskCache : NSObject

#pragma  mark - Attributes
/* The name of the cache. Default is nil. */
@property (copy)NSString * name;
/* The path of the cache (readonly) */
@property (readonly)NSString * path;
/* If the object's data size (bytes) is larger than this value, then object be  */
@property (readonly)NSUInteger inlineThreshold;

@property (copy)NSData * (^customArchiveBlock)(id object);

@property (copy) id (^customUnarchiveBlock)(NSData * data);

@property (copy)NSString * (^customFilenameBlock)(NSString * key);

#pragma mark - Limited - 

@property (assign)NSUInteger countLimit;
@property (assign)NSUInteger costLimit;
@property (assign)NSTimeInterval ageLimit;
@property (assign)NSUInteger freeDiskSpaceLimit;
@property (assign)NSTimeInterval autoTrimInterval;

#pragma mark - Initializer -

- (instancetype)init UNAVAILABLE_ATTRIBUTE;
+ (instancetype)new UNAVAILABLE_ATTRIBUTE;

- (instancetype)initWithPath:(NSString *)path;
- (instancetype)initWithPath:(NSString *)path
             inlineThreshold:(NSUInteger)threshold NS_DESIGNATED_INITIALIZER;


#pragma mark - Access Methods -
/**
 *  Returns a boolean value that indicates whether a given key is in cache.
 This method may blocks the calling thread until file read finished.
 *
 *  @param key a string identifying the value. if nil,just return No.
 *
 *  @return yes or no
 */
- (BOOL)containsObjectForKey:(NSString *)key;
/**
 *  Returns a boolean value that indicates whether a given key is in cache.
 This method returns immediately and invoke the passed block in background queue.
 *
 *  @param key   a string identifying the value.If nil, just return NO.
 *  @param block A block which be invoked in background queue when finished.
 *
 */
- (void)containsObjectForKey:(NSString *)key withBlock:(void(^)(NSString * key,BOOL contains))block;
/**
 *  Returns the value associated with a given key.
 This method returns may blocks the calling thread until file read finished.
 *
 *  @param key A string identifying the value.
 *
 *  @return The value associated with key, or nil if no value is associated with key.
 */
- (id<NSCoding>)objectForKey:(NSString *)key;
/**
 *  Returns a value associated with a given key.
 This method returns immediately and invoke the passed block in background queue when the operation finished.
 *
 *  @param key   A string identifying the value. If nil, just return nil.
 *  @param block A block which will be invoked in background queue when finished.
 */
- (void)objectForKey:(NSString *)key withBlock:(void(^)(NSString * key,id<NSCoding> object))block;
/**
 *  Set the vlaue of the specified key in the cache.
 This method may blocks the calling thread until file write finished.
 *
 *  @param object The object to be stored in the cache. If nil, it calls 'removeObjectForKey:'
 *  @param key    The key which to associated the value, If nil, this method has no effect.
 */
- (void)setObject:(id<NSCoding>)object forKey:(NSString *)key;
/**
 *  Set vlaue of the specified key in the cache.
 This method returns immediately and invoke the passed block in background queue when the operation finished.
 *
 *  @param object The object to be stored in the cache.If nil...
 *
 *  @param block  A block which will be invoked in background queue when finished.
 */
- (void)setObject:(id<NSCoding>)object forKey:(NSString *)key withBlock:(void(^)(void))block;
/**
 *  Removes the value of the specified key in the cache.
 *
 *  @param key The key identifying the value to be removed. If nil, this method has no effect.
 */
- (void)removeObjectForKey:(NSString *)key;

- (void)removeObjectForKey:(NSString *)key withBlock:(void(^)(NSString * key))block;

- (void)removeAllObjects;

- (void)removeAllObjectsWithBlock:(void(^)(void))block;
/**
 *  Empties the cache with block.
 This method returns immediately and executes the clear operation with block in background. You should not send message to this instance in these blocks.
 *
 *  @param progress This block will be invoked during removing,pass nil to ignore.
 *  @param end      This block will be invoked at the end, pass nil to ignore.
 */
- (void)removeAllObjectsWithProgressBlock:(void(^)(int removedCount,int totalCount))progress
                                 endBlock:(void(^)(BOOL error))end;
/**
 *  Returns the number of objects in this cache.
 This method may blocks the calling thread until file read finished.
 *
 *  @return The total objects count.
 */
- (NSInteger)totalCount;
/**
 *  Get the number of objects in this cache.
 This method returns immediately and invoke the passed block in background queue when the operation finished
 *
 *  @param block A block which will be invoked in background queue when finished.
 */
- (void)totalCountWithBlock:(void(^)(NSInteger totalCount))block;
/**
 *  Returns the total cost (in bytes) of objects in this cache.
 *
 *  @return the total objects cost in bytes.
 */
- (NSInteger)totalCost;
/**
 *  Get the total cost (in bytes) of objects in this cache.
 This method returns immediately and invoke the passed block in background queue when the operation finished.
 *
 *  @param block A block which will be invoked in background queue when finished.
 */
- (void)totalCostWithBlock:(void(^)(NSInteger totalCost))block;

#pragma mark - Trim - 
/**
 *  Removes objects from the cache use LRU, until the 'totalCount' is below the specified value. This may blocks the calling thread until operation finished.
 *
 *  @param count The total count allowed to remain after the cache has been trimmed.
 */
- (void)trimToCount:(NSUInteger)count;

/**
 *  Removes objects from the cache use LRU, until the 'totalCount' is below the specified value.
 *
 *  @param count count The total count allowed to remain after the cache has been trimmed.
 *  @param block A block which will be invoked in backgorund queue when finished.
 */
- (void)trimToCount:(NSUInteger)count withBlock:(void(^)(void))block;

- (void)trimToCost:(NSUInteger)cost;

- (void)trimToCost:(NSUInteger)cost withBlock:(void(^)(void))block;
/**
 *  Removes objects from the cache use LRU, until all expiry(期满) objects removed by the specified value.
 *
 *  @param age The maximum age of the object.
 */
- (void)trimToAge:(NSTimeInterval)age;

- (void)trimToAge:(NSTimeInterval)age withBlock:(void(^)(void))block;

#pragma mark - Extend Data -

/**
 *  Get extend data from an object
 *
 *  @param object An object
 *
 *  @return The extend data
 */
+ (NSData *)getExtendedDataFromObject:(id)object;
/**
 *  Set extended data to an object
 *  You can set any extended data to an object before you save the object to disk cache. The extended data will also be saved with this object. You can get the extended data later with 'getExtendedDataFromObject'.
 
 *  @param extendedData The extended data (pass nil to remove)
 *  @param object       the object
 */
+ (void)setExtendedData:(NSData *)extendedData toObject:(id)object;


@end
