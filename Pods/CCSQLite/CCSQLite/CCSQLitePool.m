//
//  CCSQLitePool.m
//  CCSQLite
//
//  Created by deng you hua on 2/12/17.
//  Copyright © 2017 CC | ccworld1000@gmail.com. All rights reserved.
//

#import "CCSQLitePool.h"
#import "CCSQLite.h"

@interface CCSQLitePool () {
    dispatch_queue_t _lockQueue;

    NSMutableArray * _databaseInPool;
    NSMutableArray * _databaseOutPool;
}

- (void) pushDatabaseBackInPool:(CCSQLite *)db;
- (CCSQLite *) db;

@end


@implementation CCSQLitePool

+ (instancetype) databasePoolWithPath:(NSString *)aPath {
    return CCReturnAutoreleased([[self alloc] initWithPath:aPath]);
}

+ (instancetype) databasePoolWithPath:(NSString *)aPath flags:(int)openFlags {
    return CCReturnAutoreleased([[self alloc] initWithPath:aPath flags:openFlags]);
}

- (instancetype) initWithPath:(NSString *)aPath flags:(int)openFlags vfs:(NSString *)vfsName {

    self = [super init];

    if (self != nil) {
        _path               = [aPath copy];
        _lockQueue          = dispatch_queue_create([[NSString stringWithFormat:@"CCSQLitePool.%@", self] UTF8String], NULL);
        _databaseInPool     = CCReturnRetained([NSMutableArray array]);
        _databaseOutPool    = CCReturnRetained([NSMutableArray array]);
        _openFlags          = openFlags;
        _vfsName            = [vfsName copy];
    }

    return self;
}

- (instancetype) initWithPath:(NSString *)aPath flags:(int)openFlags {
    return [self initWithPath:aPath flags:openFlags vfs:nil];
}

- (instancetype) initWithPath:(NSString *)aPath {
    // default flags for sqlite3_open
    return [self initWithPath:aPath flags:SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE];
}

- (instancetype) init {
    return [self initWithPath:nil];
}

+ (Class) databaseClass {
    return [CCSQLite class];
}

- (void) dealloc {

    _delegate = CCNULL;
    CCRelease(_path);
    CCRelease(_databaseInPool);
    CCRelease(_databaseOutPool);

    if (_lockQueue) {
        CCDispatchQueueRelease(_lockQueue);
        _lockQueue = CCNULL;
    }
}


- (void) executeLocked:(void (^)(void))aBlock {
    dispatch_sync(_lockQueue, aBlock);
}

- (void) pushDatabaseBackInPool:(CCSQLite *)db {

    if (!db) { // db can be null if we set an upper bound on the # of databases to create.
        return;
    }

    [self executeLocked:^() {

         if ([self->_databaseInPool containsObject:db]) {
             [[NSException exceptionWithName:@"Database already in pool" reason:@"The CCSQLite being put back into the pool is already present in the pool" userInfo:nil] raise];
         }

         [self->_databaseInPool addObject:db];
         [self->_databaseOutPool removeObject:db];

     }];
}

- (CCSQLite *) db {

    __block CCSQLite * db;


    [self executeLocked:^() {
         db = [self->_databaseInPool lastObject];

         BOOL shouldNotifyDelegate = NO;

         if (db) {
             [self->_databaseOutPool addObject:db];
             [self->_databaseInPool removeLastObject];
         } else {

             if (self->_maximumNumberOfDatabasesToCreate) {
                 NSUInteger currentCount = [self->_databaseOutPool count] + [self->_databaseInPool count];

                 if (currentCount >= self->_maximumNumberOfDatabasesToCreate) {
                     NSLog(@"Maximum number of databases (%ld) has already been reached!", (long)currentCount);
                     return;
                 }
             }

             db = [[[self class] databaseClass] databaseWithPath:self->_path];
             shouldNotifyDelegate = YES;
         }

         // This ensures that the db is opened before returning
#if SQLITE_VERSION_NUMBER >= 3005000
         BOOL success = [db openWithFlags:self->_openFlags vfs:self->_vfsName];
#else
         BOOL success = [db open];
#endif
         if (success) {
             if ([self->_delegate respondsToSelector:@selector(databasePool:shouldAddDatabaseToPool:)] && ![self->_delegate databasePool:self shouldAddDatabaseToPool:db]) {
                 [db close];
                 db = CCNULL;
             } else {
                 // It should not get added in the pool twice if lastObject was found
                 if (![self->_databaseOutPool containsObject:db]) {
                     [self->_databaseOutPool addObject:db];

                     if (shouldNotifyDelegate && [self->_delegate respondsToSelector:@selector(databasePool:didAddDatabase:)]) {
                         [self->_delegate databasePool:self didAddDatabase:db];
                     }
                 }
             }
         } else {
             NSLog(@"Could not open up the database at path %@", self->_path);
             db = CCNULL;
         }
     }];

    return db;
} /* db */

- (NSUInteger) countOfCheckedInDatabases {

    __block NSUInteger count;

    [self executeLocked:^() {
         count = [self->_databaseInPool count];
     }];

    return count;
}

- (NSUInteger) countOfCheckedOutDatabases {

    __block NSUInteger count;

    [self executeLocked:^() {
         count = [self->_databaseOutPool count];
     }];

    return count;
}

- (NSUInteger) countOfOpenDatabases {
    __block NSUInteger count;

    [self executeLocked:^() {
         count = [self->_databaseOutPool count] + [self->_databaseInPool count];
     }];

    return count;
}

- (void) releaseAllDatabases {
    [self executeLocked:^() {
         [self->_databaseOutPool removeAllObjects];
         [self->_databaseInPool removeAllObjects];
     }];
}

- (void) inDatabase:(void (^)(CCSQLite * db))block {

    CCSQLite * db = [self db];

    block(db);

    [self pushDatabaseBackInPool:db];
}

- (void) beginTransaction:(BOOL)useDeferred withBlock:(void (^)(CCSQLite * db, BOOL * rollback))block {

    BOOL shouldRollback = NO;

    CCSQLite * db = [self db];

    if (useDeferred) {
        [db beginDeferredTransaction];
    } else {
        [db beginTransaction];
    }


    block(db, &shouldRollback);

    if (shouldRollback) {
        [db rollback];
    } else {
        [db commit];
    }

    [self pushDatabaseBackInPool:db];
} /* beginTransaction */

- (void) inDeferredTransaction:(void (^)(CCSQLite * db, BOOL * rollback))block {
    [self beginTransaction:YES withBlock:block];
}

- (void) inTransaction:(void (^)(CCSQLite * db, BOOL * rollback))block {
    [self beginTransaction:NO withBlock:block];
}

- (NSError *) inSavePoint:(void (^)(CCSQLite * db, BOOL * rollback))block {
#if SQLITE_VERSION_NUMBER >= 3007000
    static unsigned long savePointIdx = 0;

    NSString * name = [NSString stringWithFormat:@"savePoint%ld", savePointIdx++];

    BOOL shouldRollback = NO;

    CCSQLite * db = [self db];

    NSError * err = CCNULL;

    if (![db startSavePointWithName:name error:&err]) {
        [self pushDatabaseBackInPool:db];
        return err;
    }

    block(db, &shouldRollback);

    if (shouldRollback) {
        // We need to rollback and release this savepoint to remove it
        [db rollbackToSavePointWithName:name error:&err];
    }
    [db releaseSavePointWithName:name error:&err];

    [self pushDatabaseBackInPool:db];

    return err;
#else  /* if SQLITE_VERSION_NUMBER >= 3007000 */
    NSString * errorMessage = NSLocalizedString(@"Save point functions require SQLite 3.7", nil);
    if (self.logsErrors) NSLog(@"%@", errorMessage);
    return [NSError errorWithDomain:@"CCSQLite" code:0 userInfo:@{ NSLocalizedDescriptionKey : errorMessage }];
#endif /* if SQLITE_VERSION_NUMBER >= 3007000 */
} /* inSavePoint */

@end
