//
//  CCMemoryCache.m
//  CCCache
//
//  Created by admin on 15/12/17.
//  Copyright © 2015年 CXK. All rights reserved.
//

#import "CCMemoryCache.h"
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <libkern/OSAtomic.h>
#import <pthread.h>

#if __has_include("CCDispatchQueuePool.h")
#import "CCDispatchQueuePool.h"
#else
#import <libkern/OSAtomic.h>
#endif

#ifdef CCDispatchQueuePool_h 
static inline dispatch_queue_t CCMemoryCacheGetReleaseQueue() {
    return CCDispatchQueueGetForQOS(NSQualityOfServiceUtility);
}
#else
static inline dispatch_queue_t CCMemoryCacheGetReleaseQueue() {
    return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);
}
#endif

@interface _CCLinkedMapNode : NSObject {
  @package
    __unsafe_unretained _CCLinkedMapNode * _prev; //retained by dic
    __unsafe_unretained _CCLinkedMapNode * next; //retained by dic
    id _key;
    id _value;
    NSUInteger _cost;
    NSTimeInterval _time;
}
@end

@implementation _CCLinkedMapNode
@end


@interface _CCLinkedMap : NSObject {
  @package
    CFMutableDictionaryRef _dic;
    NSUInteger _totalCost;
    NSUInteger _totalCount;
    _CCLinkedMapNode * _head;
    _CCLinkedMapNode * _tail;
    BOOL _releaseOnMainThread;
    BOOL _releaseAsynchronously;
}

- (void)insertNodeToHead:(_CCLinkedMapNode *)node;

- (void)bringNodeToHead:(_CCLinkedMapNode *)node;

- (void)removeNode:(_CCLinkedMapNode *)node;

- (_CCLinkedMapNode *)removeTailNode;

- (void)removeAll;
@end

@implementation _CCLinkedMap

- (instancetype)init {
    self = [super init];
    _dic = CFDictionaryCreateMutable(CFAllocatorGetDefault(), 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    _releaseOnMainThread = NO;
    _releaseAsynchronously = YES;
    return self;
}

- (void)dealloc {
    CFRelease(_dic);
}

- (void)insertNodeToHead:(_CCLinkedMapNode *)node {
    CFDictionarySetValue(_dic, (__bridge const void *)(node->_key), (__bridge const void *)(node));
    _totalCost += node->_cost;
    _totalCount ++;
    if (_head) {
        node->next = _head;
        _head->_prev = node;
        _head = node;
    }else {
        _head = _tail = node;
    }
}

- (void)bringNodeToHead:(_CCLinkedMapNode *)node {
    if (_head == node) {
        return;
    }
    if (_tail == node) {
        _tail = node->_prev;
        _tail->next = nil;
    }else {
        node->next->_prev = node->_prev;
        node->_prev->next = node->next;
    }
    node->next = _head;
    node->_prev = nil;
    _head->_prev = node;
    _head = node;
}

- (void)removeNode:(_CCLinkedMapNode *)node {
    CFDictionaryRemoveValue(_dic, (__bridge const void *)(node->_key));
    _totalCost -= node->_cost;
    _totalCount --;
    if (node->next) node->next->_prev = node->_prev;
    if (node->_prev) node->_prev->next = node->next;
    if (_head == node) _head = node->next;
    if (_tail == node) _tail = node->_prev;
}

- (_CCLinkedMapNode *)removeTailNode {
    if (!_tail) {
        return nil;
    }
    _CCLinkedMapNode * tail = _tail;
    CFDictionaryRemoveValue(_dic, (__bridge const void *)(_tail->_key));
    _totalCost -= _tail->_cost;
    _totalCount -- ;
    if (_head == _tail) {
        _head = _tail = nil;
    }else {
        _tail = _tail->_prev;
        _tail->next = nil;
    }
    return tail;
}

- (void)removeAll {
    _totalCount = 0;
    _totalCost = 0;
    _head = nil;
    _tail = nil;
    if (CFDictionaryGetCount(_dic) > 0) {
        CFMutableDictionaryRef holder = _dic;
        _dic = CFDictionaryCreateMutable(CFAllocatorGetDefault(), 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        if (_releaseAsynchronously) {
            dispatch_queue_t queue = _releaseOnMainThread ?
            dispatch_get_main_queue() : CCMemoryCacheGetReleaseQueue();
            dispatch_async(queue, ^{
                CFRelease(holder);
            });
        }else if (_releaseOnMainThread && !pthread_main_np()) {
          dispatch_async(dispatch_get_main_queue(), ^{
              CFRelease(holder);
          });
        }else {
            CFRelease(holder);
        }
    }
}


@end


@implementation CCMemoryCache

{
    OSSpinLock _lock;
    _CCLinkedMap * _lru;
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
    dispatch_async(_queue, ^{
        [self _trimToCost:self->_costLimit];
        [self _trimToCount:self->_countLimit];
        [self _trimToAge:self->_ageLimit];
    });
}

- (void)_trimToCost:(NSUInteger)costLimit {
    BOOL finish = NO;
    OSSpinLockLock(&_lock);
    if (costLimit == 0) {
        [_lru removeAll];
        finish = YES;
    }else if (_lru->_totalCost <= costLimit) {
        finish = YES;
    }
    OSSpinLockUnlock(&_lock);
    if (finish) {
        return;
    }
    
    NSMutableArray * holder = [NSMutableArray new];
    while (!finish) {
        if (OSSpinLockTry(&_lock)) {
            if (_lru->_totalCost > costLimit) {
                _CCLinkedMapNode * node = [_lru removeTailNode];
                if (node) {
                    [holder addObject:node];
                }
            }else {
                finish = YES;
            }
            OSSpinLockUnlock(&_lock);
        }else {
            usleep(10 * 1000);
        }
    }
    if (holder.count) {
        dispatch_queue_t queue = _lru->_releaseOnMainThread ?
        dispatch_get_main_queue() : CCMemoryCacheGetReleaseQueue();
        dispatch_async(queue, ^{
            [holder count];
        });
    }
    
}

- (void)_trimToCount:(NSUInteger)countLimit {
    BOOL finish = NO;
    OSSpinLockLock(&_lock);
    if (countLimit == 0 ) {
        [_lru removeAll];
        finish = YES;
    }else if (_lru->_totalCount <= countLimit) {
        finish = YES;
    }
    OSSpinLockUnlock(&_lock);
    if (finish) {
        return;
    }
    
    NSMutableArray * holder = [NSMutableArray new];
    while (!finish) {
        if (OSSpinLockTry(&_lock)) {
            if (_lru->_totalCount > countLimit) {
                _CCLinkedMapNode * node = [_lru removeTailNode];
                if (node)[holder addObject:node];
            }else {
                finish = YES;
            }
            OSSpinLockUnlock(&_lock);
        }else {
            usleep(10 * 1000); // 10 ms
        }
    }
    if (holder.count) {
        dispatch_queue_t queue = _lru->_releaseOnMainThread ?
        dispatch_get_main_queue() : CCMemoryCacheGetReleaseQueue();
        dispatch_async(queue, ^{
            [holder count];
        });
    }
}

- (void)_trimToAge:(NSTimeInterval)ageLimit {
    BOOL finish = NO;
    NSTimeInterval now = CACurrentMediaTime();
    OSSpinLockLock(&_lock);
    if (ageLimit <= 0 ) {
        [_lru removeAll];
        finish = YES;
    }else if (!_lru->_tail || (now - _lru->_tail->_time <= ageLimit)) {
        finish = YES;
    }
    OSSpinLockUnlock(&_lock);
    if (finish ) {
        return;
    }
    
    NSMutableArray * holder = [NSMutableArray new];
    while (!finish) {
        if (OSSpinLockTry(&_lock)) {
            if (_lru->_tail && (now - _lru->_tail->_time > ageLimit)) {
                _CCLinkedMapNode * node = [_lru removeTailNode];
                if (node) [holder addObject:node];
            }else {
                finish = YES;
            }
            OSSpinLockUnlock(&_lock);
        }else {
            usleep(10 * 1000); // 10 ms
        }
    }
    if (holder.count) {
        dispatch_queue_t queue = _lru->_releaseOnMainThread ?
        dispatch_get_main_queue() : CCMemoryCacheGetReleaseQueue();
        dispatch_async(queue, ^{
            [holder count]; // release in queue
        });
    }
  
}

- (void)_appDidReceiveMemoryWarningNotification {
    if (self.didReceiveMemoryWarningBlock) {
        self.didReceiveMemoryWarningBlock(self);
    }
    if (self.shouldRemoveAllObjectsOnMemoryWarning) {
        [self removeAllObjects];
    }
}

- (void)_appDidEnterBackgroundNotification {
    if (self.didEnterBackgroundBlock) {
        self.didEnterBackgroundBlock(self);
    }
    if (self.shouldRemoveAllObjectsWhenEnteringBackground) {
        [self removeAllObjects];
    }
}

#pragma mark - public 

- (instancetype)init {
    self = [super init];
    _lock = OS_SPINLOCK_INIT;
    _lru = [_CCLinkedMap new];
    _queue = dispatch_queue_create("com.cxk.cache.memory", DISPATCH_QUEUE_SERIAL);
    
    _costLimit = NSUIntegerMax;
    _countLimit = NSUIntegerMax;
    _ageLimit = DBL_MAX;
    _autoTrimInterval = 5.0;
    _shouldRemoveAllObjectsOnMemoryWarning = YES;
    _shouldRemoveAllObjectsWhenEnteringBackground = YES;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_appDidReceiveMemoryWarningNotification) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_appDidEnterBackgroundNotification) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [self _trimRecursively];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
    [_lru removeAll];
    
}

- (NSUInteger)totalCount {
    OSSpinLockLock(&_lock);
    NSUInteger count = _lru->_totalCount;
    OSSpinLockUnlock(&_lock);
    return count;
}
- (NSUInteger)totalCost {
    OSSpinLockLock(&_lock);
    NSUInteger totalcost = _lru->_totalCost;
    OSSpinLockUnlock(&_lock);
    return totalcost;
}

- (BOOL)releaseInMainThread {
    OSSpinLockLock(&_lock);
    BOOL releaseInMainThread = _lru->_releaseOnMainThread;
    OSSpinLockUnlock(&_lock);
    return releaseInMainThread;
}

- (void)setReleaseInMainThread:(BOOL)releaseInMainThread {
    OSSpinLockLock(&_lock);
    _lru->_releaseOnMainThread = releaseInMainThread;
    OSSpinLockUnlock(&_lock);
}

- (BOOL)releaseAsynchronously {
    OSSpinLockLock(&_lock);
    BOOL releaseAsynchronously = _lru->_releaseAsynchronously;
    OSSpinLockUnlock(&_lock);
    return releaseAsynchronously;
}


- (void)setReleaseAsynchronously:(BOOL)releaseAsynchronously {
    OSSpinLockLock(&_lock);
    _lru->_releaseAsynchronously = releaseAsynchronously;
    OSSpinLockUnlock(&_lock);

}

- (BOOL)containsObjectForKey:(id)key {
    if (!key) {
        return NO;
    }
    OSSpinLockLock(&_lock);
    BOOL contains = CFDictionaryContainsKey(_lru->_dic, (__bridge const void *)(key));
    OSSpinLockUnlock(&_lock);
    return contains;
}

- (id)objectForKey:(id)key {
    if (!key) {
        return nil;
    }
    OSSpinLockLock(&_lock);
    _CCLinkedMapNode * node = CFDictionaryGetValue(_lru->_dic, (__bridge const void *)(key));
    if (node) {
        node->_time = CACurrentMediaTime();
        [_lru bringNodeToHead:node];
    }
    OSSpinLockUnlock(&_lock);
    return node ? node->_value : nil;
}

- (void)setObject:(id)object forKey:(id)key {
    [self setObject:object forKey:key withCost:0];
}

- (void)setObject:(id)object forKey:(id)key withCost:(NSUInteger)cost {
    if (!key) {
        return ;
    }
    if (!object) {
        [self removeObjectForKey:key];
        return;
    }
    OSSpinLockLock(&_lock);
    _CCLinkedMapNode * node = CFDictionaryGetValue(_lru->_dic, (__bridge const void *)(key));
    NSTimeInterval now = CACurrentMediaTime();
    if (node) {
        _lru->_totalCost -= node->_cost;
        _lru->_totalCost += cost;
        node->_cost = cost;
        node->_time = now;
        node->_value = object;
        [_lru bringNodeToHead:node];
    }else {
        node = [_CCLinkedMapNode new];
        node->_cost = cost;
        node->_time = now;
        node->_key = key;
        node->_value = object;
        [_lru insertNodeToHead:node];
    }
    if (_lru->_totalCost > _costLimit) {
        dispatch_async(_queue, ^{
            [self trimToCost:_costLimit];
        });
    }
    if (_lru->_totalCount > _costLimit) {
        _CCLinkedMapNode * node = [_lru removeTailNode];
        if (_lru->_releaseAsynchronously) {
            dispatch_queue_t queue = _lru->_releaseOnMainThread ?
            dispatch_get_main_queue() : CCMemoryCacheGetReleaseQueue();
            dispatch_async(queue, ^{
                [node class];
            });
        }else if (_lru->_releaseOnMainThread && ! pthread_main_np()) {
          dispatch_async(dispatch_get_main_queue(), ^{
              [node class];
          });
        }
    }
    OSSpinLockUnlock(&_lock);
}

- (void)removeObjectForKey:(id)key {
    if (!key) {
        return;
    }
    OSSpinLockLock(&_lock);
    _CCLinkedMapNode * node = CFDictionaryGetValue(_lru->_dic,(__bridge const void *) (key));
    if (node) {
        [_lru removeNode:node];
        if (_lru->_releaseAsynchronously) {
            dispatch_queue_t queue = _lru->_releaseOnMainThread ?
            dispatch_get_main_queue() : CCMemoryCacheGetReleaseQueue();
            dispatch_async(queue, ^{
                [node class];
            });
        }else if (_lru->_releaseOnMainThread && ! pthread_main_np()) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [node class];
            });
        }
    }
    OSSpinLockUnlock(&_lock);
}

- (void)removeAllObjects {
    OSSpinLockLock(&_lock);
    [_lru removeAll];
    OSSpinLockUnlock(&_lock);
}

- (void)trimToCount:(NSUInteger)count {
    if (count == 0 ) {
        [self removeAllObjects];
        return;
    }
    [self _trimToCount:count];
}

- (void)trimToCost:(NSUInteger)cost {
    [self _trimToCost:cost];
}

- (void)trimToAge:(NSTimeInterval)age {
    [self _trimToAge:age];
}

- (NSString *)description {
    if (_name) {
        return [NSString stringWithFormat:@"<%@: %p> (%@)",self.class,self ,_name];
    }else {
        return [NSString stringWithFormat:@"<%@: %p>",self.class,self];
    }
}

@end
