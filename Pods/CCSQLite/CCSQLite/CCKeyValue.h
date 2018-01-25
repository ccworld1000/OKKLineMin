//
//  CCKeyValue.h
//  CCSQLite
//
//  Created by dengyouhua on 17/2/22.
//  Copyright © 2017 CC | ccworld1000@gmail.com. All rights reserved.
//

#import <Foundation/Foundation.h>

#define CCKeyValueRowIDKey      @"rowid"
#define CCKeyValueCollectionKey @"collection"
#define CCKeyValueKey           @"key"
#define CCKeyValueDataKey       @"data"
#define CCKeyValueMetadataKey   @"metadata"

/**
 *  CCKeyValueType
 */
typedef NS_ENUM(NSInteger, CCKeyValueType) {
    /**
     *  default | NSKeyedArchiver/NSKeyedUnarchiver
     */
    CCKeyValueTypeDefault,
    /**
     *  PropertyList | Property lists ONLY support the following: NSData, NSString, NSArray, NSDictionary, NSDate, and NSNumber.
     */
    CCKeyValueTypePropertyList,
    /**
     *  json | support json string or json data
     */
    CCKeyValueTypeJson,
};

/**
 *  Embeded CCSQLite.Collection in table 'CCSQLite.Database2'
 *  because of use CCSQLiteQueue, you should Use alone
 *  CCKeyValue can replace NSUserDefaults or simple data type or key value type [Lightweight data] [Lightweight cache]
 */
@interface CCKeyValue : NSObject

/**
 *  valueType | if you change the valueType, store data type change
 */
@property (atomic) CCKeyValueType valueType;

/**
 *  defaultKeyValueWithPath
 *
 *  @param path path description
 *
 *  @return return value description
 */
+ (CCKeyValue *) defaultKeyValueWithPath : (NSString *)path;

/**
 *  setObject
 *
 *  @param object object description
 *  @param key    key description
 */
- (void) setObject: (id) object key : (NSString *) key;

/**
 *  objectForKey
 *
 *  @param key key description
 *
 *  @return return value description
 */
- (id) objectForKey : (NSString *) key;


@end
