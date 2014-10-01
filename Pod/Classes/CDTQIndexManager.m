//
//  CDTQIndexManager.m
//  
//  Created by Mike Rhodes on 2014-09-27
//  Copyright (c) 2014 Cloudant. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

//
// The metadata for an index is represented in the database table as follows:
//
//   index_name  |  field_name  |  last_sequence
//   -------------------------------------------
//     name      |  firstName   |     0
//     name      |  lastName    |     0
//     age       |  age         |     0
//
// The index itself is a single table, with a colum for docId and each of the indexed fields:
//
//     doc_id    |  firstName   |  lastName
//   -------------------------------------------
//     miker     |  Mike        |  Rhodes
//     johna     |  John        |  Appleseed
//     joeb      |  Joe         |  Bloggs
// 
// There is a single SQLite index created on all columns of this table.
//

#import "CDTQIndexManager.h"

#import "CDTQResultSet.h"
#import "CDTQIndexUpdater.h"
#import "CDTQQueryExecutor.h"
#import "CDTQIndexCreator.h"

#import "TD_Database.h"
#import "TD_Body.h"

#import <CloudantSync.h>
#import <FMDB.h>

NSString* const CDTQIndexManagerErrorDomain = @"CDTIndexManagerErrorDomain";

NSString* const kCDTQIndexTablePrefix = @"_t_cloudant_sync_query_index_";
NSString* const kCDTQIndexMetadataTableName = @"_t_cloudant_sync_query_metadata";

static NSString* const kCDTQExtensionName = @"com.cloudant.sync.query";
static NSString* const kCDTQIndexFieldNamePattern = @"^[a-zA-Z][a-zA-Z0-9_]*$";

static const int VERSION = 1;

@interface CDTQIndexManager ()

@property (nonatomic,strong) FMDatabaseQueue *database;
@property (nonatomic,strong) NSRegularExpression *validFieldName;

@end

@implementation CDTQSqlParts

+ (CDTQSqlParts*)partsForSql:(NSString*)sql parameters:(NSArray*)parameters
{
    CDTQSqlParts *parts = [[CDTQSqlParts alloc] init];
    parts.sqlWithPlaceholders = sql;
    parts.placeholderValues = parameters;
    return parts;
}

- (NSString*)description {
    return [NSString stringWithFormat:@"sql: %@ vals: %@", 
            self.sqlWithPlaceholders, self.placeholderValues];
}

@end

@implementation CDTQIndexManager

+ (CDTQIndexManager*)managerUsingDatastore:(CDTDatastore*)datastore 
                                     error:(NSError * __autoreleasing *)error
{
    return [[CDTQIndexManager alloc] initUsingDatastore:datastore error:error];
}

- (instancetype)initUsingDatastore:(CDTDatastore*)datastore
                             error:(NSError * __autoreleasing *)error 
{
    self = [super init];
    if (self) {
        _datastore = datastore;
        _validFieldName = [[NSRegularExpression alloc] initWithPattern:kCDTQIndexFieldNamePattern
                                                               options:0 
                                                                 error:error];
        
        NSString *dir = [datastore extensionDataFolder:kCDTQExtensionName];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:TRUE 
                                                   attributes:nil 
                                                        error:nil];
        NSString *filename = [NSString pathWithComponents:@[dir, @"indexes.sqlite"]];
        _database = [[FMDatabaseQueue alloc] initWithPath:filename];
        if (! _database) {
            if (error) {
                NSDictionary *userInfo =
                @{NSLocalizedDescriptionKey: NSLocalizedString(@"Problem opening or creating database.", nil)};
                *error = [NSError errorWithDomain:CDTQIndexManagerErrorDomain
                                             code:CDTQIndexErrorSqlError
                                         userInfo:userInfo];
            }
            return nil;
        }
        
        if (![self updateSchema:VERSION]) {
            if (error) {
                NSDictionary *userInfo =
                @{NSLocalizedDescriptionKey: NSLocalizedString(@"Problem updating database schema.", nil)};
                *error = [NSError errorWithDomain:CDTQIndexManagerErrorDomain
                                             code:CDTQIndexErrorSqlError
                                         userInfo:userInfo];
            }
            return nil;
        }
    }
    return self;
}

#pragma mark List indexes

- (NSDictionary*/* NSString -> NSArray[NSString]*/)listIndexes
{
    // Accumulate indexes and definitions into a dictionary
    
    NSMutableDictionary *indexes = [NSMutableDictionary dictionary];
    
    [_database inDatabase:^(FMDatabase *db) {
        NSString *sql = @"SELECT index_name, field_name FROM %@;";
        sql = [NSString stringWithFormat:sql, kCDTQIndexMetadataTableName];
        FMResultSet *rs= [db executeQuery:sql];
        while ([rs next]) {
            NSString *rowIndex = [rs stringForColumn:@"index_name"];
            NSString *rowField = [rs stringForColumn:@"field_name"];
            
            if (indexes[rowIndex] == nil) {
                indexes[rowIndex] = [NSMutableArray array];
            }
            
            [indexes[rowIndex] addObject:rowField];
        }
        [rs close];
    }];
    
    // Now we need to make the return value immutable
    
    for (NSString *k in [indexes allKeys]) {
        NSMutableArray *v = indexes[k];
        indexes[k] = [v copy];  // -copy makes arrays immutable
    }
    
    return [NSDictionary dictionaryWithDictionary:indexes];  // make dictionary immutable
}

#pragma mark Create Indexes

/**
 Add a single, possibly compound, index for the given field names.
 
 This function generates a name for the new index.
 
 @param fieldNames List of fieldnames in the sort format
 @returns name of created index
 */
- (NSString*)ensureIndexed:(NSArray*/* NSString */)fieldNames
{
    return nil;
}

/**
 Add a single, possibly compound, index for the given field names.
 
 @param fieldNames List of fieldnames in the sort format
 @param indexName Name of index to create.
 @returns name of created index
 */
- (NSString*)ensureIndexed:(NSArray*/* NSString */)fieldNames withName:(NSString*)indexName
{
    return [self ensureIndexed:fieldNames
                      withName:indexName
                          type:@"json"];
}

/**
 Add a single, possibly compound, index for the given field names.
 
 @param fieldNames List of fieldnames in the sort format
 @param indexName Name of index to create.
 @param type "json" is the only supported type for now
 @returns name of created index
 */
- (NSString*)ensureIndexed:(NSArray*/* NSString */)fieldNames 
                  withName:(NSString*)indexName
                      type:(NSString*)type
{
    if (fieldNames.count == 0) { 
        return nil;
    }
    
    if (!indexName) {
        return nil;
    }
    
    if (![type isEqualToString:@"json"]) {
        return nil;
    }
    
    return [CDTQIndexCreator ensureIndexed:fieldNames
                                  withName:indexName
                                      type:type
                                inDatabase:_database 
                             fromDatastore:_datastore];
}

#pragma mark Delete Indexes

- (BOOL)deleteIndexNamed:(NSString*)indexName
{
    __block BOOL success = YES;
    
    [_database inTransaction:^(FMDatabase *db, BOOL *rollback) {
        
        NSString *tableName = [CDTQIndexManager tableNameForIndex:indexName];
        NSDictionary *args;
        
        // Drop the index table
        args = @{@"table_name": tableName};
        NSString *sql = @"DROP TABLE :table_name";
        success = success && [db executeUpdate:sql withParameterDictionary:args];
        
        // Delete the metadata entries
        args = @{@"index_name": indexName, 
                 @"metadata": kCDTQIndexMetadataTableName};
        sql = [NSString stringWithFormat:@"DELETE * FROM :metadata WHERE index_name = :index_name"];
        success = success && [db executeUpdate:sql withParameterDictionary:args];
        
        if (!success) {
            *rollback = YES;
        }
    }];
    
    return success;
}

#pragma mark Update indexes

- (BOOL)updateAllIndexes
{
    // TODO
    
    // To start with, assume top-level fields only
    
    NSDictionary *indexes = [self listIndexes];
    return [CDTQIndexUpdater updateAllIndexes:indexes
                                   inDatabase:_database
                                fromDatastore:_datastore];
}

#pragma mark Query indexes

- (CDTQResultSet*)find:(NSDictionary*)query
{
    if (![self updateAllIndexes]) {
        return nil;
    }
    
    NSDictionary *indexes = [self listIndexes];
    
    return [CDTQQueryExecutor find:query
                      usingIndexes:indexes
                        inDatabase:_database
                     fromDatastore:_datastore];
}

#pragma mark Utilities

+ (NSString*)tableNameForIndex:(NSString*)indexName
{
    return [kCDTQIndexTablePrefix stringByAppendingString:indexName];
}

#pragma mark Setup methods

-(BOOL)updateSchema:(int)currentVersion
{
    NSString* SCHEMA_INDEX = @"CREATE TABLE _t_cloudant_sync_query_metadata ( "
    @"        index_name TEXT NOT NULL, "
    @"        field_name TEXT NOT NULL, "
    @"        last_sequence INTEGER NOT NULL);";
    
    __block BOOL success = YES;
    
    // get current version
    [_database inTransaction:^(FMDatabase *db, BOOL *rollback) {
        int version = 0;
        
        FMResultSet *rs= [db executeQuery:@"pragma user_version;"];
        while([rs next]) {
            version = [rs intForColumnIndex:0];
            break;  // should only be a single result, so may as well break
        }
        [rs close];
        
        if (version < currentVersion) {
            // Update schema and update version
            NSString *sql = [NSString stringWithFormat:@"pragma user_version = %d", currentVersion];
            success = success && [db executeUpdate:sql];
            success = success && [db executeUpdate:SCHEMA_INDEX];
            if (!success) {
                *rollback = YES;
            }
        }
    }];
    
    return success;
}

@end
