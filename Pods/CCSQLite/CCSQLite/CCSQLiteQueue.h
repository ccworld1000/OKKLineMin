//
//  CCSQLiteQueue.h
//  CCSQLite
//
//  Created by deng you hua on 2/12/17.
//  Copyright © 2017 CC | ccworld1000@gmail.com. All rights reserved.
//

#import <Foundation/Foundation.h>

@class CCSQLite;

/** To perform queries and updates on multiple threads, you'll want to use `CCSQLiteQueue`.
 
 Using a single instance of `<CCSQLite>` from multiple threads at once is a bad idea.  It has always been OK to make a `<CCSQLite>` object *per thread*.  Just don't share a single instance across threads, and definitely not across multiple threads at the same time.
 
 Instead, use `CCSQLiteQueue`. Here's how to use it:
 
 First, make your queue.
 
 CCSQLiteQueue *queue = [CCSQLiteQueue databaseQueueWithPath:aPath];
 
 Then use it like so:
 
 [queue inDatabase:^(CCSQLite *db) {
 [db executeUpdate:@"INSERT INTO myTable VALUES (?)", [NSNumber numberWithInt:1]];
 [db executeUpdate:@"INSERT INTO myTable VALUES (?)", [NSNumber numberWithInt:2]];
 [db executeUpdate:@"INSERT INTO myTable VALUES (?)", [NSNumber numberWithInt:3]];
 
 CCResultSet *rs = [db executeQuery:@"select * from foo"];
 while ([rs next]) {
 //…
 }
 }];
 
 An easy way to wrap things up in a transaction can be done like this:
 
 [queue inTransaction:^(CCSQLite *db, BOOL *rollback) {
 [db executeUpdate:@"INSERT INTO myTable VALUES (?)", [NSNumber numberWithInt:1]];
 [db executeUpdate:@"INSERT INTO myTable VALUES (?)", [NSNumber numberWithInt:2]];
 [db executeUpdate:@"INSERT INTO myTable VALUES (?)", [NSNumber numberWithInt:3]];
 
 if (whoopsSomethingWrongHappened) {
 *rollback = YES;
 return;
 }
 // etc…
 [db executeUpdate:@"INSERT INTO myTable VALUES (?)", [NSNumber numberWithInt:4]];
 }];
 
 `CCSQLiteQueue` will run the blocks on a serialized queue (hence the name of the class).  So if you call `CCSQLiteQueue`'s methods from multiple threads at the same time, they will be executed in the order they are received.  This way queries and updates won't step on each other's toes, and every one is happy.
 
 ### See also
 
 - `<CCSQLite>`
 
 @warning Do not instantiate a single `<CCSQLite>` object and use it across multiple threads. Use `CCSQLiteQueue` instead.
 
 @warning The calls to `CCSQLiteQueue`'s methods are blocking.  So even though you are passing along blocks, they will **not** be run on another thread.
 
 */

@interface CCSQLiteQueue : NSObject 

/** Path of database */

@property (atomic, copy) NSString *path;

/** Open flags */

@property (atomic, readonly) int openFlags;

/**  Custom virtual file system name */

@property (atomic, copy) NSString *vfsName;

///----------------------------------------------------
/// @name Initialization, opening, and closing of queue
///----------------------------------------------------

/** Create queue using path.
 
 @param aPath The file path of the database.
 
 @return The `CCSQLiteQueue` object. `nil` on error.
 */

+ (instancetype)databaseQueueWithPath:(NSString*)aPath;

/** Create queue using path and specified flags.
 
 @param aPath The file path of the database.
 @param openFlags Flags passed to the openWithFlags method of the database
 
 @return The `CCSQLiteQueue` object. `nil` on error.
 */
+ (instancetype)databaseQueueWithPath:(NSString*)aPath flags:(int)openFlags;

/** Create queue using path.
 
 @param aPath The file path of the database.
 
 @return The `CCSQLiteQueue` object. `nil` on error.
 */

- (instancetype)initWithPath:(NSString*)aPath;

/** Create queue using path and specified flags.
 
 @param aPath The file path of the database.
 @param openFlags Flags passed to the openWithFlags method of the database
 
 @return The `CCSQLiteQueue` object. `nil` on error.
 */

- (instancetype)initWithPath:(NSString*)aPath flags:(int)openFlags;

/** Create queue using path and specified flags.
 
 @param aPath The file path of the database.
 @param openFlags Flags passed to the openWithFlags method of the database
 @param vfsName The name of a custom virtual file system
 
 @return The `CCSQLiteQueue` object. `nil` on error.
 */

- (instancetype)initWithPath:(NSString*)aPath flags:(int)openFlags vfs:(NSString *)vfsName;

/** Returns the Class of 'CCSQLite' subclass, that will be used to instantiate database object.
 
 Subclasses can override this method to return specified Class of 'CCSQLite' subclass.
 
 @return The Class of 'CCSQLite' subclass, that will be used to instantiate database object.
 */

+ (Class)databaseClass;

/** Close database used by queue. */

- (void)close;

/** Interupt pending database operation. */

- (void)interrupt;

///-----------------------------------------------
/// @name Dispatching database operations to queue
///-----------------------------------------------

/** Synchronously perform database operations on queue.
 
 @param block The code to be run on the queue of `CCSQLiteQueue`
 */

- (void)inDatabase:(void (^)(CCSQLite *db))block;

/** Synchronously perform database operations on queue, using transactions.
 
 @param block The code to be run on the queue of `CCSQLiteQueue`
 */

- (void)inTransaction:(void (^)(CCSQLite *db, BOOL *rollback))block;

/** Synchronously perform database operations on queue, using deferred transactions.
 
 @param block The code to be run on the queue of `CCSQLiteQueue`
 */

- (void)inDeferredTransaction:(void (^)(CCSQLite *db, BOOL *rollback))block;

///-----------------------------------------------
/// @name Dispatching database operations to queue
///-----------------------------------------------

/** Synchronously perform database operations using save point.
 
 @param block The code to be run on the queue of `CCSQLiteQueue`
 */

// NOTE: you can not nest these, since calling it will pull another database out of the pool and you'll get a deadlock.
// If you need to nest, use CCSQLite's startSavePointWithName:error: instead.
- (NSError*)inSavePoint:(void (^)(CCSQLite *db, BOOL *rollback))block;

@end
