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

static NSString *const AND = @"$and";

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
    query = [CDTQQueryExecutor normaliseQuery:query];
    
    NSString *chosenIndex = [CDTQQueryExecutor chooseIndexForAndClause:query[AND]
                                                           fromIndexes:indexes];
    if (!chosenIndex) {
        return nil;
    }
    
    // Execute SQL on that index with appropriate values
    CDTQSqlParts *select = [CDTQQueryExecutor selectStatementForAndClause:query[AND]
                                                               usingIndex:chosenIndex];
    if (!select) {
        return nil;
    }

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

#pragma mark Pre-process query

+ (NSDictionary*)normaliseQuery:(NSDictionary*)query
{
    if (query.count == 1 && query[AND]) {
        return query;
    }
    
    NSMutableArray *andClause = [NSMutableArray array];
    for (NSString *k in query) {
        [andClause addObject:@{k: query[k]}];
    }
    
    return @{AND: [NSArray arrayWithArray:andClause]};
}

#pragma mark Process single AND clause with no sub-clauses

+ (NSArray*)neededFieldsForAndClause:(NSArray*)clause
{
    // @[@{@"fieldName": @"mike"}, ...]
    // for now support one level of AND
    return [CDTQQueryExecutor fieldsForAndClause:clause];
}

+ (NSArray*)fieldsForAndClause:(NSArray*)clause 
{
    NSMutableArray *fieldNames = [NSMutableArray array];
    for (NSDictionary* term in clause) {
        if (term.count == 1) {
            [fieldNames addObject:[term allKeys][0]];
        }
    }
    return [NSArray arrayWithArray:fieldNames];
}

+ (NSString*)chooseIndexForAndClause:(NSArray*)clause fromIndexes:(NSDictionary*)indexes
{
    NSSet *neededFields = [NSSet setWithArray:[self neededFieldsForAndClause:clause]];
    
    if (neededFields.count == 0) {
        return nil;  // no point in querying empty set of fields
    }
    
    NSString *chosenIndex = nil;
    for (NSString *indexName in indexes) {
        NSSet *providedFields = [NSSet setWithArray:indexes[indexName][@"fields"]];
        if ([neededFields isSubsetOfSet:providedFields]) {
            chosenIndex = indexName;
            break;
        }
    }
    
    return chosenIndex;
}

+ (CDTQSqlParts*)wherePartsForAndClause:(NSArray*)clause
{
    if (clause.count == 0) {
        return nil;  // no point in querying empty set of fields
    }
    
    // @[@{@"fieldName": @"mike"}, ...]
    
    NSMutableArray *sqlClauses = [NSMutableArray array];
    NSMutableArray *sqlParameters = [NSMutableArray array];
    NSDictionary *operatorMap = @{@"$eq": @"=",
                                  @"$gt": @">",
                                  @"$gte": @">=",
                                  @"$lt": @"<",
                                  @"$lte": @"<=",
                                  };
    for (NSDictionary *component in clause) {
        
        if (component.count != 1) {
            return nil;
        }
        
        NSString *fieldName = component.allKeys[0];
        NSDictionary *predicate = component[fieldName];
        
        if (predicate.count != 1) {
            return nil;
        }
        
        NSString *operator = predicate.allKeys[0];
        NSString *sqlOperator = operatorMap[operator];
        
        if (!sqlOperator) {
            return nil;
        }
        
        NSString *sqlClause = [NSString stringWithFormat:@"\"%@\" %@ ?", 
                            fieldName, sqlOperator];
        [sqlClauses addObject:sqlClause];
        
        [sqlParameters addObject:[predicate objectForKey:operator]];
    }
    
    return [CDTQSqlParts partsForSql:[sqlClauses componentsJoinedByString:@" AND "]
                          parameters:sqlParameters];
    
}

+ (CDTQSqlParts*)selectStatementForAndClause:(NSArray*)clause usingIndex:(NSString*)indexName
{
    if (clause.count == 0) {
        return nil;  // no query here
    }
    
    if (!indexName) {
        return nil;
    }
    
    CDTQSqlParts *where = [CDTQQueryExecutor wherePartsForAndClause:clause];
    
    if (!where) {
        return nil;
    }

    NSString *tableName = [CDTQIndexManager tableNameForIndex:indexName];
    
    NSString *sql = @"SELECT docid FROM %@ WHERE %@;";
    sql = [NSString stringWithFormat:sql, tableName, where.sqlWithPlaceholders];
    
    CDTQSqlParts *parts = [CDTQSqlParts partsForSql:sql
                                         parameters:where.placeholderValues];
    return parts;
}

@end
