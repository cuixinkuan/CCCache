//
//  CCDiskCache.m
//  CCCache
//
//  Created by admin on 15/12/16.
//  Copyright © 2015年 CXK. All rights reserved.
//

#import "CCDiskCache.h"
#import "CCKVStorage.h"
#import <CommonCrypto/CommonCrypto.h>
#import <objc/runtime.h>
#import <time.h>

#define Lock() dispatch_semaphore_wait(_lock, DISPATCH_TIME_FOREVER)
#define Unlock() dispatch_semaphore_signal(_lock)

static const int extended_data_key;

// free disk space in bytes.
static int64_t _CCDiskSpaceFree() {
    
    NSError * error = nil;
    NSDictionary * attris = [[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory() error:&error];
    if (error)return -1;
    int64_t space = [[attris objectForKey:NSFileSystemFreeSize] longLongValue];
    if (space < 0) space = -1;
    return space;
}

// string's MD5 hash
static NSString * _CCNSStringMD5(NSString * string) {
    if (!string) {
        return nil;
    }
    NSData * data = [string dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5(data.bytes, (CC_LONG)data.length, result);
    return [NSString stringWithFormat:@"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
            result[0],  result[1],  result[2],  result[3],
            result[4],  result[5],  result[6],  result[7],
            result[8],  result[9],  result[10], result[11],
            result[12], result[13], result[14], result[15]
            ];
}


@implementation CCDiskCache
{
    CCKVStorage * _kv;
    dispatch_semaphore_t _lock;
    dispatch_queue_t _queue;
}

- (void)_trimRecursively {
    __weak typeof(self) _self = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_autoTrimInterval * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        __strong typeof(_self) self = _self;
        if (!self) {
            return ;
        }
        [self _trimInBackground];
        [self _trimRecursively];
    });
}

- (void)_trimInBackground {
    __weak typeof(self) _self = self;
    dispatch_async(_queue, ^{
        __strong typeof(_self) self = _self;
        if (!self) {
            return ;
        }
        dispatch_semaphore_wait(self->_lock, DISPATCH_TIME_FOREVER);
        [self _trimToCost:self.costLimit];
        [self _trimToCount:self.countLimit];
        [self _trimToAge:self.ageLimit];
        [self _trimToFreeDiskSpace:self.freeDiskSpaceLimit];
        dispatch_semaphore_signal(self->_lock);
        
    });
}

- (void)_trimToCost:(NSUInteger)costLimit {
    if (costLimit >= INT_MAX) return;
    [_kv removeItemsToFitSize:(int)costLimit];
}

- (void)_trimToCount:(NSUInteger)countLimit {
    if (countLimit >= INT_MAX) return;
    [_kv removeItemsToFitCount:(int)countLimit];
}

- (void)_trimToAge:(NSTimeInterval)ageLimit {
    if (ageLimit <= 0) {
        [_kv removeAllItems];
        return;
    }
    long timestamp = time(NULL);
    if (timestamp <= ageLimit) return;
    long age = timestamp - ageLimit;
    if (age >= INT_MAX) return;
    [_kv removeItemsEarlierThanTime:(int)age];
}

- (void)_trimToFreeDiskSpace:(NSUInteger)targetFreeDiskSpace {
    if (targetFreeDiskSpace == 0) {
        return;
    }
    int64_t totalBytes = [_kv getItemsSize];
    if (totalBytes <= 0) {
        return;
    }
    int64_t diskFreeBytes = _CCDiskSpaceFree();
    if (diskFreeBytes < 0) {
        return;
    }
    int64_t needTrimBytes = targetFreeDiskSpace - diskFreeBytes;
    if (needTrimBytes <= 0) {
        return;
    }
    int64_t costLimit = totalBytes - needTrimBytes;
    if (costLimit < 0) costLimit = 0;
    [self _trimToCost:(int)costLimit];
}

- (NSString *)_filenameForKey:(NSString *)key {
    NSString * filename = nil;
    if (_customFilenameBlock) filename = _customFilenameBlock(key);
    if (!filename) filename = _CCNSStringMD5(key);
    return filename;
}

#pragma mark - public - 

-(instancetype)init {
    @throw [NSException exceptionWithName:@"CCDiskCache init error" reason:@"CCDiskCache must be initialized with a path. Use 'initWithPath:' or 'initWithPath:inlineThreshold:' instead." userInfo:nil];
    return [self initWithPath:nil inlineThreshold:0];
}

- (instancetype)initWithPath:(NSString *)path {
    //20KB
    return [self initWithPath:path inlineThreshold:1024 * 20];
}

- (instancetype)initWithPath:(NSString *)path inlineThreshold:(NSUInteger)threshold {
    self = [super init];
    if (!self) {
        return nil;
    }
    
    CCKVStorageType type;
    if (threshold == 0 ) {
        type = CCKVStorageTypeFile;
    }else if (threshold == NSUIntegerMax) {
        type = CCKVStorageTypeSQLite;
    }else {
        type = CCKVStorageTypeMixed;
    }
    
    CCKVStorage * kv = [[CCKVStorage alloc] initWithPath:path type:type];
    if (!kv) {
        return nil;
    }
    
    _kv = kv;
    _path = path;
    _lock = dispatch_semaphore_create(1);
    _queue = dispatch_queue_create("com.cxk.cache.disk", DISPATCH_QUEUE_CONCURRENT);
    _inlineThreshold = threshold;
    _countLimit = NSUIntegerMax;
    _costLimit = NSUIntegerMax;
    _ageLimit = DBL_MAX;
    _freeDiskSpaceLimit = 0;
    _autoTrimInterval = 60;
    
    [self _trimRecursively];
    return self;
    
}

- (BOOL)containsObjectForKey:(NSString *)key {
    if (!key) {
        return NO;
    }
    Lock();
    BOOL contains = [_kv itemExistsForKey:key];
    Unlock();
    return contains;
}

- (void)containsObjectForKey:(NSString *)key withBlock:(void (^)(NSString *, BOOL))block {
    if (!block) {
        return;
    }
    __weak typeof(self) _self = self;
    dispatch_async(_queue, ^{
        __strong typeof(_self) self = _self;
        BOOL contains = [self containsObjectForKey:key];
        block (key,contains);
    });
}

- (id<NSCoding>)objectForKey:(NSString *)key {
    if (!key) {
        return nil;
    }
    Lock();
    CCKVStorageItem * item = [_kv getItemForkey:key];
    Unlock();
    if (!item.value) {
        return nil;
    }
    id object = nil;
    if (_customUnarchiveBlock) {
        object = _customUnarchiveBlock(item.value);
    }else {
        @try {
            object = [NSKeyedUnarchiver unarchiveObjectWithData:item.value];
        }
        @catch (NSException *exception) {
            //nothing to do ....
        }
    }
    if (object && item.extendedData) {
        [CCDiskCache setExtendedData:item.extendedData toObject:object];
    }
    return object;
}

- (void)objectForKey:(NSString *)key withBlock:(void (^)(NSString *, id<NSCoding>))block {
    if (!block) {
        return;
    }
    __weak typeof(self) _self = self;
    dispatch_async(_queue, ^{
        __strong typeof(_self) self = _self;
        id<NSCoding> object = [self objectForKey:key];
        block(key,object);
    });
}

- (void)setObject:(id<NSCoding>)object forKey:(NSString *)key {
    if (!key) {
        return;
    }
    if (!object) {
        [self removeObjectForKey:key];
        return;
    }
    NSData * extendedData = [CCDiskCache getExtendedDataFromObject:object];
    NSData * value = nil;
    if (_customArchiveBlock) {
        value = _customArchiveBlock(object);
    }else {
        @try {
            value = [NSKeyedArchiver archivedDataWithRootObject:object];
        }
        @catch (NSException *exception) {
            // nothing to do ...
        }
    }
    if (!value) {
        return;
    }
    NSString * filename = nil;
    if (_kv.type != CCKVStorageTypeSQLite) {
        if (value.length > _inlineThreshold) {
            filename = [self _filenameForKey:key];
        }
    }
    Lock();
    [_kv saveItemWithkey:key value:value filename:filename extendedData:extendedData];
    Unlock();
    
}

- (void)setObject:(id<NSCoding>)object forKey:(NSString *)key withBlock:(void (^)(void))block {
    __weak typeof(self ) _self = self;
    dispatch_async(_queue, ^{
        __strong typeof(_self) self = _self;
        [self setObject:object forKey:key];
        if (block) {
            block();
        }
    });
}

- (void)removeObjectForKey:(NSString *)key {
    if (!key) {
        return;
    }
    Lock();
    [_kv removeItemForKey:key];
    Unlock();
}

- (void)removeObjectForKey:(NSString *)key withBlock:(void (^)(NSString *))block {
    __weak typeof(self) _self = self;
    dispatch_async(_queue, ^{
        __strong typeof(_self) self = _self;
        [self removeObjectForKey:key];
        if (block) {
            block(key);
        }
    });
}

- (void)removeAllObjects {
    Lock();
    [_kv removeAllItems];
    Unlock();
}

- (void)removeAllObjectsWithBlock:(void (^)(void))block {
    __weak typeof(self) _self = self;
    dispatch_async(_queue, ^{
        __strong typeof(_self) self = _self;
        [self removeAllObjects];
        if (block) {
            block();
        }
    });
}

- (void)removeAllObjectsWithProgressBlock:(void (^)(int, int))progress endBlock:(void (^)(BOOL))end {
    __weak typeof(self) _self = self;
    dispatch_async(_queue, ^{
        __strong typeof(_self) self = _self;
        if (!self) {
            if (end)
                end(YES);
            return ;
        }
        dispatch_semaphore_wait(self->_lock, DISPATCH_TIME_FOREVER);
        [_kv removeAllItemsWithProgressBlock:progress endBlock:end];
        dispatch_semaphore_signal(self->_lock);
    });
}

- (NSInteger)totalCount {
    Lock();
    int count = [_kv getItemsCount];
    Unlock();
    return count;
}

- (void)totalCountWithBlock:(void (^)(NSInteger))block {
    if (!block) {
        return;
    }
    __weak typeof(self) _self = self;
    dispatch_async(_queue, ^{
        __strong typeof(_self) self = _self;
        NSInteger totalCount = [self totalCount];
        block(totalCount);
    });
}

- (NSInteger)totalCost {
    Lock();
    int cost = [_kv getItemsSize];
    Unlock();
    return cost;
}

- (void)totalCostWithBlock:(void (^)(NSInteger))block {
    if (!block) {
        return;
    }
    __weak typeof(self) _self = self;
    dispatch_async(_queue, ^{
        __strong typeof(_self) self = _self;
        NSInteger totalCost = [self totalCost];
        block(totalCost);
    });
}

- (void)trimToCount:(NSUInteger)count {
    Lock();
    [self _trimToCount:count];
    Unlock();
}

- (void)trimToCount:(NSUInteger)count withBlock:(void (^)(void))block {
    __weak typeof(self) _self = self;
    dispatch_async(_queue, ^{
        __strong typeof(_self) self = _self;
        [self trimToCount:count];
        if (block) {
            block();
        }
    });
}

- (void)trimToCost:(NSUInteger)cost {
    Lock();
    [self _trimToCost:cost];
    Unlock();
}

- (void)trimToCost:(NSUInteger)cost withBlock:(void (^)(void))block {
    __weak typeof(self) _self = self;
    dispatch_async(_queue, ^{
        __strong typeof(_self) self = _self;
        [self trimToCost:cost];
        if (block) {
            block();
        }
    });
}

- (void)trimToAge:(NSTimeInterval)age {
    Lock();
    [self _trimToAge:age];
    Unlock();
}

- (void)trimToAge:(NSTimeInterval)age withBlock:(void (^)(void))block {
    __weak typeof(self) _self = self;
    dispatch_async(_queue, ^{
        __strong typeof(_self) self = _self;
        [self trimToAge:age];
        if (block) {
            block();
        }
    });
}

+ (NSData *)getExtendedDataFromObject:(id)object {
    if (!object) {
        return nil;
    }
    return (NSData *)objc_getAssociatedObject(object, &extended_data_key);
}

+ (void)setExtendedData:(NSData *)extendedData toObject:(id)object {
    if (!object) {
        return;
    }
    objc_setAssociatedObject(object, &extended_data_key, extendedData, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSString *)description {
    if (_name) {
        return [NSString stringWithFormat:@"<%@: %p> (%@:%@)",self.class,self,_name,_path];
    }else {
        return [NSString stringWithFormat:@"<%@: %p> (%@)",self.class,self,_path];
    }
}

@end



















