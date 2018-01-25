//
//  CCStatement.m
//  CCSQLite
//
//  Created by deng you hua on 2/12/17.
//  Copyright © 2017 CC | ccworld1000@gmail.com. All rights reserved.
//

#import "CCStatement.h"
#import "CCSQLite.h"

@implementation CCStatement

- (void) dealloc {
    [self close];
}

- (void) close {
    if (_statement) {
        sqlite3_finalize(_statement);
        _statement = CCNULL;
    }

    _inUse = NO;
}

- (void) reset {
    if (_statement) {
        sqlite3_reset(_statement);
    }

    _inUse = NO;
}

- (NSString *) description {
    return [NSString stringWithFormat:@"%@ %ld hit(s) for query %@", [super description], _useCount, _query];
}

@end
