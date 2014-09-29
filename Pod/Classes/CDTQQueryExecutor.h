//
//  CDTQQueryExecutor.h
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

#import <Foundation/Foundation.h>

@class CDTDatastore;
@class CDTQResultSet;
@class CDTQSqlParts;
@class FMDatabaseQueue;

/**
 Handles querying indexes for a given datastore.
 */
@interface CDTQQueryExecutor : NSObject


/**
 Execute the query passed using the selection of index definition provided.
 
 The index definitions are presumed to already exist and be up to date for the
 datastore and database passed to the constructor.
 
 A covering index for the query must exist in the selection passed to the method.
 
 @param query query to execute.
 @param indexes indexes to use (this method will select the most appropriate).
 */
+ (CDTQResultSet*)find:(NSDictionary*)query 
          usingIndexes:(NSDictionary*)indexes
            inDatabase:(FMDatabaseQueue*)database
         fromDatastore:(CDTDatastore*)datastore;

/**
 Constructs a new CDTQQueryExecutor using the indexes in `database` to find documents from
 `datastore`.
 */
- (instancetype)initWithDatabase:(FMDatabaseQueue*)database
                       datastore:(CDTDatastore*)datastore;

/**
 Execute the query passed using the selection of index definition provided.
 
 The index definitions are presumed to already exist and be up to date for the
 datastore and database passed to the constructor.
 
 A covering index for the query must exist in the selection passed to the method.
 
 @param query query to execute.
 @param indexes indexes to use (this method will select the most appropriate).
 */
- (CDTQResultSet*)find:(NSDictionary*)query usingIndexes:(NSDictionary*)indexes;

/**
 Selects an index to use for a given query from the set provided.
 
 Here we're looking for the index which supports all the fields used in the query.
 
 @param query full query provided by user.
 @param indexes index list of the form @{indexName: @[fieldName1, fieldName2]}
 @return name of index from `indexes` to ues for `query`, or `nil` if none found.
 */
+ (NSString*)chooseIndexForQuery:(NSDictionary*)query fromIndexes:(NSDictionary*)indexes;

/**
 Returns the SQL WHERE clause for a query.
 */
+ (CDTQSqlParts*)wherePartsForQuery:(NSDictionary*)query;

/**
 Returns the SQL statement to find document IDs matching query.
 
 @param query the query being executed.
 @param indexName the index selected for use in this query
 */
+ (CDTQSqlParts*)selectStatementForQuery:(NSDictionary*)query usingIndex:(NSString*)indexName;

@end
