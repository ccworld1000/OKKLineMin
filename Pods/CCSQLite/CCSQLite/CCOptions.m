//
//  CCOptions.m
//  CCSQLite
//
//  Created by deng you hua on 2/19/17.
//  Copyright © 2017 CC | ccworld1000@gmail.com. All rights reserved.
//


#import "CCOptions.h"

/**
 * Welcome to YapDatabase!
 *
 * The project page has a wealth of documentation if you have any questions.
 * https://github.com/yapstudios/YapDatabase
 *
 * If you're new to the project you may want to visit the wiki.
 * https://github.com/yapstudios/YapDatabase/wiki
 *
 * This class provides extra configuration options that may be passed to YapDatabase.
 * The configuration options provided by this class are advanced (beyond the basic setup options).
 **/
@implementation CCOptions

@synthesize corruptAction = corruptAction;
@synthesize pragmaSynchronous = pragmaSynchronous;
@synthesize pragmaJournalSizeLimit = pragmaJournalSizeLimit;
@synthesize pragmaPageSize = pragmaPageSize;
@synthesize pragmaMMapSize = pragmaMMapSize;
#ifdef SQLITE_HAS_CODEC
@synthesize cipherKeyBlock = cipherKeyBlock;
@synthesize kdfIterNumber = kdfIterNumber;
@synthesize cipherDefaultkdfIterNumber = cipherDefaultkdfIterNumber;
@synthesize cipherPageSize = cipherPageSize;
#endif
@synthesize aggressiveWALTruncationSize = aggressiveWALTruncationSize;
@synthesize enableMultiProcessSupport = enableMultiProcessSupport;

- (id) init {
    if ((self = [super init])) {
        corruptAction = CCOptionsCorruptAction_Rename;
        pragmaSynchronous = CCOptionsPragmaSynchronous_Full;
        pragmaJournalSizeLimit = 0;
        pragmaPageSize = 0;
        pragmaMMapSize = 0;
        aggressiveWALTruncationSize = (1024 * 1024); // 1 MB
        enableMultiProcessSupport = NO;
    }
    return self;
}

- (id) copyWithZone:(NSZone __unused *)zone {
    CCOptions * copy = [[[self class] alloc] init];

    copy->corruptAction = corruptAction;
    copy->pragmaSynchronous = pragmaSynchronous;
    copy->pragmaJournalSizeLimit = pragmaJournalSizeLimit;
    copy->pragmaPageSize = pragmaPageSize;
    copy->pragmaMMapSize = pragmaMMapSize;
#ifdef SQLITE_HAS_CODEC
    copy->cipherKeyBlock = cipherKeyBlock;
    copy->kdfIterNumber = kdfIterNumber;
    copy->cipherDefaultkdfIterNumber = cipherDefaultkdfIterNumber;
    copy->cipherPageSize = cipherPageSize;
#endif
    copy->aggressiveWALTruncationSize = aggressiveWALTruncationSize;
    copy->enableMultiProcessSupport = enableMultiProcessSupport;

    return copy;
}

@end
