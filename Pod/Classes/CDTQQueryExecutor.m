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

#pragma mark Instance methods

- (CDTQResultSet*)find:(NSDictionary *)query
          usingIndexes:(NSDictionary *)indexes
                  skip:(NSUInteger)skip
                 limit:(NSUInteger)limit
                fields:(NSArray *)fields
                  sort:(NSArray*)sortDocument
{
    //
    // Validate inputs
    //
    
    if (![CDTQQueryExecutor validateSortDocument:sortDocument]) {
        return nil;  // validate logs the error if doc is invalid
    }
    
    fields = [CDTQQueryExecutor normaliseFields:fields];
    
    if (![CDTQQueryExecutor validateFields:fields]) {
        return nil;  // validate logs error message
    }
    
    //
    // Execute the query
    //
    
    CDTQOrQueryNode *root = (CDTQOrQueryNode*)[CDTQQuerySqlTranslator translateQuery:query
                                                                        toUseIndexes:indexes];
    
    if(!root) {
        return nil;
    }
    
    __block NSArray *docIds;
    
    [_database inTransaction:^(FMDatabase *db, BOOL *rollback) {
        NSSet *docIdSet = [self executeQueryTree:root inDatabase:db];
        
        // sorting
        if (sortDocument != nil && sortDocument.count > 0) {
            docIds = [CDTQQueryExecutor sortIds:docIdSet 
                                      usingSort:sortDocument 
                                        indexes:indexes 
                                     inDatabase:db];
        } else {
            docIds = [docIdSet allObjects];
        }
    }];
    
    // nil if an error during sorting
    if (docIds == nil) {
        return nil;
    }
    
    // skip + limit
    if(skip < docIds.count){
        NSUInteger maxLength = docIds.count - skip;
        NSRange range = NSMakeRange(skip, MIN(limit, maxLength));
        docIds = [docIds subarrayWithRange:range];
    } else {
        docIds =  @[];
    }
    
    return [[CDTQResultSet alloc] initWithDocIds:docIds
                                       datastore:self.datastore
                                projectionFields:fields];  
}

#pragma mark Validation helpers

+ (BOOL)validateSortDocument:(NSArray/*NSDictionary*/*)sortDocument
{
    if (sortDocument == nil || sortDocument.count == 0) {
        return YES;  // empty or nil sort docs just mean "don't sort", so are valid
    }
    
    for (NSDictionary* clause in sortDocument) {
        
        if (clause.count > 1) {
            LogError(@"Each order clause can only be a single field, %@", clause);
            return NO;
        }
        
        NSString *fieldName = [clause allKeys][0];
        NSString *direction = clause[fieldName];
        
        if (![fieldName isKindOfClass:[NSString class]]) {
            LogError(@"Field names in sort clause must be strings, %@", fieldName);
            return NO;
        }
        
        if (![@[ @"ASC", @"DESC" ] containsObject:[direction uppercaseString]]) {
            LogError(@"Order direction %@ not valid, use `asc` or `desc`", direction);
            return NO;
        }
    }
    
    return YES;
}

/**
 Checks if the fields are valid.
 */
+ (BOOL)validateFields:(NSArray*)fields
{
    for (NSString *field in fields) {
        
        if(![field isKindOfClass:[NSString class]]){
            LogError(@"Projection field should be string object: %@", [field description]);
            return NO;
        }
        
        if ([field containsString:@"."]) {
            LogError(@"Projection field cannot use dotted notation: %@", [field description]);
            return NO;
        }
        
    };
    
    return YES;
}

+ (NSArray*)normaliseFields:(NSArray*)fields
{
    if (fields.count == 0) {
        LogWarn(@"Projection fields array is empty, disabling project for this query");
        return nil;
    }
    
    return fields;
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

#pragma mark Sorting

/**
 Return ordered list of document IDs using provided indexes.
 
 Method assumes `sortDocument` is valid.
 
 @param docIdSet Set of current results which are sorted
 @param sortDocument Array of ordering definitions 
                     `@[ @{"fieldName": "asc"}, @{@"fieldName2", @"desc"} ]`
 @param indexes dictionary of indexes
 @param db database containing `indexes` to use when sorting documents
 */
 
+ (NSArray*)sortIds:(NSSet/*NSString*/*)docIdSet 
          usingSort:(NSArray/*NSDictionary*/*)sortDocument 
            indexes:(NSDictionary*)indexes
         inDatabase:(FMDatabase*)db
{
    CDTQSqlParts *orderBy = [CDTQQueryExecutor sqlToSortUsingOrder:sortDocument
                                                           indexes:indexes];
    NSArray *sortedIds;
    
    if (orderBy != nil) {
        NSMutableArray *sortedDocIds = [NSMutableArray array];
        
        // The query will iterate through a sorted list of docIds.
        // This means that if we create a new array and add entries
        // to that array as we iterate through the result set which
        // are part of the query's results, we'll end up with an
        // ordered set of results.
        FMResultSet *rs= [db executeQuery:orderBy.sqlWithPlaceholders 
                     withArgumentsInArray:orderBy.placeholderValues];
        while ([rs next]) {
            NSString *candidateId = [rs stringForColumnIndex:0];
            if ([docIdSet containsObject:candidateId]) {
                [sortedDocIds addObject:candidateId];
            }
        }
        [rs close];
        sortedIds = [NSArray arrayWithArray:sortedDocIds];
    } else {
        sortedIds = nil;  // error doing the ordering
    }
    
    return sortedIds;
}

/**
 Return SQL to get ordered list of docIds.
 
 Method assumes `sortDocument` is valid.
 
 @param sortDocument Array of ordering definitions 
                     `@[ @{"fieldName": "asc"}, @{@"fieldName2", @"desc"} ]`
 @param indexes dictionary of indexes
 */
+ (CDTQSqlParts*)sqlToSortUsingOrder:(NSArray/*NSDictionary*/*)sortDocument
                             indexes:(NSDictionary*)indexes
{
    NSString *chosenIndex = [CDTQQueryExecutor chooseIndexForSort:sortDocument
                                                      fromIndexes:indexes];
    if (chosenIndex == nil) {
        LogError(@"No single index can satisfy order %@", sortDocument);
        return nil;
    }
    
    
    NSString *indexTable = [CDTQIndexManager tableNameForIndex:chosenIndex];
    
    // SELECT _id FROM idx ORDER BY fieldName ASC, fieldName2 DESC;
    
    NSMutableArray *orderClauses = [NSMutableArray array];
    for (NSDictionary* orderClause in sortDocument) {
        
        NSString *fieldName = [orderClause allKeys][0];
        NSString *direction = orderClause[fieldName];
        
        NSString *orderClause = [NSString stringWithFormat:@"\"%@\" %@", 
                                 fieldName, [direction uppercaseString]];
        [orderClauses addObject:orderClause];
    }
    
    NSString *sql = [NSString stringWithFormat:@"SELECT DISTINCT _id FROM %@ ORDER BY %@;", 
                     indexTable, 
                     [orderClauses componentsJoinedByString:@", "]];
    return [CDTQSqlParts partsForSql:sql parameters:@[]];
}

+ (NSString*)chooseIndexForSort:(NSArray/*NSDictionary*/*)sortDocument
                    fromIndexes:(NSDictionary*)indexes
{
    NSMutableSet *neededFields = [NSMutableSet set];
    [sortDocument enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        // This is validated and normalised already to be a dictionary with one key.
        NSDictionary *orderSpecifier = (NSDictionary*)obj;
        [neededFields addObject:[orderSpecifier allKeys][0]];
    }];
    
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

@end
