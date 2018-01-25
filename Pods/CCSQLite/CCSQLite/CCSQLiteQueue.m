//
//  CCSQLiteQueue.m
//  CCSQLite
//
//  Created by deng you hua on 2/12/17.
//  Copyright © 2017 CC | ccworld1000@gmail.com. All rights reserved.
//

#import "CCSQLiteQueue.h"
#import "CCSQLite.h"

@interface CCSQLiteQueue () {
    dispatch_queue_t _queue;
    CCSQLite * _db;
}

@end

/*
 *
 * Note: we call [self retain]; before using dispatch_sync, just incase
 * CCSQLiteQueue is released on another thread and we're in the middle of doing
 * something in dispatch_sync
 *
 */

/*
 * A key used to associate the CCSQLiteQueue object with the dispatch_queue_t it uses.
 * This in turn is used for deadlock detection by seeing if inDatabase: is called on
 * the queue's dispatch queue, which should not happen and causes a deadlock.
 */
static const void * const kDispatchQueueSpecificKey = &kDispatchQueueSpecificKey;

@implementation CCSQLiteQueue

+ (instancetype) databaseQueueWithPath:(NSString *)aPath {

    CCSQLiteQueue * q = [[self alloc] initWithPath:aPath];

    CCAutorelease(q);

    return q;
}

+ (instancetype) databaseQueueWithPath:(NSString *)aPath flags:(int)openFlags {

    CCSQLiteQueue * q = [[self alloc] initWithPath:aPath flags:openFlags];

    CCAutorelease(q);

    return q;
}

+ (Class) databaseClass {
    return [CCSQLite class];
}

- (instancetype) initWithPath:(NSString *)aPath flags:(int)openFlags vfs:(NSString *)vfsName {

    self = [super init];

    if (self != nil) {

        _db = [[[self class] databaseClass] databaseWithPath:aPath];
        CCRetain(_db);

#if SQLITE_VERSION_NUMBER >= 3005000
        BOOL success = [_db openWithFlags:openFlags vfs:vfsName];
#else
        BOOL success = [_db open];
#endif
        if (!success) {
            NSLog(@"Could not create database queue for path %@", aPath);
            CCRelease(self);
            return CCNULL;
        }

        _path = CCReturnRetained(aPath);

        _queue = dispatch_queue_create([[NSString stringWithFormat:@"CCSQLiteQueue.%@", self] UTF8String], NULL);
        dispatch_queue_set_specific(_queue, kDispatchQueueSpecificKey, (__bridge void *)self, NULL);
        _openFlags = openFlags;
        _vfsName = [vfsName copy];
    }

    return self;
} /* initWithPath */

- (instancetype) initWithPath:(NSString *)aPath flags:(int)openFlags {
    return [self initWithPath:aPath flags:openFlags vfs:nil];
}

- (instancetype) initWithPath:(NSString *)aPath {

    // default flags for sqlite3_open
    return [self initWithPath:aPath flags:SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE vfs:nil];
}

- (instancetype) init {
    return [self initWithPath:nil];
}


- (void) dealloc {

    CCRelease(_db);
    CCRelease(_path);

    if (_queue) {
        CCDispatchQueueRelease(_queue);
        _queue = CCNULL;
    }
}

- (void) close {
    CCRetain(self);
    dispatch_sync(_queue, ^() {
        [self->_db close];
        CCRelease(_db);
        self->_db = CCNULL;
    });
    CCRelease(self);
}

- (void) interrupt {
    [[self database] interrupt];
}

- (CCSQLite *) database {
    if (!_db) {
        _db = CCReturnRetained([[[self class] databaseClass] databaseWithPath:_path]);

#if SQLITE_VERSION_NUMBER >= 3005000
        BOOL success = [_db openWithFlags:_openFlags vfs:_vfsName];
#else
        BOOL success = [_db open];
#endif
        if (!success) {
            NSLog(@"CCSQLiteQueue could not reopen database for path %@", _path);
            CCRelease(_db);
            _db  = CCNULL;
            return CCNULL;
        }
    }

    return _db;
}

- (void) inDatabase:(void (^)(CCSQLite * db))block {
#ifndef NDEBUG
    /* Get the currently executing queue (which should probably be nil, but in theory could be another DB queue
     * and then check it against self to make sure we're not about to deadlock. */
    CCSQLiteQueue * currentSyncQueue = (__bridge id)dispatch_get_specific(kDispatchQueueSpecificKey);
    assert(currentSyncQueue != self && "inDatabase: was called reentrantly on the same queue, which would lead to a deadlock");
#endif

    CCRetain(self);

    dispatch_sync(_queue, ^() {

        CCSQLite * db = [self database];
        block(db);

        if ([db hasOpenResultSets]) {
            NSLog(@"Warning: there is at least one open result set around after performing [CCSQLiteQueue inDatabase:]");

#if defined(DEBUG) && DEBUG
            NSSet * openSetCopy = CCReturnAutoreleased([[db valueForKey:@"_openResultSets"] copy]);
            for (NSValue * rsInWrappedInATastyValueMeal in openSetCopy) {
                CCResultSet * rs = (CCResultSet *)[rsInWrappedInATastyValueMeal pointerValue];
                NSLog(@"query: '%@'", [rs query]);
            }
#endif
        }
    });

    CCRelease(self);
} /* inDatabase */


- (void) beginTransaction:(BOOL)useDeferred withBlock:(void (^)(CCSQLite * db, BOOL * rollback))block {
    CCRetain(self);
    dispatch_sync(_queue, ^() {

        BOOL shouldRollback = NO;

        if (useDeferred) {
            [[self database] beginDeferredTransaction];
        } else {
            [[self database] beginTransaction];
        }

        block([self database], &shouldRollback);

        if (shouldRollback) {
            [[self database] rollback];
        } else {
            [[self database] commit];
        }
    });

    CCRelease(self);
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
    __block NSError * err = CCNULL;
    CCRetain(self);
    dispatch_sync(_queue, ^() {

        NSString * name = [NSString stringWithFormat:@"savePoint%ld", savePointIdx++];

        BOOL shouldRollback = NO;

        if ([[self database] startSavePointWithName:name error:&err]) {

            block([self database], &shouldRollback);

            if (shouldRollback) {
                // We need to rollback and release this savepoint to remove it
                [[self database] rollbackToSavePointWithName:name error:&err];
            }
            [[self database] releaseSavePointWithName:name error:&err];

        }
    });
    CCRelease(self);
    return err;
#else  /* if SQLITE_VERSION_NUMBER >= 3007000 */
    NSString * errorMessage = NSLocalizedString(@"Save point functions require SQLite 3.7", nil);
    if (self.logsErrors) NSLog(@"%@", errorMessage);
    return [NSError errorWithDomain:@"CCSQLite" code:0 userInfo:@{ NSLocalizedDescriptionKey : errorMessage }];
#endif /* if SQLITE_VERSION_NUMBER >= 3007000 */
} /* inSavePoint */

@end
