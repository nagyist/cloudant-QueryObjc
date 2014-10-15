//
//  CDTQQueryExecutor.m
//  
//  Created by Mike Rhodes on 2014-09-29
//  Copyright (c) 2014 Cloudant. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CDTQQueryExecutor.h"

#import "CDTQIndexManager.h"
#import "CDTQResultSet.h"
#import "CDTQQuerySqlTranslator.h"
#import "CDTQLogging.h"

#import "FMDB.h"

@interface CDTQQueryExecutor ()

@property (nonatomic,strong) FMDatabaseQueue *database;
@property (nonatomic,strong) CDTDatastore *datastore;

@end

@implementation CDTQQueryExecutor

- (instancetype)initWithDatabase:(FMDatabaseQueue*)database
                       datastore:(CDTDatastore*)datastore
{
    self = [super init];
    if (self) {
        _database = database;
        _datastore = datastore;
    }
    return self;
}

#pragma mark Convenience methods

+ (CDTQResultSet*)find:(NSDictionary*)query 
          usingIndexes:(NSDictionary*)indexes
            inDatabase:(FMDatabaseQueue*)database
         fromDatastore:(CDTDatastore*)datastore
{
    CDTQQueryExecutor *executor = [[CDTQQueryExecutor alloc] initWithDatabase:database
                                                                    datastore:datastore];
    return [executor find:query usingIndexes:indexes];
}

#pragma mark Instance methods

- (CDTQResultSet*)find:(NSDictionary*)query usingIndexes:(NSDictionary*)indexes
{
    return [self find:query usingIndexes:indexes skip:0 limit:NSUIntegerMax];
}

/**
 
 Checks if the fields are valid. If they the array is empty the pointer to the array
 is changed to nil
 
 */
- (BOOL)validateFields:(NSArray *)fields
{
    
    
    for (id obj in fields) {
        
        if([obj isKindOfClass:[NSString class]]){
            if ([obj containsString:@"."]) {
                LogError(@"Fields cannot use dotted notation: %@", [fields description]);
                return NO;
            }
        } else {
            LogError(@"Fields should only be string objects: %@",[fields description]);
            return NO;
        }
    };
    
    return YES;
}

- (void)normaliseFields:(NSArray **)fields
{
    if ([*fields count] == 0) {
        LogWarn(@"fields array is empty, ignoring");
        *fields = nil;
    }
}

- (CDTQResultSet*)find:(NSDictionary *)query
          usingIndexes:(NSDictionary *)indexes
                  skip:(NSUInteger)skip
                 limit:(NSUInteger)limit
                fields:(NSArray *)fields
{
    
    [self normaliseFields:&fields];
    
    if ([self validateFields:fields])
    {
        
        CDTQOrQueryNode *root = (CDTQOrQueryNode*)[CDTQQuerySqlTranslator translateQuery:query
                                                                            toUseIndexes:indexes];
        
        if(!root) {
            return nil;
        }
        __block NSSet *docIds;
        
        [_database inTransaction:^(FMDatabase *db, BOOL *rollback) {
            docIds = [self executeQueryTree:root inDatabase:db];
        }];
        
        
        NSArray *filteredDocs = nil;
        
        if(skip < [docIds count]){
            NSRange range = NSMakeRange(skip, MIN(limit, [docIds count]));
            filteredDocs = [[docIds allObjects] subarrayWithRange:range];
        } else {
            filteredDocs =  @[];
        }
        
        return [[CDTQResultSet alloc] initWithDocIds:filteredDocs
                                           datastore:self.datastore
                                    projectionFields:fields];
    } else {
        return nil;
    }
    
}

- (CDTQResultSet*)find:(NSDictionary *)query
          usingIndexes:(NSDictionary *)indexes
                  skip:(NSUInteger)skip
                 limit:(NSUInteger)limit
{
    return [self find:query usingIndexes:indexes skip:skip limit:limit fields:nil];
}

#pragma mark Tree walking

- (NSSet*)executeQueryTree:(CDTQQueryNode*)node inDatabase:(FMDatabase*)db
{
    if ([node isKindOfClass:[CDTQAndQueryNode class]]) {
        
        NSMutableSet *accumulator = nil;
        
        CDTQAndQueryNode *andNode = (CDTQAndQueryNode*)node;
        for (CDTQQueryNode *node in andNode.children) {
            NSSet *childIds = [self executeQueryTree:node inDatabase:db];
            if (!accumulator) {
                accumulator = [NSMutableSet setWithSet:childIds];
            } else {
                [accumulator intersectSet:childIds];
            }
            
            // TODO optimisation is to bail here if accumlator is empty
        }
        
        return [NSSet setWithSet:accumulator];
        
    } if ([node isKindOfClass:[CDTQOrQueryNode class]]) {
        
        NSMutableSet *accumulator = nil;
        
        CDTQOrQueryNode *andNode = (CDTQOrQueryNode*)node;
        for (CDTQQueryNode *node in andNode.children) {
            NSSet *childIds = [self executeQueryTree:node inDatabase:db];
            if (!accumulator) {
                accumulator = [NSMutableSet setWithSet:childIds];
            } else {
                [accumulator unionSet:childIds];
            }
        }
        
        return [NSSet setWithSet:accumulator];
        
    } else if ([node isKindOfClass:[CDTQSqlQueryNode class]]) {
        
        CDTQSqlQueryNode *sqlNode = (CDTQSqlQueryNode*)node;
        CDTQSqlParts *sqlParts = sqlNode.sql;
        
        NSMutableArray *docIds = [NSMutableArray array];
        
        FMResultSet *rs= [db executeQuery:sqlParts.sqlWithPlaceholders 
                     withArgumentsInArray:sqlParts.placeholderValues];
        while ([rs next]) {
            [docIds addObject:[rs stringForColumn:@"_id"]];
        }

        [rs close];
        
        return [NSSet setWithArray:docIds];
        
    } else {
        return nil;
    }
}



@end
