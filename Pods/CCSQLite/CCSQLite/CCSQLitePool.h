//
//  CCSQLitePool.h
//  CCSQLite
//
//  Created by deng you hua on 2/12/17.
//  Copyright © 2017 CC | ccworld1000@gmail.com. All rights reserved.
//

#import <Foundation/Foundation.h>

@class CCSQLite;

/** Pool of `<CCSQLite>` objects.
 
 ### See also
 
 - `<CCSQLiteQueue>`
 - `<CCSQLite>`
 
 @warning Before using `CCSQLitePool`, please consider using `<CCSQLiteQueue>` instead.
 
 If you really really really know what you're doing and `CCSQLitePool` is what
 you really really need (ie, you're using a read only database), OK you can use
 it.  But just be careful not to deadlock!
 
 For an example on deadlocking, search for:
 `ONLY_USE_THE_POOL_IF_YOU_ARE_DOING_READS_OTHERWISE_YOULL_DEADLOCK_USE_CCSQLiteQueue_INSTEAD`
 in the main.m file.
 */

@interface CCSQLitePool : NSObject 

/** Database path */

@property (atomic, copy) NSString *path;

/** Delegate object */

@property (atomic, assign) id delegate;

/** Maximum number of databases to create */

@property (atomic, assign) NSUInteger maximumNumberOfDatabasesToCreate;

/** Open flags */

@property (atomic, readonly) int openFlags;

/**  Custom virtual file system name */

@property (atomic, copy) NSString *vfsName;


///---------------------
/// @name Initialization
///---------------------

/** Create pool using path.
 
 @param aPath The file path of the database.
 
 @return The `CCSQLitePool` object. `nil` on error.
 */

+ (instancetype)databasePoolWithPath:(NSString*)aPath;

/** Create pool using path and specified flags
 
 @param aPath The file path of the database.
 @param openFlags Flags passed to the openWithFlags method of the database
 
 @return The `CCSQLitePool` object. `nil` on error.
 */

+ (instancetype)databasePoolWithPath:(NSString*)aPath flags:(int)openFlags;

/** Create pool using path.
 
 @param aPath The file path of the database.
 
 @return The `CCSQLitePool` object. `nil` on error.
 */

- (instancetype)initWithPath:(NSString*)aPath;

/** Create pool using path and specified flags.
 
 @param aPath The file path of the database.
 @param openFlags Flags passed to the openWithFlags method of the database
 
 @return The `CCSQLitePool` object. `nil` on error.
 */

- (instancetype)initWithPath:(NSString*)aPath flags:(int)openFlags;

/** Create pool using path and specified flags.
 
 @param aPath The file path of the database.
 @param openFlags Flags passed to the openWithFlags method of the database
 @param vfsName The name of a custom virtual file system
 
 @return The `CCSQLitePool` object. `nil` on error.
 */

- (instancetype)initWithPath:(NSString*)aPath flags:(int)openFlags vfs:(NSString *)vfsName;

/** Returns the Class of 'CCSQLite' subclass, that will be used to instantiate database object.
 
 Subclasses can override this method to return specified Class of 'CCSQLite' subclass.
 
 @return The Class of 'CCSQLite' subclass, that will be used to instantiate database object.
 */

+ (Class)databaseClass;

///------------------------------------------------
/// @name Keeping track of checked in/out databases
///------------------------------------------------

/** Number of checked-in databases in pool
 
 @returns Number of databases
 */

- (NSUInteger)countOfCheckedInDatabases;

/** Number of checked-out databases in pool
 
 @returns Number of databases
 */

- (NSUInteger)countOfCheckedOutDatabases;

/** Total number of databases in pool
 
 @returns Number of databases
 */

- (NSUInteger)countOfOpenDatabases;

/** Release all databases in pool */

- (void)releaseAllDatabases;

///------------------------------------------
/// @name Perform database operations in pool
///------------------------------------------

/** Synchronously perform database operations in pool.
 
 @param block The code to be run on the `CCSQLitePool` pool.
 */

- (void)inDatabase:(void (^)(CCSQLite *db))block;

/** Synchronously perform database operations in pool using transaction.
 
 @param block The code to be run on the `CCSQLitePool` pool.
 */

- (void)inTransaction:(void (^)(CCSQLite *db, BOOL *rollback))block;

/** Synchronously perform database operations in pool using deferred transaction.
 
 @param block The code to be run on the `CCSQLitePool` pool.
 */

- (void)inDeferredTransaction:(void (^)(CCSQLite *db, BOOL *rollback))block;

/** Synchronously perform database operations in pool using save point.
 
 @param block The code to be run on the `CCSQLitePool` pool.
 
 @return `NSError` object if error; `nil` if successful.
 
 @warning You can not nest these, since calling it will pull another database out of the pool and you'll get a deadlock. If you need to nest, use `<[CCSQLite startSavePointWithName:error:]>` instead.
 */

- (NSError*)inSavePoint:(void (^)(CCSQLite *db, BOOL *rollback))block;

@end


/** CCSQLitePool delegate category
 
 This is a category that defines the protocol for the CCSQLitePool delegate
 */

@interface NSObject (CCSQLitePoolDelegate)

/** Asks the delegate whether database should be added to the pool.
 
 @param pool     The `CCSQLitePool` object.
 @param database The `CCSQLite` object.
 
 @return `YES` if it should add database to pool; `NO` if not.
 
 */

- (BOOL)databasePool:(CCSQLitePool*)pool shouldAddDatabaseToPool:(CCSQLite*)database;

/** Tells the delegate that database was added to the pool.
 
 @param pool     The `CCSQLitePool` object.
 @param database The `CCSQLite` object.
 
 */

- (void)databasePool:(CCSQLitePool*)pool didAddDatabase:(CCSQLite*)database;

@end
