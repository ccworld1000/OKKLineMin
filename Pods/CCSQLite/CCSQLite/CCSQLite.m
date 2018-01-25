//
//  CCSQLite.m
//  CCSQLite
//
//  Created by deng you hua on 2/11/17.
//  Copyright © 2017 CC | ccworld1000@gmail.com. All rights reserved.
//

#import "CCSQLite.h"

#import "CCSQLite.h"
#import "unistd.h"
#import <objc/runtime.h>

#import <sqlite3.h>

/**
 *  avoid Yapdatabase repeat | [Embeded CCSQLiteCollection]
 *  new add [Embeded CCSQLiteCollection]
 */
NSString * CCSQLiteDatabase2     = @"CCSQLite.Database2";
NSString * CCSQLiteCollection    = @"CCSQLite.Collection";

static int connectionBusyHandler(void * ptr, int count) {
    CCSQLite * currentDatabase = (__bridge CCSQLite *)ptr;

    usleep(50 * 1000); // sleep 50ms

    if (count % 4 == 1) { // log every 4th attempt but not the first one
        NSLog(@"Cannot obtain busy lock on SQLite from database (%p), is another process locking the database? Retrying in 50ms...", currentDatabase);
    }

    return 1;
}

@interface CCSQLite () {
    void * _db;
    NSString * _databasePath;

    BOOL _shouldCacheStatements;
    BOOL _isExecutingStatement;
    BOOL _inTransaction;
    NSTimeInterval _maxBusyRetryTimeInterval;
    NSTimeInterval _startBusyRetryTime;

    NSMutableSet * _openResultSets;
    NSMutableSet * _openFunctions;

    NSDateFormatter * _dateFormat;
}

- (CCResultSet *) executeQuery:(NSString *)sql withArgumentsInArray:(NSArray *)arrayArgs orDictionary:(NSDictionary *)dictionaryArgs orVAList:(va_list)args;
- (BOOL) executeUpdate:(NSString *)sql error:(NSError **)outErr withArgumentsInArray:(NSArray *)arrayArgs orDictionary:(NSDictionary *)dictionaryArgs orVAList:(va_list)args;

@end

@implementation CCSQLite

- (NSString *) databasePath_wal {
    return [[self databasePath] stringByAppendingString:@"-wal"];
}

- (NSString *) databasePath_shm {
    return [[self databasePath] stringByAppendingString:@"-shm"];
}

/**
 * The default serializer & deserializer use NSCoding (NSKeyedArchiver & NSKeyedUnarchiver).
 * Thus the objects need only support the NSCoding protocol.
 **/
+ (CCSQLiteSerializer) defaultSerializer {
    return ^NSData * (NSString __unused * collection, NSString __unused * key, id object){
               return [NSKeyedArchiver archivedDataWithRootObject:object];
    };
}

/**
 * The default serializer & deserializer use NSCoding (NSKeyedArchiver & NSKeyedUnarchiver).
 * Thus the objects need only support the NSCoding protocol.
 **/
+ (CCSQLiteDeserializer) defaultDeserializer {
    return ^id (NSString __unused * collection, NSString __unused * key, NSData * data){
               return data && data.length > 0 ? [NSKeyedUnarchiver unarchiveObjectWithData:data] : nil;
    };
}

/**
 * Property lists ONLY support the following: NSData, NSString, NSArray, NSDictionary, NSDate, and NSNumber.
 * Property lists are highly optimized and are used extensively by Apple.
 *
 * Property lists make a good fit when your existing code already uses them,
 * such as replacing NSUserDefaults with a database.
 **/
+ (CCSQLiteSerializer) propertyListSerializer {
    return ^NSData * (NSString __unused * collection, NSString __unused * key, id object){
               return [NSPropertyListSerialization dataWithPropertyList:object
                                                                 format:NSPropertyListBinaryFormat_v1_0
                                                                options:NSPropertyListImmutable
                                                                  error:NULL];
    };
}

/**
 * Property lists ONLY support the following: NSData, NSString, NSArray, NSDictionary, NSDate, and NSNumber.
 * Property lists are highly optimized and are used extensively by Apple.
 *
 * Property lists make a good fit when your existing code already uses them,
 * such as replacing NSUserDefaults with a database.
 **/
+ (CCSQLiteDeserializer) propertyListDeserializer {
    return ^id (NSString __unused * collection, NSString __unused * key, NSData * data){
               return [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
    };
}

/**
 * A FASTER serializer than the default, if serializing ONLY a NSDate object.
 * You may want to use timestampSerializer & timestampDeserializer if your metadata is simply an NSDate.
 **/
+ (CCSQLiteSerializer) timestampSerializer {
    return ^NSData * (NSString __unused * collection, NSString __unused * key, id object) {

               if ([object isKindOfClass:[NSDate class]]) {
                   NSTimeInterval timestamp = [(NSDate *)object timeIntervalSinceReferenceDate];

                   return [[NSData alloc] initWithBytes:(void *)&timestamp length:sizeof(NSTimeInterval)];
               } else {
                   return [NSKeyedArchiver archivedDataWithRootObject:object];
               }
    };
}

/**
 * A FASTER deserializer than the default, if deserializing data from timestampSerializer.
 * You may want to use timestampSerializer & timestampDeserializer if your metadata is simply an NSDate.
 **/
+ (CCSQLiteDeserializer) timestampDeserializer {
    return ^id (NSString __unused * collection, NSString __unused * key, NSData * data) {

               if ([data length] == sizeof(NSTimeInterval)) {
                   NSTimeInterval timestamp;
                   memcpy((void *)&timestamp, [data bytes], sizeof(NSTimeInterval));

                   return [[NSDate alloc] initWithTimeIntervalSinceReferenceDate:timestamp];
               } else {
                   return [NSKeyedUnarchiver unarchiveObjectWithData:data];
               }
    };
}

+ (CCSQLiteSerializer) jsonSerializer {
    return ^NSData * (NSString * collection, NSString * key, id object) {
               if ([object isKindOfClass:[NSString class]]) {
                   NSString * data = object;
                   return [data dataUsingEncoding:NSUTF8StringEncoding];
               } else if ([object isKindOfClass:[NSData class]]) {
                   return object;
               } else {
                   NSLog(@"error args for object");
                   return nil;
               }
    };
}

+ (CCSQLiteDeserializer) jsonDeserializer {
    return ^id (NSString * collection, NSString * key, NSData * data) {
               NSError * error = nil;
               id object = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error];

               if (error) {
                   NSLog(@"jsonDeserializer : %@", error);;
               }

               return object;
    };
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Setup
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Attempts to open (or create & open) the database connection.
 **/
- (BOOL) openDatabase {
    // Open the database connection.
    //
    // We use SQLITE_OPEN_NOMUTEX to use the multi-thread threading mode,
    // as we will be serializing access to the connection externally.

    int flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX | SQLITE_OPEN_PRIVATECACHE;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincompatible-pointer-types"
    int status = sqlite3_open_v2([[self databasePath] UTF8String], &_db, flags, NULL);
#pragma clang diagnostic pop

    if (status != SQLITE_OK) {
        // There are a few reasons why the database might not open.
        // One possibility is if the database file has become corrupt.

        // Sometimes the open function returns a db to allow us to query it for the error message.
        // The openConfigCreate block will close it for us.
        if (_db) {
            NSLog(@"Error opening database: %d %s", status, sqlite3_errmsg(_db));
        } else {
            NSLog(@"Error opening database: %d", status);
        }

        return NO;
    }
    // Add a busy handler if we are in multiprocess mode
    if (_options.enableMultiProcessSupport) {
        sqlite3_busy_handler(_db, connectionBusyHandler, (__bridge void *)(self));
    }

    return YES;
} /* openDatabase */

/**
 * Configures the database connection.
 * This mainly means enabling WAL mode, and configuring the auto-checkpoint.
 **/
- (BOOL) configureDatabase:(BOOL)isNewDatabaseFile {
    int status;

    // Set mandatory pragmas

    if (isNewDatabaseFile && (_options.pragmaPageSize > 0)) {
        NSString * pragma_page_size =
            [NSString stringWithFormat:@"PRAGMA page_size = %ld;", (long)_options.pragmaPageSize];

        status = sqlite3_exec(_db, [pragma_page_size UTF8String], NULL, NULL, NULL);
        if (status != SQLITE_OK) {
            NSLog(@"Error setting PRAGMA page_size: %d %s", status, sqlite3_errmsg(_db));
        }
    }

#if SQLITE_VERSION_NUMBER >= 3007000
    status = sqlite3_exec(_db, "PRAGMA journal_mode = WAL;", NULL, NULL, NULL);
    if (status != SQLITE_OK) {
        NSLog(@"Error setting PRAGMA journal_mode: %d %s", status, sqlite3_errmsg(_db));
        return NO;
    } else if (status == SQLITE_READONLY) {
        NSLog(@"Attempt to write a readonly database : close journal_mode. or At the same time increase the database read and write permissions ");
        status = SQLITE_OK;
    }
#endif

    if (isNewDatabaseFile) {
        status = sqlite3_exec(_db, "PRAGMA auto_vacuum = FULL; VACUUM;", NULL, NULL, NULL);
        if (status != SQLITE_OK) {
            NSLog(@"Error setting PRAGMA auto_vacuum: %d %s", status, sqlite3_errmsg(_db));
        }
    }

    // Set synchronous to normal for THIS sqlite instance.
    //
    // This does NOT affect normal connections.
    // That is, this does NOT affect YapDatabaseConnection instances.
    // The sqlite connections of normal YapDatabaseConnection instances will follow the set pragmaSynchronous value.
    //
    // The reason we hardcode normal for this sqlite instance is because
    // it's only used to write the initial snapshot value.
    // And this doesn't need to be durable, as it is initialized to zero everytime.
    //
    // (This sqlite db is also used to perform checkpoints.
    //  But a normal value won't affect these operations,
    //  as they will perform sync operations whether the connection is normal or full.)

    status = sqlite3_exec(_db, "PRAGMA synchronous = NORMAL;", NULL, NULL, NULL);
    if (status != SQLITE_OK) {
        NSLog(@"Error setting PRAGMA synchronous: %d %s", status, sqlite3_errmsg(_db));
        // This isn't critical, so we can continue.
    }

    // Set journal_size_imit.
    //
    // We only need to do set this pragma for THIS connection,
    // because it is the only connection that performs checkpoints.

    NSString * pragma_journal_size_limit =
        [NSString stringWithFormat:@"PRAGMA journal_size_limit = %ld;", (long)_options.pragmaJournalSizeLimit];

    status = sqlite3_exec(_db, [pragma_journal_size_limit UTF8String], NULL, NULL, NULL);
    if (status != SQLITE_OK) {
        NSLog(@"Error setting PRAGMA journal_size_limit: %d %s", status, sqlite3_errmsg(_db));
        // This isn't critical, so we can continue.
    }

    // Set mmap_size (if needed).
    //
    // This configures memory mapped I/O.

    if (_options.pragmaMMapSize > 0) {
        NSString * pragma_mmap_size =
            [NSString stringWithFormat:@"PRAGMA mmap_size = %ld;", (long)_options.pragmaMMapSize];

        status = sqlite3_exec(_db, [pragma_mmap_size UTF8String], NULL, NULL, NULL);
        if (status != SQLITE_OK) {
            NSLog(@"Error setting PRAGMA mmap_size: %d %s", status, sqlite3_errmsg(_db));
            // This isn't critical, so we can continue.
        }
    }

    // Disable autocheckpointing.
    //
    // YapDatabase has its own optimized checkpointing algorithm built-in.
    // It knows the state of every active connection for the database,
    // so it can invoke the checkpoint methods at the precise time in which a checkpoint can be most effective.

#if SQLITE_VERSION_NUMBER >= 3007000
    sqlite3_wal_autocheckpoint(_db, 0);
#endif

    return YES;
} /* configureDatabase */


#ifdef SQLITE_HAS_CODEC
/**
 * Configures database encryption via SQLCipher.
 **/
- (BOOL) configureEncryptionForDatabase:(sqlite3 *)sqlite {
    if (_options.cipherKeyBlock) {
        NSData * keyData = _options.cipherKeyBlock();

        if (keyData == nil) {
            NSAssert(NO, @"CCOptions.cipherKeyBlock cannot return nil!");
            return NO;
        }

        // Setting the PBKDF2 default iteration number (this will have effect next time database is opened)
        if (_options.cipherDefaultkdfIterNumber > 0) {
            char * errorMsg;
            NSString * pragmaCommand = [NSString stringWithFormat:@"PRAGMA cipher_default_kdf_iter = %lu", (unsigned long)_options.cipherDefaultkdfIterNumber];
            if (sqlite3_exec(sqlite, [pragmaCommand UTF8String], NULL, NULL, &errorMsg) != SQLITE_OK) {
                NSLog(@"failed to set database cipher_default_kdf_iter: %s", errorMsg);
                return NO;
            }
        }

        // Setting the PBKDF2 iteration number
        if (_options.kdfIterNumber > 0) {
            char * errorMsg;
            NSString * pragmaCommand = [NSString stringWithFormat:@"PRAGMA kdf_iter = %lu", (unsigned long)_options.kdfIterNumber];
            if (sqlite3_exec(sqlite, [pragmaCommand UTF8String], NULL, NULL, &errorMsg) != SQLITE_OK) {
                NSLog(@"failed to set database kdf_iter: %s", errorMsg);
                return NO;
            }
        }

        // Setting the encrypted database page size
        if (_options.cipherPageSize > 0) {
            char * errorMsg;
            NSString * pragmaCommand = [NSString stringWithFormat:@"PRAGMA cipher_page_size = %lu", (unsigned long)_options.cipherPageSize];
            if (sqlite3_exec(sqlite, [pragmaCommand UTF8String], NULL, NULL, &errorMsg) != SQLITE_OK) {
                NSLog(@"failed to set database cipher_page_size: %s", errorMsg);
                return NO;
            }
        }

        int status = sqlite3_key(sqlite, [keyData bytes], (int)[keyData length]);
        if (status != SQLITE_OK) {
            NSLog(@"Error setting SQLCipher key: %d %s", status, sqlite3_errmsg(sqlite));
            return NO;
        }
    }

    return YES;
} /* configureEncryptionForDatabase */
#endif /* ifdef SQLITE_HAS_CODEC */

/**
 * Creates the database tables we need:
 *
 * - yap2      : stores snapshot and metadata for extensions
 * - CCSQLite.Database2 : stores collection/key/value/metadata rows
 **/
- (BOOL) createTables {
    int status;

    char * createDatabaseTableStatement =
        "CREATE TABLE IF NOT EXISTS \"CCSQLite.Database2\""
        " (\"rowid\" INTEGER PRIMARY KEY,"
        "  \"collection\" CHAR NOT NULL,"
        "  \"key\" CHAR NOT NULL,"
        "  \"data\" BLOB,"
        "  \"metadata\" BLOB"
        " );";

    status = sqlite3_exec(_db, createDatabaseTableStatement, NULL, NULL, NULL);
    if (status != SQLITE_OK) {
        NSLog(@"Failed creating 'CCSQLite.Database2' table: %d %s", status, sqlite3_errmsg(_db));
        return NO;
    }

    char * createIndexStatement =
        "CREATE UNIQUE INDEX IF NOT EXISTS \"true_primary_key\" ON \"CCSQLite.Database2\" ( \"collection\", \"key\" );";

    status = sqlite3_exec(_db, createIndexStatement, NULL, NULL, NULL);
    if (status != SQLITE_OK) {
        NSLog(@"Failed creating index on 'CCSQLite.Database2' table: %d %s", status, sqlite3_errmsg(_db));
        return NO;
    }

    return YES;
} /* createTables */

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#pragma mark Init
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// - (id)initWithPath:(NSString *)inPath
// {
//    return [self initWithPath:inPath
//             objectSerializer:NULL
//           objectDeserializer:NULL
//           metadataSerializer:NULL
//         metadataDeserializer:NULL
//           objectPreSanitizer:NULL
//          objectPostSanitizer:NULL
//         metadataPreSanitizer:NULL
//        metadataPostSanitizer:NULL
//                      options:nil];
// }

- (id) initWithPath:(NSString *)inPath
    options:(nullable CCOptions *)inOptions {
    return [self initWithPath:inPath
                objectSerializer:NULL
              objectDeserializer:NULL
              metadataSerializer:NULL
            metadataDeserializer:NULL
              objectPreSanitizer:NULL
             objectPostSanitizer:NULL
            metadataPreSanitizer:NULL
           metadataPostSanitizer:NULL
                         options:inOptions];
}

- (id) initWithPath:(NSString *)inPath
    serializer:(CCSQLiteSerializer)inSerializer
    deserializer:(CCSQLiteDeserializer)inDeserializer {
    return [self initWithPath:inPath
                objectSerializer:inSerializer
              objectDeserializer:inDeserializer
              metadataSerializer:inSerializer
            metadataDeserializer:inDeserializer
              objectPreSanitizer:NULL
             objectPostSanitizer:NULL
            metadataPreSanitizer:NULL
           metadataPostSanitizer:NULL
                         options:nil];
}

- (id) initWithPath:(NSString *)inPath
    serializer:(CCSQLiteSerializer)inSerializer
    deserializer:(CCSQLiteDeserializer)inDeserializer
    options:(CCOptions *)inOptions {
    return [self initWithPath:inPath
                objectSerializer:inSerializer
              objectDeserializer:inDeserializer
              metadataSerializer:inSerializer
            metadataDeserializer:inDeserializer
              objectPreSanitizer:NULL
             objectPostSanitizer:NULL
            metadataPreSanitizer:NULL
           metadataPostSanitizer:NULL
                         options:inOptions];
}

- (id) initWithPath:(NSString *)inPath
    serializer:(CCSQLiteSerializer)inSerializer
    deserializer:(CCSQLiteDeserializer)inDeserializer
    preSanitizer:(CCSQLitePreSanitizerr)inPreSanitizer
    postSanitizer:(CCSQLitePostSanitizer)inPostSanitizer
    options:(CCOptions *)inOptions {
    return [self initWithPath:inPath
                objectSerializer:inSerializer
              objectDeserializer:inDeserializer
              metadataSerializer:inSerializer
            metadataDeserializer:inDeserializer
              objectPreSanitizer:inPreSanitizer
             objectPostSanitizer:inPostSanitizer
            metadataPreSanitizer:inPreSanitizer
           metadataPostSanitizer:inPostSanitizer
                         options:inOptions];
}

- (id) initWithPath:(NSString *)inPath objectSerializer:(CCSQLiteSerializer)inObjectSerializer
    objectDeserializer:(CCSQLiteDeserializer)inObjectDeserializer
    metadataSerializer:(CCSQLiteSerializer)inMetadataSerializer
    metadataDeserializer:(CCSQLiteDeserializer)inMetadataDeserializer {
    return [self initWithPath:inPath
                objectSerializer:inObjectSerializer
              objectDeserializer:inObjectDeserializer
              metadataSerializer:inMetadataSerializer
            metadataDeserializer:inMetadataDeserializer
              objectPreSanitizer:NULL
             objectPostSanitizer:NULL
            metadataPreSanitizer:NULL
           metadataPostSanitizer:NULL
                         options:nil];
}

- (id) initWithPath:(NSString *)inPath objectSerializer:(CCSQLiteSerializer)inObjectSerializer
    objectDeserializer:(CCSQLiteDeserializer)inObjectDeserializer
    metadataSerializer:(CCSQLiteSerializer)inMetadataSerializer
    metadataDeserializer:(CCSQLiteDeserializer)inMetadataDeserializer
    options:(CCOptions *)inOptions {
    return [self initWithPath:inPath
                objectSerializer:inObjectSerializer
              objectDeserializer:inObjectDeserializer
              metadataSerializer:inMetadataSerializer
            metadataDeserializer:inMetadataDeserializer
              objectPreSanitizer:NULL
             objectPostSanitizer:NULL
            metadataPreSanitizer:NULL
           metadataPostSanitizer:NULL
                         options:inOptions];
}

- (id) initWithPath:(NSString *)inPath objectSerializer:(CCSQLiteSerializer)inObjectSerializer
    objectDeserializer:(CCSQLiteDeserializer)inObjectDeserializer
    metadataSerializer:(CCSQLiteSerializer)inMetadataSerializer
    metadataDeserializer:(CCSQLiteDeserializer)inMetadataDeserializer
    objectPreSanitizer:(CCSQLitePreSanitizerr)inObjectPreSanitizer
    objectPostSanitizer:(CCSQLitePostSanitizer)inObjectPostSanitizer
    metadataPreSanitizer:(CCSQLitePreSanitizerr)inMetadataPreSanitizer
    metadataPostSanitizer:(CCSQLitePostSanitizer)inMetadataPostSanitizer
    options:(CCOptions *)inOptions {
    // First, standardize path.
    // This allows clients to be lazy when passing paths.
    NSString * path = [inPath stringByStandardizingPath];

    if ((self = [super init])) {
        _databasePath = path;
        _options = inOptions ? [inOptions copy] : [[CCOptions alloc] init];

        __block BOOL isNewDatabaseFile = ![[NSFileManager defaultManager] fileExistsAtPath:[self databasePath]];

        BOOL (^ openConfigCreate)(void) = ^BOOL (void) { @autoreleasepool {

                                                             BOOL result = YES;

                                                             if (result) result = [self openDatabase];
#ifdef SQLITE_HAS_CODEC
                                                             if (result) result = [self configureEncryptionForDatabase:_db];
#endif
                                                             if (result) result = [self configureDatabase:isNewDatabaseFile];
                                                             if (result) result = [self createTables];

                                                             if (!result && _db) {
                                                                 sqlite3_close(_db);
                                                                 _db = NULL;
                                                             }

                                                             return result;
                                                         } };

        BOOL result = openConfigCreate();
        if (!result) {
            // There are a few reasons why the database might not open.
            // One possibility is if the database file has become corrupt.

            if (_options.corruptAction == CCOptionsCorruptAction_Fail) {
                // Fail - do not try to resolve
            } else if (_options.corruptAction == CCOptionsCorruptAction_Rename) {
                // Try to rename the corrupt database file.

                BOOL renamed = NO;
                BOOL failed = NO;

                NSString * newDatabasePath = nil;
                int i = 0;

                do {
                    NSString * extension = [NSString stringWithFormat:@"%d.corrupt", i];
                    newDatabasePath = [[self databasePath] stringByAppendingPathExtension:extension];

                    if ([[NSFileManager defaultManager] fileExistsAtPath:newDatabasePath]) {
                        i++;
                    } else {
                        NSError * error = nil;
                        renamed = [[NSFileManager defaultManager] moveItemAtPath:[self databasePath]
                                                                          toPath:newDatabasePath
                                                                           error:&error];
                        if (!renamed) {
                            failed = YES;
                            NSLog(@"Error renaming corrupt database file: (%@ -> %@) %@",
                                  [[self databasePath] lastPathComponent], [newDatabasePath lastPathComponent], error);
                        }
                    }

                } while (i < INT_MAX && !renamed && !failed);

                if (renamed) {
                    isNewDatabaseFile = YES;
                    result = openConfigCreate();
                    if (result) {
                        NSLog(@"Database corruption resolved. Renamed corrupt file. (newDB=%@) (corruptDB=%@)",
                              [[self databasePath] lastPathComponent], [newDatabasePath lastPathComponent]);
                    } else {
                        NSLog(@"Database corruption unresolved. (name=%@)", [[self databasePath] lastPathComponent]);
                    }
                }

            } else { // if (options.corruptAction == CCOptionsCorruptAction_Delete)
                     // Try to delete the corrupt database file.

                NSError * error = nil;
                BOOL deleted = [[NSFileManager defaultManager] removeItemAtPath:path error:&error];

                if (deleted) {
                    isNewDatabaseFile = YES;
                    result = openConfigCreate();
                    if (result) {
                        NSLog(@"Database corruption resolved. Deleted corrupt file. (name=%@)",
                              [[self databasePath] lastPathComponent]);
                    } else {
                        NSLog(@"Database corruption unresolved. (name=%@)", [[self databasePath] lastPathComponent]);
                    }
                } else {
                    NSLog(@"Error deleting corrupt database file: %@", error);
                }
            }
        }
        if (!result) {
            return nil;
        }


        // Initialize variables

        CCSQLiteSerializer defaultSerializer     = nil;
        CCSQLiteDeserializer defaultDeserializer = nil;

        if (!inObjectSerializer || !inMetadataSerializer)
            defaultSerializer = [[self class] defaultSerializer];

        if (!inObjectDeserializer || !inMetadataDeserializer)
            defaultDeserializer = [[self class] defaultDeserializer];

        _objectSerializer = (CCSQLiteSerializer)[inObjectSerializer copy] ? : defaultSerializer;
        _objectDeserializer = (CCSQLiteDeserializer)[inObjectDeserializer copy] ? : defaultDeserializer;

        _metadataSerializer = (CCSQLiteSerializer)[inMetadataSerializer copy] ? : defaultSerializer;
        _metadataDeserializer = (CCSQLiteDeserializer)[inMetadataDeserializer copy] ? : defaultDeserializer;

        _objectPreSanitizer = (CCSQLitePreSanitizerr)[inObjectPreSanitizer copy];
        _objectPostSanitizer = (CCSQLitePostSanitizer)[inObjectPostSanitizer copy];

        _metadataPreSanitizer = (CCSQLitePreSanitizerr)[inMetadataPreSanitizer copy];
        _metadataPostSanitizer = (CCSQLitePostSanitizer)[inMetadataPostSanitizer copy];

    }
    return self;
} /* initWithPath */

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#pragma mark CCSQLite instantiation and deallocation

+ (instancetype) databaseWithPath:(NSString *)aPath {
    return CCReturnAutoreleased([[self alloc] initWithPath:aPath]);
}

- (instancetype) init {
    return [self initWithPath:nil];
}

- (instancetype) initWithPath:(NSString *)aPath {

    assert(sqlite3_threadsafe()); // whoa there big boy- gotta make sure sqlite it happy with what we're going to do.

    self = [super init];

    if (self) {
        _databasePath               = [aPath copy];
        _openResultSets             = [[NSMutableSet alloc] init];
        _db                         = nil;
        _logsErrors                 = YES;
        _crashOnErrors              = NO;
        _maxBusyRetryTimeInterval   = 2;
    }

    return [self initWithPath:aPath
                objectSerializer:NULL
              objectDeserializer:NULL
              metadataSerializer:NULL
            metadataDeserializer:NULL
              objectPreSanitizer:NULL
             objectPostSanitizer:NULL
            metadataPreSanitizer:NULL
           metadataPostSanitizer:NULL
                         options:nil];

    return self;
} /* initWithPath */

- (void) dealloc {
    [self close];
    CCRelease(_openResultSets);
    CCRelease(_cachedStatements);
    CCRelease(_dateFormat);
    CCRelease(_databasePath);
    CCRelease(_openFunctions);
}

- (NSString *) databasePath {
    return _databasePath;
}

+ (NSString *) CCUserVersion {
    return @"1.1.1";
}

// returns 0x0240 for version 2.4.  This makes it super easy to do things like:
// /* need to make sure to do X with CCSQLite version 2.4 or later */
// if ([CCSQLite CCVersion] >= 0x0240) { … }

+ (SInt32) CCVersion {

    // we go through these hoops so that we only have to change the version number in a single spot.
    static dispatch_once_t once;
    static SInt32 CCVersionVal = 0;

    dispatch_once(&once, ^{
        NSString * prodVersion = [self CCUserVersion];

        if ([[prodVersion componentsSeparatedByString:@"."] count] < 3) {
            prodVersion = [prodVersion stringByAppendingString:@".0"];
        }

        NSString * junk = [prodVersion stringByReplacingOccurrencesOfString:@"." withString:@""];

        char * e = nil;
        CCVersionVal = (int)strtoul([junk UTF8String], &e, 16);

    });

    return CCVersionVal;
} /* CCVersion */

#pragma mark SQLite information

+ (NSString *) sqliteLibVersion {
    return [NSString stringWithFormat:@"%s", sqlite3_libversion()];
}

+ (BOOL) isSQLiteThreadSafe {
    // make sure to read the sqlite headers on this guy!
    return sqlite3_threadsafe() != 0;
}

- (void *) sqliteHandle {
    return _db;
}

- (const char *) sqlitePath {

    if (!_databasePath) {
        return ":memory:";
    }

    if ([_databasePath length] == 0) {
        return ""; // this creates a temporary database (it's an sqlite thing).
    }

    return [_databasePath fileSystemRepresentation];

}

#pragma mark Open and close database

- (BOOL) open {
    if (_db) {
        return YES;
    }

    int err = sqlite3_open([self sqlitePath], (sqlite3 **)&_db);
    if (err != SQLITE_OK) {
        NSLog(@"error opening!: %d", err);
        return NO;
    }

    if (_maxBusyRetryTimeInterval > 0.0) {
        // set the handler
        [self setMaxBusyRetryTimeInterval:_maxBusyRetryTimeInterval];
    }


    return YES;
}

- (BOOL) openWithFlags:(int)flags {
    return [self openWithFlags:flags vfs:nil];
}
- (BOOL) openWithFlags:(int)flags vfs:(NSString *)vfsName {
#if SQLITE_VERSION_NUMBER >= 3005000
    if (_db) {
        return YES;
    }

    int err = sqlite3_open_v2([self sqlitePath], (sqlite3 **)&_db, flags, [vfsName UTF8String]);
    if (err != SQLITE_OK) {
        NSLog(@"error opening!: %d", err);
        return NO;
    }

    if (_maxBusyRetryTimeInterval > 0.0) {
        // set the handler
        [self setMaxBusyRetryTimeInterval:_maxBusyRetryTimeInterval];
    }

    return YES;
#else
    NSLog(@"openWithFlags requires SQLite 3.5");
    return NO;
#endif
} /* openWithFlags */


- (BOOL) close {

    [self clearCachedStatements];
    [self closeOpenResultSets];

    if (!_db) {
        return YES;
    }

    int rc;
    BOOL retry;
    BOOL triedFinalizingOpenStatements = NO;

    do {
        retry   = NO;
        rc      = sqlite3_close(_db);
        if (SQLITE_BUSY == rc || SQLITE_LOCKED == rc) {
            if (!triedFinalizingOpenStatements) {
                triedFinalizingOpenStatements = YES;
                sqlite3_stmt * pStmt;
                while ((pStmt = sqlite3_next_stmt(_db, nil)) != 0) {
                    NSLog(@"Closing leaked statement");
                    sqlite3_finalize(pStmt);
                    retry = YES;
                }
            }
        } else if (SQLITE_OK != rc) {
            NSLog(@"error closing!: %d", rc);
        }
    } while (retry);

    _db = nil;
    return YES;
} /* close */

#pragma mark Busy handler routines

// NOTE: appledoc seems to choke on this function for some reason;
//       so when generating documentation, you might want to ignore the
//       .m files so that it only documents the public interfaces outlined
//       in the .h files.
//
//       This is a known appledoc bug that it has problems with C functions
//       within a class implementation, but for some reason, only this
//       C function causes problems; the rest don't. Anyway, ignoring the .m
//       files with appledoc will prevent this problem from occurring.

static int CCDatabaseBusyHandler(void * f, int count) {
    CCSQLite * self = (__bridge CCSQLite *)f;

    if (count == 0) {
        self->_startBusyRetryTime = [NSDate timeIntervalSinceReferenceDate];
        return 1;
    }

    NSTimeInterval delta = [NSDate timeIntervalSinceReferenceDate] - (self->_startBusyRetryTime);

    if (delta < [self maxBusyRetryTimeInterval]) {
        int requestedSleepInMillseconds = (int)arc4random_uniform(50) + 50;
        int actualSleepInMilliseconds = sqlite3_sleep(requestedSleepInMillseconds);
        if (actualSleepInMilliseconds != requestedSleepInMillseconds) {
            NSLog(@"WARNING: Requested sleep of %i milliseconds, but SQLite returned %i. Maybe SQLite wasn't built with HAVE_USLEEP=1?", requestedSleepInMillseconds, actualSleepInMilliseconds);
        }
        return 1;
    }

    return 0;
} /* CCDatabaseBusyHandler */

- (void) setMaxBusyRetryTimeInterval:(NSTimeInterval)timeout {

    _maxBusyRetryTimeInterval = timeout;

    if (!_db) {
        return;
    }

    if (timeout > 0) {
        sqlite3_busy_handler(_db, &CCDatabaseBusyHandler, (__bridge void *)(self));
    } else {
        // turn it off otherwise
        sqlite3_busy_handler(_db, nil, nil);
    }
}

- (NSTimeInterval) maxBusyRetryTimeInterval {
    return _maxBusyRetryTimeInterval;
}


// we no longer make busyRetryTimeout public
// but for folks who don't bother noticing that the interface to CCSQLite changed,
// we'll still implement the method so they don't get suprise crashes
- (int) busyRetryTimeout {
    NSLog(@"%s:%d", __FUNCTION__, __LINE__);
    NSLog(@"CCSQLite: busyRetryTimeout no longer works, please use maxBusyRetryTimeInterval");
    return -1;
}

- (void) setBusyRetryTimeout:(int)i {
#pragma unused(i)
    NSLog(@"%s:%d", __FUNCTION__, __LINE__);
    NSLog(@"CCSQLite: setBusyRetryTimeout does nothing, please use setMaxBusyRetryTimeInterval:");
}

#pragma mark Result set functions

- (BOOL) hasOpenResultSets {
    return [_openResultSets count] > 0;
}

- (void) closeOpenResultSets {

    // Copy the set so we don't get mutation errors
    NSSet * openSetCopy = CCReturnAutoreleased([_openResultSets copy]);

    for (NSValue * rsInWrappedInATastyValueMeal in openSetCopy) {
        CCResultSet * rs = (CCResultSet *)[rsInWrappedInATastyValueMeal pointerValue];

        [rs setParentDB:nil];
        [rs close];

        [_openResultSets removeObject:rsInWrappedInATastyValueMeal];
    }
}

- (void) resultSetDidClose:(CCResultSet *)resultSet {
    NSValue * setValue = [NSValue valueWithNonretainedObject:resultSet];

    [_openResultSets removeObject:setValue];
}

#pragma mark Cached statements

- (void) clearCachedStatements {

    for (NSMutableSet * statements in [_cachedStatements objectEnumerator]) {
        for (CCStatement * statement in [statements allObjects]) {
            [statement close];
        }
    }

    [_cachedStatements removeAllObjects];
}

- (CCStatement *) cachedStatementForQuery:(NSString *)query {

    NSMutableSet * statements = [_cachedStatements objectForKey:query];

    return [[statements objectsPassingTest:^BOOL (CCStatement * statement, BOOL * stop) {

                 *stop = ![statement inUse];
                 return *stop;

             }] anyObject];
}


- (void) setCachedStatement:(CCStatement *)statement forQuery:(NSString *)query {

    query = [query copy]; // in case we got handed in a mutable string...
    [statement setQuery:query];

    NSMutableSet * statements = [_cachedStatements objectForKey:query];
    if (!statements) {
        statements = [NSMutableSet set];
    }

    [statements addObject:statement];

    [_cachedStatements setObject:statements forKey:query];

    CCRelease(query);
}

#pragma mark Key routines

- (BOOL) rekey:(NSString *)key {
    NSData * keyData = [NSData dataWithBytes:(void *)[key UTF8String] length:(NSUInteger)strlen([key UTF8String])];

    return [self rekeyWithData:keyData];
}

- (BOOL) rekeyWithData:(NSData *)keyData {
#ifdef SQLITE_HAS_CODEC
    if (!keyData) {
        return NO;
    }

    int rc = sqlite3_rekey(_db, [keyData bytes], (int)[keyData length]);

    if (rc != SQLITE_OK) {
        NSLog(@"error on rekey: %d", rc);
        NSLog(@"%@", [self lastErrorMessage]);
    }

    return (rc == SQLITE_OK);
#else
#pragma unused(keyData)
    return NO;
#endif
}

- (BOOL) setKey:(NSString *)key {
    NSData * keyData = [NSData dataWithBytes:[key UTF8String] length:(NSUInteger)strlen([key UTF8String])];

    return [self setKeyWithData:keyData];
}

- (BOOL) setKeyWithData:(NSData *)keyData {
#ifdef SQLITE_HAS_CODEC
    if (!keyData) {
        return NO;
    }

    int rc = sqlite3_key(_db, [keyData bytes], (int)[keyData length]);

    return (rc == SQLITE_OK);
#else
#pragma unused(keyData)
    return NO;
#endif
}

#pragma mark Date routines

+ (NSDateFormatter *) storeableDateFormat:(NSString *)format {

    NSDateFormatter * result = CCReturnAutoreleased([[NSDateFormatter alloc] init]);

    result.dateFormat = format;
    result.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    result.locale = CCReturnAutoreleased([[NSLocale alloc] initWithLocaleIdentifier:@"en_US"]);
    return result;
}


- (BOOL) hasDateFormatter {
    return _dateFormat != nil;
}

- (void) setDateFormat:(NSDateFormatter *)format {
    CCAutorelease(_dateFormat);
    _dateFormat = CCReturnRetained(format);
}

- (NSDate *) dateFromString:(NSString *)s {
    return [_dateFormat dateFromString:s];
}

- (NSString *) stringFromDate:(NSDate *)date {
    return [_dateFormat stringFromDate:date];
}

#pragma mark State of database

- (BOOL) goodConnection {

    if (!_db) {
        return NO;
    }

    CCResultSet * rs = [self executeQuery:@"select name from sqlite_master where type='table'"];

    if (rs) {
        [rs close];
        return YES;
    }

    return NO;
}

- (void) warnInUse {
    NSLog(@"The CCSQLite %@ is currently in use.", self);

#ifndef NS_BLOCK_ASSERTIONS
    if (_crashOnErrors) {
        NSAssert(false, @"The CCSQLite %@ is currently in use.", self);
        abort();
    }
#endif
}

- (BOOL) databaseExists {

    if (!_db) {

        NSLog(@"The CCSQLite %@ is not open.", self);

#ifndef NS_BLOCK_ASSERTIONS
        if (_crashOnErrors) {
            NSAssert(false, @"The CCSQLite %@ is not open.", self);
            abort();
        }
#endif

        return NO;
    }

    return YES;
}

#pragma mark Error routines

- (NSString *) lastErrorMessage {
    return [NSString stringWithUTF8String:sqlite3_errmsg(_db)];
}

- (BOOL) hadError {
    int lastErrCode = [self lastErrorCode];

    return (lastErrCode > SQLITE_OK && lastErrCode < SQLITE_ROW);
}

- (int) lastErrorCode {
    return sqlite3_errcode(_db);
}

- (int) lastExtendedErrorCode {
    return sqlite3_extended_errcode(_db);
}

- (NSError *) errorWithMessage:(NSString *)message {
    NSDictionary * errorMessage = [NSDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey];

    return [NSError errorWithDomain:@"CCSQLite" code:sqlite3_errcode(_db) userInfo:errorMessage];
}

- (NSError *) lastError {
    return [self errorWithMessage:[self lastErrorMessage]];
}

#pragma mark Update information routines

- (sqlite_int64) lastInsertRowId {

    if (_isExecutingStatement) {
        [self warnInUse];
        return NO;
    }

    _isExecutingStatement = YES;

    sqlite_int64 ret = sqlite3_last_insert_rowid(_db);

    _isExecutingStatement = NO;

    return ret;
}

- (int) changes {
    if (_isExecutingStatement) {
        [self warnInUse];
        return 0;
    }

    _isExecutingStatement = YES;

    int ret = sqlite3_changes(_db);

    _isExecutingStatement = NO;

    return ret;
}

#pragma mark SQL manipulation

- (void) bindObject:(id)obj toColumn:(int)idx inStatement:(sqlite3_stmt *)pStmt {

    if ((!obj) || ((NSNull *)obj == [NSNull null])) {
        sqlite3_bind_null(pStmt, idx);
    }
    // FIXME - someday check the return codes on these binds.
    else if ([obj isKindOfClass:[NSData class]]) {
        const void * bytes = [obj bytes];
        if (!bytes) {
            // it's an empty NSData object, aka [NSData data].
            // Don't pass a NULL pointer, or sqlite will bind a SQL null instead of a blob.
            bytes = "";
        }
        sqlite3_bind_blob(pStmt, idx, bytes, (int)[obj length], SQLITE_STATIC);
    } else if ([obj isKindOfClass:[NSDate class]]) {
        if (self.hasDateFormatter)
            sqlite3_bind_text(pStmt, idx, [[self stringFromDate:obj] UTF8String], -1, SQLITE_STATIC);
        else
            sqlite3_bind_double(pStmt, idx, [obj timeIntervalSince1970]);
    } else if ([obj isKindOfClass:[NSNumber class]]) {

        if (strcmp([obj objCType], @encode(char)) == 0) {
            sqlite3_bind_int(pStmt, idx, [obj charValue]);
        } else if (strcmp([obj objCType], @encode(unsigned char)) == 0) {
            sqlite3_bind_int(pStmt, idx, [obj unsignedCharValue]);
        } else if (strcmp([obj objCType], @encode(short)) == 0) {
            sqlite3_bind_int(pStmt, idx, [obj shortValue]);
        } else if (strcmp([obj objCType], @encode(unsigned short)) == 0) {
            sqlite3_bind_int(pStmt, idx, [obj unsignedShortValue]);
        } else if (strcmp([obj objCType], @encode(int)) == 0) {
            sqlite3_bind_int(pStmt, idx, [obj intValue]);
        } else if (strcmp([obj objCType], @encode(unsigned int)) == 0) {
            sqlite3_bind_int64(pStmt, idx, (long long)[obj unsignedIntValue]);
        } else if (strcmp([obj objCType], @encode(long)) == 0) {
            sqlite3_bind_int64(pStmt, idx, [obj longValue]);
        } else if (strcmp([obj objCType], @encode(unsigned long)) == 0) {
            sqlite3_bind_int64(pStmt, idx, (long long)[obj unsignedLongValue]);
        } else if (strcmp([obj objCType], @encode(long long)) == 0) {
            sqlite3_bind_int64(pStmt, idx, [obj longLongValue]);
        } else if (strcmp([obj objCType], @encode(unsigned long long)) == 0) {
            sqlite3_bind_int64(pStmt, idx, (long long)[obj unsignedLongLongValue]);
        } else if (strcmp([obj objCType], @encode(float)) == 0) {
            sqlite3_bind_double(pStmt, idx, [obj floatValue]);
        } else if (strcmp([obj objCType], @encode(double)) == 0) {
            sqlite3_bind_double(pStmt, idx, [obj doubleValue]);
        } else if (strcmp([obj objCType], @encode(BOOL)) == 0) {
            sqlite3_bind_int(pStmt, idx, ([obj boolValue] ? 1 : 0));
        } else {
            sqlite3_bind_text(pStmt, idx, [[obj description] UTF8String], -1, SQLITE_STATIC);
        }
    } else {
        sqlite3_bind_text(pStmt, idx, [[obj description] UTF8String], -1, SQLITE_STATIC);
    }
} /* bindObject */

- (void) extractSQL:(NSString *)sql argumentsList:(va_list)args intoString:(NSMutableString *)cleanedSQL arguments:(NSMutableArray *)arguments {

    NSUInteger length = [sql length];
    unichar last = '\0';

    for (NSUInteger i = 0; i < length; ++i) {
        id arg = nil;
        unichar current = [sql characterAtIndex:i];
        unichar add = current;
        if (last == '%') {
            switch (current) {
                case '@':
                    arg = va_arg(args, id);
                    break;
                case 'c':
                    // warning: second argument to 'va_arg' is of promotable type 'char'; this va_arg has undefined behavior because arguments will be promoted to 'int'
                    arg = [NSString stringWithFormat:@"%c", va_arg(args, int)];
                    break;
                case 's':
                    arg = [NSString stringWithUTF8String:va_arg(args, char *)];
                    break;
                case 'd':
                case 'D':
                case 'i':
                    arg = [NSNumber numberWithInt:va_arg(args, int)];
                    break;
                case 'u':
                case 'U':
                    arg = [NSNumber numberWithUnsignedInt:va_arg(args, unsigned int)];
                    break;
                case 'h':
                    i++;
                    if (i < length && [sql characterAtIndex:i] == 'i') {
                        //  warning: second argument to 'va_arg' is of promotable type 'short'; this va_arg has undefined behavior because arguments will be promoted to 'int'
                        arg = [NSNumber numberWithShort:(short)(va_arg(args, int))];
                    } else if (i < length && [sql characterAtIndex:i] == 'u') {
                        // warning: second argument to 'va_arg' is of promotable type 'unsigned short'; this va_arg has undefined behavior because arguments will be promoted to 'int'
                        arg = [NSNumber numberWithUnsignedShort:(unsigned short)(va_arg(args, uint))];
                    } else {
                        i--;
                    }
                    break;
                case 'q':
                    i++;
                    if (i < length && [sql characterAtIndex:i] == 'i') {
                        arg = [NSNumber numberWithLongLong:va_arg(args, long long)];
                    } else if (i < length && [sql characterAtIndex:i] == 'u') {
                        arg = [NSNumber numberWithUnsignedLongLong:va_arg(args, unsigned long long)];
                    } else {
                        i--;
                    }
                    break;
                case 'f':
                    arg = [NSNumber numberWithDouble:va_arg(args, double)];
                    break;
                case 'g':
                    // warning: second argument to 'va_arg' is of promotable type 'float'; this va_arg has undefined behavior because arguments will be promoted to 'double'
                    arg = [NSNumber numberWithFloat:(float)(va_arg(args, double))];
                    break;
                case 'l':
                    i++;
                    if (i < length) {
                        unichar next = [sql characterAtIndex:i];
                        if (next == 'l') {
                            i++;
                            if (i < length && [sql characterAtIndex:i] == 'd') {
                                // %lld
                                arg = [NSNumber numberWithLongLong:va_arg(args, long long)];
                            } else if (i < length && [sql characterAtIndex:i] == 'u') {
                                // %llu
                                arg = [NSNumber numberWithUnsignedLongLong:va_arg(args, unsigned long long)];
                            } else {
                                i--;
                            }
                        } else if (next == 'd') {
                            // %ld
                            arg = [NSNumber numberWithLong:va_arg(args, long)];
                        } else if (next == 'u') {
                            // %lu
                            arg = [NSNumber numberWithUnsignedLong:va_arg(args, unsigned long)];
                        } else {
                            i--;
                        }
                    } else {
                        i--;
                    }
                    break;
                default:
                    // something else that we can't interpret. just pass it on through like normal
                    break;
            } /* switch */
        } else if (current == '%') {
            // percent sign; skip this character
            add = '\0';
        }

        if (arg != nil) {
            [cleanedSQL appendString:@"?"];
            [arguments addObject:arg];
        } else if (add == (unichar)'@' && last == (unichar)'%') {
            [cleanedSQL appendFormat:@"NULL"];
        } else if (add != '\0') {
            [cleanedSQL appendFormat:@"%C", add];
        }
        last = current;
    }
} /* extractSQL */

#pragma mark Execute queries

- (CCResultSet *) executeQuery:(NSString *)sql withParameterDictionary:(NSDictionary *)arguments {
    return [self executeQuery:sql withArgumentsInArray:nil orDictionary:arguments orVAList:nil];
}

- (CCResultSet *) executeQuery:(NSString *)sql withArgumentsInArray:(NSArray *)arrayArgs orDictionary:(NSDictionary *)dictionaryArgs orVAList:(va_list)args {

    if (![self databaseExists]) {
        return CCNULL;
    }

    if (_isExecutingStatement) {
        [self warnInUse];
        return CCNULL;
    }

    _isExecutingStatement = YES;

    int rc                  = CCNULL;
    sqlite3_stmt * pStmt     = CCNULL;
    CCStatement * statement  = CCNULL;
    CCResultSet * rs         = CCNULL;

    if (_traceExecution && sql) {
        NSLog(@"%@ executeQuery: %@", self, sql);
    }

    if (_shouldCacheStatements) {
        statement = [self cachedStatementForQuery:sql];
        pStmt = statement ? [statement statement] : CCNULL;
        [statement reset];
    }

    if (!pStmt) {

        rc = sqlite3_prepare_v2(_db, [sql UTF8String], -1, &pStmt, 0);

        if (SQLITE_OK != rc) {
            if (_logsErrors) {
                NSLog(@"DB Error: %d \"%@\"", [self lastErrorCode], [self lastErrorMessage]);
                NSLog(@"DB Query: %@", sql);
                NSLog(@"DB Path: %@", _databasePath);
            }

            if (_crashOnErrors) {
                NSAssert(false, @"DB Error: %d \"%@\"", [self lastErrorCode], [self lastErrorMessage]);
                abort();
            }

            sqlite3_finalize(pStmt);
            _isExecutingStatement = NO;
            return nil;
        }
    }

    id obj;
    int idx = 0;
    int queryCount = sqlite3_bind_parameter_count(pStmt); // pointed out by Dominic Yu (thanks!)

    // If dictionaryArgs is passed in, that means we are using sqlite's named parameter support
    if (dictionaryArgs) {

        for (NSString * dictionaryKey in [dictionaryArgs allKeys]) {

            // Prefix the key with a colon.
            NSString * parameterName = [[NSString alloc] initWithFormat:@":%@", dictionaryKey];

            if (_traceExecution) {
                NSLog(@"%@ = %@", parameterName, [dictionaryArgs objectForKey:dictionaryKey]);
            }

            // Get the index for the parameter name.
            int namedIdx = sqlite3_bind_parameter_index(pStmt, [parameterName UTF8String]);

            CCRelease(parameterName);

            if (namedIdx > 0) {
                // Standard binding from here.
                [self bindObject:[dictionaryArgs objectForKey:dictionaryKey] toColumn:namedIdx inStatement:pStmt];
                // increment the binding count, so our check below works out
                idx++;
            } else {
                NSLog(@"Could not find index for %@", dictionaryKey);
            }
        }
    } else {

        while (idx < queryCount) {

            if (arrayArgs && idx < (int)[arrayArgs count]) {
                obj = [arrayArgs objectAtIndex:(NSUInteger)idx];
            } else if (args) {
                obj = va_arg(args, id);
            } else {
                // We ran out of arguments
                break;
            }

            if (_traceExecution) {
                if ([obj isKindOfClass:[NSData class]]) {
                    NSLog(@"data: %ld bytes", (unsigned long)[(NSData *)obj length]);
                } else {
                    NSLog(@"obj: %@", obj);
                }
            }

            idx++;

            [self bindObject:obj toColumn:idx inStatement:pStmt];
        }
    }

    if (idx != queryCount) {
        NSLog(@"Error: the bind count is not correct for the # of variables (executeQuery)");
        sqlite3_finalize(pStmt);
        _isExecutingStatement = NO;
        return nil;
    }

    CCRetain(statement); // to balance the release below

    if (!statement) {
        statement = [[CCStatement alloc] init];
        [statement setStatement:pStmt];

        if (_shouldCacheStatements && sql) {
            [self setCachedStatement:statement forQuery:sql];
        }
    }

    // the statement gets closed in rs's dealloc or [rs close];
    rs = [CCResultSet resultSetWithStatement:statement usingParentDatabase:self];
    [rs setQuery:sql];

    NSValue * openResultSet = [NSValue valueWithNonretainedObject:rs];
    [_openResultSets addObject:openResultSet];

    [statement setUseCount:[statement useCount] + 1];

    CCRelease(statement);

    _isExecutingStatement = NO;

    return rs;
} /* executeQuery */

- (CCResultSet *) executeQuery:(NSString *)sql, ...{
    va_list args;
    va_start(args, sql);

    id result = [self executeQuery:sql withArgumentsInArray:nil orDictionary:nil orVAList:args];

    va_end(args);
    return result;
}

- (CCResultSet *) executeQueryWithFormat:(NSString *)format, ...{
    va_list args;
    va_start(args, format);

    NSMutableString * sql = [NSMutableString stringWithCapacity:[format length]];
    NSMutableArray * arguments = [NSMutableArray array];
    [self extractSQL:format argumentsList:args intoString:sql arguments:arguments];

    va_end(args);

    return [self executeQuery:sql withArgumentsInArray:arguments];
}

- (CCResultSet *) executeQuery:(NSString *)sql withArgumentsInArray:(NSArray *)arguments {
    return [self executeQuery:sql withArgumentsInArray:arguments orDictionary:nil orVAList:nil];
}

- (CCResultSet *) executeQuery:(NSString *)sql values:(NSArray *)values error:(NSError * __autoreleasing *)error {
    CCResultSet * rs = [self executeQuery:sql withArgumentsInArray:values orDictionary:nil orVAList:nil];

    if (!rs && error) {
        *error = [self lastError];
    }
    return rs;
}

- (CCResultSet *) executeQuery:(NSString *)sql withVAList:(va_list)args {
    return [self executeQuery:sql withArgumentsInArray:nil orDictionary:nil orVAList:args];
}

#pragma mark Execute updates

- (BOOL) executeUpdate:(NSString *)sql error:(NSError **)outErr withArgumentsInArray:(NSArray *)arrayArgs orDictionary:(NSDictionary *)dictionaryArgs orVAList:(va_list)args {

    if (![self databaseExists]) {
        return NO;
    }

    if (_isExecutingStatement) {
        [self warnInUse];
        return NO;
    }

    _isExecutingStatement = YES;

    int rc                   = CCNULL;
    sqlite3_stmt * pStmt      = CCNULL;
    CCStatement * cachedStmt  = CCNULL;

    if (_traceExecution && sql) {
        NSLog(@"%@ executeUpdate: %@", self, sql);
    }

    if (_shouldCacheStatements) {
        cachedStmt = [self cachedStatementForQuery:sql];
        pStmt = cachedStmt ? [cachedStmt statement] : CCNULL;
        [cachedStmt reset];
    }

    if (!pStmt) {
        rc = sqlite3_prepare_v2(_db, [sql UTF8String], -1, &pStmt, 0);

        if (SQLITE_OK != rc) {
            if (_logsErrors) {
                NSLog(@"DB Error: %d \"%@\"", [self lastErrorCode], [self lastErrorMessage]);
                NSLog(@"DB Query: %@", sql);
                NSLog(@"DB Path: %@", _databasePath);
            }

            if (_crashOnErrors) {
                NSAssert(false, @"DB Error: %d \"%@\"", [self lastErrorCode], [self lastErrorMessage]);
                abort();
            }

            if (outErr) {
                *outErr = [self errorWithMessage:[NSString stringWithUTF8String:sqlite3_errmsg(_db)]];
            }

            sqlite3_finalize(pStmt);

            _isExecutingStatement = NO;
            return NO;
        }
    }

    id obj;
    int idx = 0;
    int queryCount = sqlite3_bind_parameter_count(pStmt);

    // If dictionaryArgs is passed in, that means we are using sqlite's named parameter support
    if (dictionaryArgs) {

        for (NSString * dictionaryKey in [dictionaryArgs allKeys]) {

            // Prefix the key with a colon.
            NSString * parameterName = [[NSString alloc] initWithFormat:@":%@", dictionaryKey];

            if (_traceExecution) {
                NSLog(@"%@ = %@", parameterName, [dictionaryArgs objectForKey:dictionaryKey]);
            }
            // Get the index for the parameter name.
            int namedIdx = sqlite3_bind_parameter_index(pStmt, [parameterName UTF8String]);

            CCRelease(parameterName);

            if (namedIdx > 0) {
                // Standard binding from here.
                [self bindObject:[dictionaryArgs objectForKey:dictionaryKey] toColumn:namedIdx inStatement:pStmt];

                // increment the binding count, so our check below works out
                idx++;
            } else {
                NSString * message = [NSString stringWithFormat:@"Could not find index for %@", dictionaryKey];

                if (_logsErrors) {
                    NSLog(@"%@", message);
                }
                if (outErr) {
                    *outErr = [self errorWithMessage:message];
                }
            }
        }
    } else {

        while (idx < queryCount) {

            if (arrayArgs && idx < (int)[arrayArgs count]) {
                obj = [arrayArgs objectAtIndex:(NSUInteger)idx];
            } else if (args) {
                obj = va_arg(args, id);
            } else {
                // We ran out of arguments
                break;
            }

            if (_traceExecution) {
                if ([obj isKindOfClass:[NSData class]]) {
                    NSLog(@"data: %ld bytes", (unsigned long)[(NSData *)obj length]);
                } else {
                    NSLog(@"obj: %@", obj);
                }
            }

            idx++;

            [self bindObject:obj toColumn:idx inStatement:pStmt];
        }
    }


    if (idx != queryCount) {
        NSString * message = [NSString stringWithFormat:@"Error: the bind count (%d) is not correct for the # of variables in the query (%d) (%@) (executeUpdate)", idx, queryCount, sql];
        if (_logsErrors) {
            NSLog(@"%@", message);
        }
        if (outErr) {
            *outErr = [self errorWithMessage:message];
        }

        sqlite3_finalize(pStmt);
        _isExecutingStatement = NO;
        return NO;
    }

    /* Call sqlite3_step() to run the virtual machine. Since the SQL being
    ** executed is not a SELECT statement, we assume no data will be returned.
    */

    rc      = sqlite3_step(pStmt);

    if (SQLITE_DONE == rc) {
        // all is well, let's return.
    } else if (SQLITE_INTERRUPT == rc) {
        if (_logsErrors) {
            NSLog(@"Error calling sqlite3_step. Query was interrupted (%d: %s) SQLITE_INTERRUPT", rc, sqlite3_errmsg(_db));
            NSLog(@"DB Query: %@", sql);
        }
    } else if (rc == SQLITE_ROW) {
        NSString * message = [NSString stringWithFormat:@"A executeUpdate is being called with a query string '%@'", sql];
        if (_logsErrors) {
            NSLog(@"%@", message);
            NSLog(@"DB Query: %@", sql);
        }
        if (outErr) {
            *outErr = [self errorWithMessage:message];
        }
    } else {
        if (outErr) {
            *outErr = [self errorWithMessage:[NSString stringWithUTF8String:sqlite3_errmsg(_db)]];
        }

        if (SQLITE_ERROR == rc) {
            if (_logsErrors) {
                NSLog(@"Error calling sqlite3_step (%d: %s) SQLITE_ERROR", rc, sqlite3_errmsg(_db));
                NSLog(@"DB Query: %@", sql);
            }
        } else if (SQLITE_MISUSE == rc) {
            // uh oh.
            if (_logsErrors) {
                NSLog(@"Error calling sqlite3_step (%d: %s) SQLITE_MISUSE", rc, sqlite3_errmsg(_db));
                NSLog(@"DB Query: %@", sql);
            }
        } else {
            // wtf?
            if (_logsErrors) {
                NSLog(@"Unknown error calling sqlite3_step (%d: %s) eu", rc, sqlite3_errmsg(_db));
                NSLog(@"DB Query: %@", sql);
            }
        }
    }

    if (_shouldCacheStatements && !cachedStmt) {
        cachedStmt = [[CCStatement alloc] init];

        [cachedStmt setStatement:pStmt];

        [self setCachedStatement:cachedStmt forQuery:sql];

        CCRelease(cachedStmt);
    }

    int closeErrorCode;

    if (cachedStmt) {
        [cachedStmt setUseCount:[cachedStmt useCount] + 1];
        closeErrorCode = sqlite3_reset(pStmt);
    } else {
        /* Finalize the virtual machine. This releases all memory and other
        ** resources allocated by the sqlite3_prepare() call above.
        */
        closeErrorCode = sqlite3_finalize(pStmt);
    }

    if (closeErrorCode != SQLITE_OK) {
        if (_logsErrors) {
            NSLog(@"Unknown error finalizing or resetting statement (%d: %s)", closeErrorCode, sqlite3_errmsg(_db));
            NSLog(@"DB Query: %@", sql);
        }
    }

    _isExecutingStatement = NO;
    return (rc == SQLITE_DONE || rc == SQLITE_OK);
} /* executeUpdate */


- (BOOL) executeUpdate:(NSString *)sql, ...{
    va_list args;
    va_start(args, sql);

    BOOL result = [self executeUpdate:sql error:nil withArgumentsInArray:nil orDictionary:nil orVAList:args];

    va_end(args);
    return result;
}

- (BOOL) executeUpdate:(NSString *)sql withArgumentsInArray:(NSArray *)arguments {
    return [self executeUpdate:sql error:nil withArgumentsInArray:arguments orDictionary:nil orVAList:nil];
}

- (BOOL) executeUpdate:(NSString *)sql values:(NSArray *)values error:(NSError * __autoreleasing *)error {
    return [self executeUpdate:sql error:error withArgumentsInArray:values orDictionary:nil orVAList:nil];
}

- (BOOL) executeUpdate:(NSString *)sql withParameterDictionary:(NSDictionary *)arguments {
    return [self executeUpdate:sql error:nil withArgumentsInArray:nil orDictionary:arguments orVAList:nil];
}

- (BOOL) executeUpdate:(NSString *)sql withVAList:(va_list)args {
    return [self executeUpdate:sql error:nil withArgumentsInArray:nil orDictionary:nil orVAList:args];
}

- (BOOL) executeUpdateWithFormat:(NSString *)format, ...{
    va_list args;
    va_start(args, format);

    NSMutableString * sql      = [NSMutableString stringWithCapacity:[format length]];
    NSMutableArray * arguments = [NSMutableArray array];

    [self extractSQL:format argumentsList:args intoString:sql arguments:arguments];

    va_end(args);

    return [self executeUpdate:sql withArgumentsInArray:arguments];
}


int CCExecuteBulkSQLCallback(void * theBlockAsVoid, int columns, char ** values, char ** names); // shhh clang.
int CCExecuteBulkSQLCallback(void * theBlockAsVoid, int columns, char ** values, char ** names) {

    if (!theBlockAsVoid) {
        return SQLITE_OK;
    }

    int (^ execCallbackBlock)(NSDictionary * resultsDictionary) = (__bridge int (^)(NSDictionary * __strong))(theBlockAsVoid);

    NSMutableDictionary * dictionary = [NSMutableDictionary dictionaryWithCapacity:(NSUInteger)columns];

    for (NSInteger i = 0; i < columns; i++) {
        NSString * key = [NSString stringWithUTF8String:names[i]];
        id value = values[i] ? [NSString stringWithUTF8String:values[i]] : [NSNull null];
        [dictionary setObject:value forKey:key];
    }

    return execCallbackBlock(dictionary);
}

- (BOOL) executeStatements:(NSString *)sql {
    return [self executeStatements:sql withResultBlock:nil];
}

- (BOOL) executeStatements:(NSString *)sql withResultBlock:(CCExecuteStatementsCallbackBlock)block {

    int rc;
    char * errmsg = nil;

    rc = sqlite3_exec([self sqliteHandle], [sql UTF8String], block ? CCExecuteBulkSQLCallback : nil, (__bridge void *)(block), &errmsg);

    if (errmsg && [self logsErrors]) {
        NSLog(@"Error inserting batch: %s", errmsg);
        sqlite3_free(errmsg);
    }

    return (rc == SQLITE_OK);
}

- (BOOL) executeUpdate:(NSString *)sql withErrorAndBindings:(NSError **)outErr, ...{

    va_list args;
    va_start(args, outErr);

    BOOL result = [self executeUpdate:sql error:outErr withArgumentsInArray:nil orDictionary:nil orVAList:args];

    va_end(args);
    return result;
}

#pragma mark Transactions

- (BOOL) rollback {
    BOOL b = [self executeUpdate:@"rollback transaction"];

    if (b) {
        _inTransaction = NO;
    }

    return b;
}

- (BOOL) commit {
    BOOL b =  [self executeUpdate:@"commit transaction"];

    if (b) {
        _inTransaction = NO;
    }

    return b;
}

- (BOOL) beginDeferredTransaction {

    BOOL b = [self executeUpdate:@"begin deferred transaction"];

    if (b) {
        _inTransaction = YES;
    }

    return b;
}

- (BOOL) beginTransaction {

    BOOL b = [self executeUpdate:@"begin exclusive transaction"];

    if (b) {
        _inTransaction = YES;
    }

    return b;
}

- (BOOL) inTransaction {
    return _inTransaction;
}

- (BOOL) interrupt {
    if (_db) {
        sqlite3_interrupt([self sqliteHandle]);
        return YES;
    }
    return NO;
}

static NSString * CCEscapeSavePointName(NSString * savepointName) {
    return [savepointName stringByReplacingOccurrencesOfString:@"'" withString:@"''"];
}

- (BOOL) startSavePointWithName:(NSString *)name error:(NSError **)outErr {
#if SQLITE_VERSION_NUMBER >= 3007000
    NSParameterAssert(name);

    NSString * sql = [NSString stringWithFormat:@"savepoint '%@';", CCEscapeSavePointName(name)];

    return [self executeUpdate:sql error:outErr withArgumentsInArray:nil orDictionary:nil orVAList:nil];
#else
    NSString * errorMessage = NSLocalizedString(@"Save point functions require SQLite 3.7", nil);
    if (self.logsErrors) NSLog(@"%@", errorMessage);
    return NO;
#endif
}

- (BOOL) releaseSavePointWithName:(NSString *)name error:(NSError **)outErr {
#if SQLITE_VERSION_NUMBER >= 3007000
    NSParameterAssert(name);

    NSString * sql = [NSString stringWithFormat:@"release savepoint '%@';", CCEscapeSavePointName(name)];

    return [self executeUpdate:sql error:outErr withArgumentsInArray:nil orDictionary:nil orVAList:nil];
#else
    NSString * errorMessage = NSLocalizedString(@"Save point functions require SQLite 3.7", nil);
    if (self.logsErrors) NSLog(@"%@", errorMessage);
    return NO;
#endif
}

- (BOOL) rollbackToSavePointWithName:(NSString *)name error:(NSError **)outErr {
#if SQLITE_VERSION_NUMBER >= 3007000
    NSParameterAssert(name);

    NSString * sql = [NSString stringWithFormat:@"rollback transaction to savepoint '%@';", CCEscapeSavePointName(name)];

    return [self executeUpdate:sql error:outErr withArgumentsInArray:nil orDictionary:nil orVAList:nil];
#else
    NSString * errorMessage = NSLocalizedString(@"Save point functions require SQLite 3.7", nil);
    if (self.logsErrors) NSLog(@"%@", errorMessage);
    return NO;
#endif
}

- (NSError *) inSavePoint:(void (^)(BOOL * rollback))block {
#if SQLITE_VERSION_NUMBER >= 3007000
    static unsigned long savePointIdx = 0;

    NSString * name = [NSString stringWithFormat:@"dbSavePoint%ld", savePointIdx++];

    BOOL shouldRollback = NO;

    NSError * err = CCNULL;

    if (![self startSavePointWithName:name error:&err]) {
        return err;
    }

    if (block) {
        block(&shouldRollback);
    }

    if (shouldRollback) {
        // We need to rollback and release this savepoint to remove it
        [self rollbackToSavePointWithName:name error:&err];
    }
    [self releaseSavePointWithName:name error:&err];

    return err;
#else  /* if SQLITE_VERSION_NUMBER >= 3007000 */
    NSString * errorMessage = NSLocalizedString(@"Save point functions require SQLite 3.7", nil);
    if (self.logsErrors) NSLog(@"%@", errorMessage);
    return [NSError errorWithDomain:@"CCSQLite" code:0 userInfo:@{ NSLocalizedDescriptionKey : errorMessage }];
#endif /* if SQLITE_VERSION_NUMBER >= 3007000 */
} /* inSavePoint */


#pragma mark Cache statements

- (BOOL) shouldCacheStatements {
    return _shouldCacheStatements;
}

- (void) setShouldCacheStatements:(BOOL)value {

    _shouldCacheStatements = value;

    if (_shouldCacheStatements && !_cachedStatements) {
        [self setCachedStatements:[NSMutableDictionary dictionary]];
    }

    if (!_shouldCacheStatements) {
        [self setCachedStatements:nil];
    }
}

#pragma mark Callback function

void CCBlockSQLiteCallBackFunction(sqlite3_context * context, int argc, sqlite3_value ** argv); // -Wmissing-prototypes
void CCBlockSQLiteCallBackFunction(sqlite3_context * context, int argc, sqlite3_value ** argv) {
#if !__has_feature(objc_arc)
    void (^ block)(sqlite3_context * context, int argc, sqlite3_value ** argv) = (id)sqlite3_user_data(context);
#else
    void (^ block)(sqlite3_context * context, int argc, sqlite3_value ** argv) = (__bridge id)sqlite3_user_data(context);
#endif
    if (block) {
        block(context, argc, argv);
    }
}


- (void) makeFunctionNamed:(NSString *)name maximumArguments:(int)count withBlock:(void (^)(void * context, int argc, void ** argv))block {

    if (!_openFunctions) {
        _openFunctions = [NSMutableSet new];
    }

    id b = CCReturnAutoreleased([block copy]);

    [_openFunctions addObject:b];

    /* I tried adding custom functions to release the block when the connection is destroyed- but they seemed to never be called, so we use _openFunctions to store the values instead. */
#if !__has_feature(objc_arc)
    sqlite3_create_function([self sqliteHandle], [name UTF8String], count, SQLITE_UTF8, (void *)b, &CCBlockSQLiteCallBackFunction, CCNULL, CCNULL);
#else
    sqlite3_create_function([self sqliteHandle], [name UTF8String], count, SQLITE_UTF8, (__bridge void *)b, &CCBlockSQLiteCallBackFunction, CCNULL, CCNULL);
#endif
}

#pragma mark CCSQLiteAdditions
#define RETURN_RESULT_FOR_QUERY_WITH_SELECTOR(type, sel)             \
    va_list args;                                                        \
    va_start(args, query);                                               \
    CCResultSet * resultSet = [self executeQuery:query withArgumentsInArray:CCNULL orDictionary:CCNULL orVAList:args];   \
    va_end(args);                                                        \
    if (![resultSet next]) { return (type)0; }                           \
    type ret = [resultSet sel:0];                                        \
    [resultSet close];                                                   \
    [resultSet setParentDB:nil];                                         \
    return ret;


- (NSString *) stringForQuery:(NSString *)query, ...{
    RETURN_RESULT_FOR_QUERY_WITH_SELECTOR(NSString *, stringForColumnIndex);
}

- (int) intForQuery:(NSString *)query, ...{
    RETURN_RESULT_FOR_QUERY_WITH_SELECTOR(int, intForColumnIndex);
}

- (long) longForQuery:(NSString *)query, ...{
    RETURN_RESULT_FOR_QUERY_WITH_SELECTOR(long, longForColumnIndex);
}

- (BOOL) boolForQuery:(NSString *)query, ...{
    RETURN_RESULT_FOR_QUERY_WITH_SELECTOR(BOOL, boolForColumnIndex);
}

- (double) doubleForQuery:(NSString *)query, ...{
    RETURN_RESULT_FOR_QUERY_WITH_SELECTOR(double, doubleForColumnIndex);
}

- (NSData *) dataForQuery:(NSString *)query, ...{
    RETURN_RESULT_FOR_QUERY_WITH_SELECTOR(NSData *, dataForColumnIndex);
}

- (NSDate *) dateForQuery:(NSString *)query, ...{
    RETURN_RESULT_FOR_QUERY_WITH_SELECTOR(NSDate *, dateForColumnIndex);
}


- (BOOL) tableExists:(NSString *)tableName {

    tableName = [tableName lowercaseString];

    CCResultSet * rs = [self executeQuery:@"select [sql] from sqlite_master where [type] = 'table' and lower(name) = ?", tableName];

    // if at least one next exists, table exists
    BOOL returnBool = [rs next];

    // close and free object
    [rs close];

    return returnBool;
}

/*
 * get table with list of tables: result colums: type[STRING], name[STRING],tbl_name[STRING],rootpage[INTEGER],sql[STRING]
 * check if table exist in database  (patch from OZLB)
 */
- (CCResultSet *) getSchema {

    // result colums: type[STRING], name[STRING],tbl_name[STRING],rootpage[INTEGER],sql[STRING]
    CCResultSet * rs = [self executeQuery:@"SELECT type, name, tbl_name, rootpage, sql FROM (SELECT * FROM sqlite_master UNION ALL SELECT * FROM sqlite_temp_master) WHERE type != 'meta' AND name NOT LIKE 'sqlite_%' ORDER BY tbl_name, type DESC, name"];

    return rs;
}

/*
 * get table schema: result colums: cid[INTEGER], name,type [STRING], notnull[INTEGER], dflt_value[],pk[INTEGER]
 */
- (CCResultSet *) getTableSchema:(NSString *)tableName {

    // result colums: cid[INTEGER], name,type [STRING], notnull[INTEGER], dflt_value[],pk[INTEGER]
    CCResultSet * rs = [self executeQuery:[NSString stringWithFormat:@"pragma table_info('%@')", tableName]];

    return rs;
}

- (BOOL) columnExists:(NSString *)columnName inTableWithName:(NSString *)tableName {

    BOOL returnBool = NO;

    tableName  = [tableName lowercaseString];
    columnName = [columnName lowercaseString];

    CCResultSet * rs = [self getTableSchema:tableName];

    // check if column is present in table schema
    while ([rs next]) {
        if ([[[rs stringForColumn:@"name"] lowercaseString] isEqualToString:columnName]) {
            returnBool = YES;
            break;
        }
    }

    // If this is not done CCSQLite instance stays out of pool
    [rs close];

    return returnBool;
} /* columnExists */



- (uint32_t) applicationID {
#if SQLITE_VERSION_NUMBER >= 3007017
    uint32_t r = 0;

    CCResultSet * rs = [self executeQuery:@"pragma application_id"];

    if ([rs next]) {
        r = (uint32_t)[rs longLongIntForColumnIndex:0];
    }

    [rs close];

    return r;
#else
    NSString * errorMessage = NSLocalizedString(@"Application ID functions require SQLite 3.7.17", nil);
    if (self.logsErrors) NSLog(@"%@", errorMessage);
    return 0;
#endif
}

- (void) setApplicationID:(uint32_t)appID {
#if SQLITE_VERSION_NUMBER >= 3007017
    NSString * query = [NSString stringWithFormat:@"pragma application_id=%d", appID];
    CCResultSet * rs = [self executeQuery:query];
    [rs next];
    [rs close];
#else
    NSString * errorMessage = NSLocalizedString(@"Application ID functions require SQLite 3.7.17", nil);
    if (self.logsErrors) NSLog(@"%@", errorMessage);
#endif
}


#if TARGET_OS_MAC && !TARGET_OS_IPHONE

- (NSString *) applicationIDString {
#if SQLITE_VERSION_NUMBER >= 3007017
    NSString * s = NSFileTypeForHFSTypeCode([self applicationID]);

    assert([s length] == 6);

    s = [s substringWithRange:NSMakeRange(1, 4)];


    return s;
#else
    NSString * errorMessage = NSLocalizedString(@"Application ID functions require SQLite 3.7.17", nil);
    if (self.logsErrors) NSLog(@"%@", errorMessage);
    return nil;
#endif
}

- (void) setApplicationIDString:(NSString *)s {
#if SQLITE_VERSION_NUMBER >= 3007017
    if ([s length] != 4) {
        NSLog(@"setApplicationIDString: string passed is not exactly 4 chars long. (was %ld)", [s length]);
    }

    [self setApplicationID:NSHFSTypeCodeFromFileType([NSString stringWithFormat:@"'%@'", s])];
#else
    NSString * errorMessage = NSLocalizedString(@"Application ID functions require SQLite 3.7.17", nil);
    if (self.logsErrors) NSLog(@"%@", errorMessage);
#endif
}

#endif /* if TARGET_OS_MAC && !TARGET_OS_IPHONE */

- (uint32_t) userVersion {
    uint32_t r = 0;

    CCResultSet * rs = [self executeQuery:@"pragma user_version"];

    if ([rs next]) {
        r = (uint32_t)[rs longLongIntForColumnIndex:0];
    }

    [rs close];
    return r;
}

- (void) setUserVersion:(uint32_t)version {
    NSString * query = [NSString stringWithFormat:@"pragma user_version = %d", version];
    CCResultSet * rs = [self executeQuery:query];

    [rs next];
    [rs close];
}

- (BOOL) validateSQL:(NSString *)sql error:(NSError **)error {
    sqlite3_stmt * pStmt = NULL;
    BOOL validationSucceeded = YES;

    int rc = sqlite3_prepare_v2(_db, [sql UTF8String], -1, &pStmt, 0);

    if (rc != SQLITE_OK) {
        validationSucceeded = NO;
        if (error) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:[self lastErrorCode]
                                     userInfo:[NSDictionary dictionaryWithObject:[self lastErrorMessage]
                                                                          forKey:NSLocalizedDescriptionKey]];
        }
    }

    sqlite3_finalize(pStmt);

    return validationSucceeded;
}

- (SqliteValueType) valueType:(void *)value {
    return sqlite3_value_type(value);
}

- (int) valueInt:(void *)value {
    return sqlite3_value_int(value);
}

- (long long) valueLong:(void *)value {
    return sqlite3_value_int64(value);
}

- (double) valueDouble:(void *)value {
    return sqlite3_value_double(value);
}

- (NSData *) valueData:(void *)value {
    const void * bytes = sqlite3_value_blob(value);
    int length = sqlite3_value_bytes(value);

    return bytes ? [NSData dataWithBytes:bytes length:(NSUInteger)length] : nil;
}

- (NSString *) valueString:(void *)value {
    const char * cString = (const char *)sqlite3_value_text(value);

    return cString ? [NSString stringWithUTF8String:cString] : nil;
}

- (void) resultNullInContext:(void *)context {
    sqlite3_result_null(context);
}

- (void) resultInt:(int)value context:(void *)context {
    sqlite3_result_int(context, value);
}

- (void) resultLong:(long long)value context:(void *)context {
    sqlite3_result_int64(context, value);
}

- (void) resultDouble:(double)value context:(void *)context {
    sqlite3_result_double(context, value);
}

- (void) resultData:(NSData *)data context:(void *)context {
    sqlite3_result_blob(context, data.bytes, (int)data.length, SQLITE_TRANSIENT);
}

- (void) resultString:(NSString *)value context:(void *)context {
    sqlite3_result_text(context, [value UTF8String], -1, SQLITE_TRANSIENT);
}

- (void) resultError:(NSString *)error context:(void *)context {
    sqlite3_result_error(context, [error UTF8String], -1);
}

- (void) resultErrorCode:(int)errorCode context:(void *)context {
    sqlite3_result_error_code(context, errorCode);
}

- (void) resultErrorNoMemoryInContext:(void *)context {
    sqlite3_result_error_nomem(context);
}

- (void) resultErrorTooBigInContext:(void *)context {
    sqlite3_result_error_toobig(context);
}

#pragma mark key <-> data

/**
 *  object2Data
 *
 *  @param object object description
 *
 *  @return return value description
 */
+ (NSData *) object2Data:(id)object {
    if ([object isKindOfClass:[NSString class]]) {
        NSString * data = object;
        return [data dataUsingEncoding:NSUTF8StringEncoding];
    } else if ([object isKindOfClass:[NSData class]]) {
        return object;
    } else if ([object isKindOfClass:[NSArray class]] || [object isKindOfClass:[NSDictionary class]]) {
        return [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    } else {
        NSLog(@"error args for object");
        return nil;
    }
}

/**
 *  data2Object
 *
 *  @param object object description
 *
 *  @return return value description
 */
+ (id) data2Object:(id)data {
    if (data && [data isKindOfClass:[NSData class]]) {
        return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    }

    return data;
}

@end


@interface CCSQLite (PrivateStuff)
- (CCResultSet *) executeQuery:(NSString *)sql withArgumentsInArray:(NSArray *)arrayArgs orDictionary:(NSDictionary *)dictionaryArgs orVAList:(va_list)args;
@end

