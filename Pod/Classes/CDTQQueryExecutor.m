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

- (CDTQResultSet*)find:(NSDictionary*)query usingIndexes:(NSDictionary*)indexes
{
    NSString *chosenIndex = [CDTQQueryExecutor chooseIndexForQuery:query
                                                       fromIndexes:indexes];
    if (!chosenIndex) {
        return nil;
    }
    
    // Execute SQL on that index with appropriate values
    CDTQSqlParts *select = [CDTQQueryExecutor selectStatementForQuery:query
                                                           usingIndex:chosenIndex];
    NSMutableArray *docIds = [NSMutableArray array];
    
    [_database inDatabase:^(FMDatabase *db) {
        FMResultSet *rs= [db executeQuery:select.sqlWithPlaceholders 
                     withArgumentsInArray:select.placeholderValues];
        while ([rs next]) {
            [docIds addObject:[rs stringForColumn:@"docid"]];
        }
        [rs close];
    }];
    
    // Return results
    return [[CDTQResultSet alloc] initWithDocIds:docIds datastore:self.datastore];
}

+ (NSArray*)neededFieldsForQuery:(NSDictionary*)query
{
    return [query allKeys];  // for now, support one level
}

+ (NSString*)chooseIndexForQuery:(NSDictionary*)query fromIndexes:(NSDictionary*)indexes
{
    NSSet *neededFields = [NSSet setWithArray:[self neededFieldsForQuery:query]];
    
    if (neededFields.count == 0) {
        return nil;  // no point in querying empty set of fields
    }
    
    NSString *chosenIndex = nil;
    for (NSString *indexName in indexes) {
        NSSet *providedFields = [NSSet setWithArray:indexes[indexName]];
        if ([neededFields isSubsetOfSet:providedFields]) {
            chosenIndex = indexName;
            break;
        }
    }
    
    return chosenIndex;
}

+ (CDTQSqlParts*)wherePartsForQuery:(NSDictionary*)query
{
    NSArray *fields = [[query allKeys] sortedArrayUsingSelector:@selector(compare:)];
    
    if (fields.count == 0) {
        return nil;  // no point in querying empty set of fields
    }
    
    NSMutableArray *clauses = [NSMutableArray array];
    NSMutableArray *parameters = [NSMutableArray array];
    for (NSString *field in fields) {
        NSString *clause = [NSString stringWithFormat:@"%@ = ?", field];
        [clauses addObject:clause];
        
        NSDictionary *predicate = [query objectForKey:field];
        // We only support $eq right now
        [parameters addObject:[predicate objectForKey:@"$eq"]];
    }
    
    return [CDTQSqlParts partsForSql:[clauses componentsJoinedByString:@" AND "]
                          parameters:parameters];
    
}

+ (CDTQSqlParts*)selectStatementForQuery:(NSDictionary*)query usingIndex:(NSString*)indexName
{
    if (query.count == 0) {
        return nil;  // no query here
    }
    
    if (!indexName) {
        return nil;
    }
    
    CDTQSqlParts *where = [CDTQQueryExecutor wherePartsForQuery:query];
    NSString *tableName = [CDTQIndexManager tableNameForIndex:indexName];
    
    NSString *sql = @"SELECT docid FROM %@ WHERE %@;";
    sql = [NSString stringWithFormat:sql, tableName, where.sqlWithPlaceholders];
    
    CDTQSqlParts *parts = [CDTQSqlParts partsForSql:sql
                                         parameters:where.placeholderValues];
    return parts;
}

@end
