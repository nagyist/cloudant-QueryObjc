//
//  CDTQSQLOnlyQueryExecutor.m
//  CloudantQueryObjc
//
//  Created by Michael Rhodes on 01/11/2014.
//  Copyright (c) 2014 Michael Rhodes. All rights reserved.
//

#import "CDTQSQLOnlyQueryExecutor.h"

@implementation CDTQSQLOnlyQueryExecutor

// MOD: SQL only, so never run matcher
- (NSArray*)postHocMatcherIfRequired:(BOOL)required 
                        forResultSet:(NSArray*)docIds
                       usingSelector:(NSDictionary*)selector
{
    return docIds;
}

@end
