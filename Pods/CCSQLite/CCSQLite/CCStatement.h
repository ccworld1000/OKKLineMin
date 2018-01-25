//
//  CCStatement.h
//  CCSQLite
//
//  Created by deng you hua on 2/12/17.
//  Copyright © 2017 CC | ccworld1000@gmail.com. All rights reserved.
//

#import <Foundation/Foundation.h>

/** Objective-C wrapper for `sqlite3_stmt`
 
 This is a wrapper for a SQLite `sqlite3_stmt`. Generally when using CCSQLite you will not need to interact directly with `CCStatement`, but rather with `<CCSQLite>` and `<CCResultSet>` only.
 
 ### See also
 
 - `<CCSQLite>`
 - `<CCResultSet>`
 - [`sqlite3_stmt`](http://www.sqlite.org/c3ref/stmt.html)
 */
@interface CCStatement : NSObject

///-----------------
/// @name Properties
///-----------------

/** Usage count */

@property (atomic, assign) long useCount;

/** SQL statement */

@property (atomic, copy) NSString *query;

/** SQLite sqlite3_stmt
 
 @see [`sqlite3_stmt`](http://www.sqlite.org/c3ref/stmt.html)
 */

@property (atomic, assign) void *statement;

/** Indication of whether the statement is in use */

@property (atomic, assign) BOOL inUse;

///----------------------------
/// @name Closing and Resetting
///----------------------------

/** Close statement */

- (void)close;

/** Reset statement */

- (void)reset;

@end


