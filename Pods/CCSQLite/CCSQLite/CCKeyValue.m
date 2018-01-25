//
//  CCKeyValue.m
//  CCSQLite
//
//  Created by dengyouhua on 17/2/22.
//  Copyright © 2017 CC | ccworld1000@gmail.com. All rights reserved.
//

#import "CCKeyValue.h"
#import "CCSQLite.h"

@interface CCKeyValue ()

@property (atomic, copy) NSString * path;

@property (atomic, copy) CCSQLiteSerializer objectSerializer;
@property (atomic, copy) CCSQLiteDeserializer objectDeserializer;

- (void) setObject:(id)object key:(NSString *)key;
- (id) objectForKey:(NSString *)key;

@end

@implementation CCKeyValue

+ (CCKeyValue *) defaultKeyValueWithPath:(NSString *)path {
    static CCKeyValue * kv = nil;

    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        kv = [CCKeyValue new];
        kv.valueType = CCKeyValueTypeDefault;
    });

    kv.path = path;

    return kv;
}

- (void) setObject:(id)object key:(NSString *)key inCollection:(NSString *)collection metadata:(NSData *)metadata {
    if (!_path || ![_path isKindOfClass:[NSString class]]) {
        NSLog(@"The actual path of the database must be obtained!");
        return;
    }

    NSString * c = nil;

    if (!collection || ![collection isKindOfClass:[NSString class]]) {
        c = CCSQLiteCollection;
    } else {
        c = collection;
    }

    if (!key || ![key isKindOfClass:[NSString class]]) {
        NSLog(@"key is illegal");
        return;
    }

    self.objectSerializer = [CCSQLite defaultSerializer];

    switch (_valueType) {
        case CCKeyValueTypePropertyList:
            self.objectSerializer = [CCSQLite propertyListSerializer];
            break;
        case CCKeyValueTypeJson:
            self.objectSerializer = [CCSQLite jsonSerializer];
            break;
        case CCKeyValueTypeDefault:
            self.objectSerializer = [CCSQLite defaultSerializer];
            break;
        default:
            break;
    }

    NSData * data = self.objectSerializer(c, key, object);

    CCSQLiteQueue * innerQueue = [CCSQLiteQueue databaseQueueWithPath:_path];

    __block BOOL isOK = NO;
    [innerQueue inTransaction:^(CCSQLite * db, BOOL * rollback) {
         isOK = [db executeUpdate:@"insert into 'CCSQLite.Database2' (collection, key, data, metadata) values (?, ?, ?, ?);", c, key, data, metadata];

         if (!isOK) {
             isOK = [db executeUpdate:@"update 'CCSQLite.Database2' set  data = ? , metadata = ?  where collection = ? and key = ?;",  data, metadata, c, key];
         }

         if (!isOK) {
             NSLog(@"execute excpetion!");
         }

         *rollback = !isOK;
     }];
} /* setObject */


- (id) objectForKey:(NSString *)key inCollection:(NSString *)collection {
    NSString * c = nil;
    __block id object = nil;

    if (!collection || ![collection isKindOfClass:[NSString class]]) {
        c = CCSQLiteCollection;
    } else {
        c = collection;
    }

    if (!key || ![key isKindOfClass:[NSString class]]) {
        NSLog(@"key is illegal");
        return object;
    }

    self.objectDeserializer = [CCSQLite defaultDeserializer];

    switch (_valueType) {
        case CCKeyValueTypePropertyList:
            self.objectDeserializer = [CCSQLite propertyListDeserializer];
            break;
        case CCKeyValueTypeJson:
            self.objectDeserializer = [CCSQLite jsonDeserializer];
            break;
        case CCKeyValueTypeDefault:
            self.objectDeserializer = [CCSQLite defaultDeserializer];
            break;
        default:
            break;
    }

    CCSQLiteQueue * innerQueue = [CCSQLiteQueue databaseQueueWithPath:_path];

    NSString * sql = [NSString stringWithFormat:@"select * from '%@' where  key = '%@' and collection = '%@';", CCSQLiteDatabase2, key, c];

    __block NSData * data = nil;
    [innerQueue inDatabase:^(CCSQLite * db) {
         CCResultSet * r = [db executeQuery:sql];
         while ([r next]) {
             data = [r dataForColumn:CCKeyValueDataKey];
             object = self.objectDeserializer(c, key, data);
             break;
         }

         [r close];
     }];

    return object;
} /* objectForKey */

- (void) setObject:(id)object key:(NSString *)key {
    [self setObject:object key:key inCollection:nil metadata:nil];
}

- (id) objectForKey:(NSString *)key  {
    return [self objectForKey:key inCollection:nil];
}


@end
