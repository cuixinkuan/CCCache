//
//  CCKVStorage.h
//  CCCache
//
//  Created by admin on 15/12/3.
//  Copyright © 2015年 CXK. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface CCKVStorageItem : NSObject
@property (nonatomic,strong)NSString * key; ///>key
@property (nonatomic,strong)NSData * value;///>value
@property (nonatomic,strong)NSString * filename;///>filename (nil if inline)
@property (nonatomic,assign)int size;///>value's size in bytes
@property (nonatomic,assign)int modTime;///>modification unix
@property (nonatomic,assign)int accessTime;///>last access unix
@property (nonatomic,strong)NSData * extendedData;///>extended data (nil if no extended data)

@end

/**
 *  storage type
 */
typedef NS_ENUM(NSUInteger,CCKVStorageType){
    /**
     *  the 'value' is stored as a file in file system
     */
    CCKVStorageTypeFile = 0,
    /**
     *  the 'value' is stored in sqlite with blob type
     */
    CCKVStorageTypeSQLite = 1,
    /**
     *  the 'value' is stored in file system or sqlite based on your choice
     */
    CCKVStorageTypeMixed = 2,
};

/**
 *  CCKVStorage is a key-value storage based on sqlite and file system
 */
@interface CCKVStorage : NSObject
#pragma mark - Attributes 
/**
 *  the path for this storage
 */
@property (nonatomic,readonly)NSString * path;
/**
 *  the type of this storage
 */
@property (nonatomic,readonly)CCKVStorageType type;
/**
 *  set 'Yes' to enable error logs for debug
 */
@property (nonatomic,assign)BOOL errorLogsEnabled;

#pragma mark - Initializer 
- (instancetype)init UNAVAILABLE_ATTRIBUTE;
+ (instancetype)new UNAVAILABLE_ATTRIBUTE;
/**
 *  The designated initializer
 *
 *  @param path full path of a dictionary in which the storage will write data. If the dieectory is not exists, it will try to create one, otherwise it will read the data in this dircetory.
 *  @param type the storage type
 *
 *  @return a new atorage object or nil if an error occurs
 */
- (instancetype)initWithPath:(NSString *)path type:(CCKVStorageType)type NS_DESIGNATED_INITIALIZER;

#pragma mark - Save Items 
/**
 *  Save an item or upddate the item with 'key' if it already exists.
 *
 *  @param item an item
 *
 *  @return whether succeed
 */
- (BOOL)saveItem:(CCKVStorageItem *)item;
/**
 *  this method will save the key - value pair to sqlite. If the 'type' is CCKVStorageTypefile, then this method will failed.
 *
 *  @param key   the key
 *  @param value the value
 *
 *  @return whether succeed
 */
- (BOOL)saveItemWithkey:(NSString *)key value:(NSData *)value;
/**
 *  if the 'type' is CCKVStorageTypeFile, then the 'filename' should not be empty.
    If the 'type' is CCKVStorageTypeSQLite, then the 'filename' will be ignored.
    If the 'type' is CCKVStorageTypeMixed, then the 'value' will be saved to file system if the 'filename' is not empty, otherwise it will be saves to sqlite.
 *
 *  @param key          the key
 *  @param value        the value
 *  @param filename     the filename
 *  @param extendedData the extended data for this item
 *
 *  @return whether succeed
 */
- (BOOL)saveItemWithkey:(NSString *)key
                  value:(NSData *)value
               filename:(NSString *)filename
           extendedData:(NSData *)extendedData;

#pragma mark - Remove Items
/**
 *  Remove an item with 'key'.
 *
 *  @param key the key
 *
 *  @return whether succeed
 */
- (BOOL)removeItemForKey:(NSString *)key;
/**
 *  remove items with an array of keys.
 *
 *  @param keys an array of specified keys
 *
 *  @return whether succeed
 */
- (BOOL)removeItemForKeys:(NSArray *)keys;
/**
 *  remove all items which 'value' is larger than a specified size.
 *
 *  @param size the maximum size in bytes
 *
 *  @return whether succeed
 */
- (BOOL)removeItemslargerThanSize:(int)size;
/**
 *  remove all items which last access time is earlier than a specified timestamp.
 *
 *  @param time the specified unix timestamp.
 *
 *  @return whether succeed
 */
- (BOOL)removeItemsEarlierThanTime:(int)time;
/**
 *  remove items to make the total size not larger than a specified size.
 *
 *  @param maxSize the specified size in bytes
 *
 *  @return whether succeed
 */
- (BOOL)removeItemsToFitSize:(int)maxSize;
/**
 *  remove items to make the total count not larger than a specified count.
    The least resently used (LRU) items will be removed first.
 *
 *  @param maxCount the specified count.
 *
 *  @return whether succeed
 */
- (BOOL)removeItemsToFitCount:(int)maxCount;
/**
 *  remove all items in background queue.
 *  This method will remove the files and sqlite database to a trash folder, and then clear the folder in background queue.
 *  @return whether succeed
 */
- (BOOL)removeAllItems;
/**
 *  remove all items.
 *  You should not send message to this instance in these blocks.
 *  @param progress this block will be invoked during removing, pass nil to ignore.
 *  @param end      This block will be invoked at the end, pass nil to ignore.
 */
- (void)removeAllItemsWithProgressBlock:(void(^)(int removedCount, int totalCount))progress
                               endBlock:(void(^)(BOOL error))end;


#pragma mark - Get Items
/**
 *  Get item with a specified key
 *
 *  @param key a specified key
 *
 *  @return item for the key, or nil if not exists/error occurs.
 */
- (CCKVStorageItem *)getItemForkey:(NSString *)key;
/**
 *  Get item information with a specified key.
 *
 *  @param key key
 *
 *  @return item information for the key.
 */
-(CCKVStorageItem *)getitemInfoForKey:(NSString *)key;
/**
 *  Get item value with a specified key
 *
 *  @param key key
 *
 *  @return item's value or nil if not exists/error occurs.
 */
- (NSData *)getItemValueForKey:(NSString *)key;
/**
 *  Get items with an array of keys
 *
 *  @param keys keys
 *
 *  @return an array of 'CCKVStorageItem', or nil if not exists/error occurs.
 */
- (NSArray *)getItemForKeys:(NSArray *)keys;
/**
 *  Get items informations with an array of keys
 *
 *  @param keys keys
 *
 *  @return an array of 'CCKVStorageItem', or nil if not exists/error occurs.
 */
- (NSArray *)getItemInfoForKeys:(NSArray *)keys;
/**
 *  Get items value with an array of keys
 *
 *  @param keys keys
 *
 *  @return an dictionary which key is 'key' and 'value' is 'value', or nil if not exists/error occurs.
 */
- (NSDictionary *)getItemValueForKeys:(NSArray *)keys;

#pragma  mark - Get storage Status
/**
 *  whether an item exists for a specified key.
 *
 *  @param key key
 *
 *  @return 'Yes' if there's an item exists for the key, 'No' if not exists or error occurs.
 */
- (BOOL)itemExistsForKey:(NSString *)key;
/**
 *  get total item count.
 *
 *  @return Total item count, -1 when an error occurs.
 */
- (int)getItemsCount;
/**
 *  Get item value's total size in bytes.
 *
 *  @return Total size in bytes, -1 when an error occurs.
 */
- (int)getItemsSize;


@end
























