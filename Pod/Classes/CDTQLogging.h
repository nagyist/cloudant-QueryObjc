//
//  CDTQueryLogging.h
//  Pods
//
//  Created by Rhys Short on 07/10/2014.
//
//

#ifndef Pods_CDTQueryLogging_h
#define Pods_CDTQueryLogging_h

#import "DDLog.h"

#define CDTQ_LOGGING_CONTEXT 17 //one level higher than CDT logger myabe should be 20?
static int CDTQLogLevel = LOG_LEVEL_WARN;

#define LogError( frmt, ...) SYNC_LOG_OBJC_MAYBE(CDTQLogLevel, LOG_FLAG_ERROR, CDTQ_LOGGING_CONTEXT, frmt, ##__VA_ARGS__)
#define LogWarn( frmt, ...) ASYNC_LOG_OBJC_MAYBE(CDTQLogLevel, LOG_FLAG_WARN, CDTQ_LOGGING_CONTEXT, frmt, ##__VA_ARGS__)
#define LogInfo( frmt, ...) ASYNC_LOG_OBJC_MAYBE(CDTQLogLevel, LOG_FLAG_INFO, CDTQ_LOGGING_CONTEXT, frmt, ##__VA_ARGS__)
#define LogDebug( frmt, ...) ASYNC_LOG_OBJC_MAYBE(CDTQLogLevel, LOG_FLAG_DEBUG, CDTQ_LOGGING_CONTEXT, frmt, ##__VA_ARGS__)
#define LogVerbose( frmt, ...) ASYNC_LOG_OBJC_MAYBE(CDTQLogLevel, LOG_FLAG_VERBOSE, CDTQ_LOGGING_CONTEXT, frmt, ##__VA_ARGS__)
#define CDTQChangeLogLevel(level) CDTQLogLevel = level
#endif
