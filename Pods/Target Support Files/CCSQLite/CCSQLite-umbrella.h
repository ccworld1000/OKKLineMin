#ifdef __OBJC__
#import <UIKit/UIKit.h>
#else
#ifndef FOUNDATION_EXPORT
#if defined(__cplusplus)
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif
#endif

#import "CCKeyValue.h"
#import "CCOptions.h"
#import "CCResultSet.h"
#import "CCSQLite.h"
#import "CCSQLitePool.h"
#import "CCSQLiteQueue.h"
#import "CCStatement.h"

FOUNDATION_EXPORT double CCSQLiteVersionNumber;
FOUNDATION_EXPORT const unsigned char CCSQLiteVersionString[];

