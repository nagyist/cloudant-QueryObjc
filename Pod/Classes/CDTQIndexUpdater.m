//
//  CDTQIndexUpdater.m
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

#import "CDTQIndexUpdater.h"

#import "CDTQIndexManager.h"
#import "CDTQResultSet.h"
#import "CDTQValueExtractor.h"

#import "CloudantSync.h"

#import "FMDB.h"

#import "TD_Database.h"
#import "TD_Body.h"

#import "CDTQLogging.h"

@interface CDTQIndexUpdater ()

@property (nonatomic,strong) FMDatabaseQueue *database;
@property (nonatomic,strong) CDTDatastore *datastore;

@end

@implementation CDTQIndexUpdater

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

/**
 Update all the indexes in a set.
 
 The indexes are assumed to already exist.
 */
+ (BOOL)updateAllIndexes:(NSDictionary/*NSString -> NSArray[NSString]*/*)indexes
              inDatabase:(FMDatabaseQueue*)database
           fromDatastore:(CDTDatastore*)datastore
{
    CDTQIndexUpdater *updater = [[CDTQIndexUpdater alloc] initWithDatabase:database
                                                                 datastore:datastore];
    BOOL success = [updater updateAllIndexes:indexes];
    return success;
}

/**
 Update a single index.
 
 The index is assumed to already exist.
 */
+ (BOOL)updateIndex:(NSString*)indexName
         withFields:(NSArray/* NSString */*)fieldNames
         inDatabase:(FMDatabaseQueue*)database
      fromDatastore:(CDTDatastore*)datastore
              error:(NSError * __autoreleasing *)error
{
    CDTQIndexUpdater *updater = [[CDTQIndexUpdater alloc] initWithDatabase:database
                                                                 datastore:datastore];
    BOOL success = [updater updateIndex:indexName
                             withFields:fieldNames
                                  error:error];
    return success;
}

#pragma mark Instance methods

- (BOOL)updateAllIndexes:(NSDictionary/*NSString -> NSArray[NSString]*/*)indexes
{
    BOOL success = YES;
    
    for (NSString *indexName in [indexes allKeys]) {
        NSArray *fields = indexes[indexName][@"fields"];
        success = [self updateIndex:indexName
                         withFields:fields
                              error:nil];
    }
    
    return success;
}

- (BOOL)updateIndex:(NSString*)indexName
         withFields:(NSArray/* NSString */*)fieldNames
              error:(NSError * __autoreleasing *)error
{
    BOOL success = YES;
    TDChangesOptions options = {
        .limit = 10000,
        .contentOptions = 0,
        .includeDocs = YES,
        .includeConflicts = NO,
        .sortBySequence = YES
    };
    
    TD_RevisionList *changes;
    SequenceNumber lastSequence = [self sequenceNumberForIndex:indexName];
    
    do {
        changes = [self.datastore.database changesSinceSequence:lastSequence
                                                        options:&options 
                                                         filter:nil 
                                                         params:nil];
        success = success && [self updateIndex:indexName
                                    withFields:fieldNames
                                       changes:changes 
                                  lastSequence:&lastSequence];
    } while (success && [changes count] > 0);
    
    // raise error
    if (!success) {
        if (error) {
            NSDictionary *userInfo =
            @{NSLocalizedDescriptionKey: NSLocalizedString(@"Problem updating index.", nil)};
            *error = [NSError errorWithDomain:CDTQIndexManagerErrorDomain
                                         code:CDTIndexErrorSqlError
                                     userInfo:userInfo];
        }
    }
    
    return success;
}

- (BOOL)updateIndex:(NSString*)indexName
         withFields:(NSArray/* NSString */*)fieldNames
            changes:(TD_RevisionList*)changes
       lastSequence:(SequenceNumber*)lastSequence
{
    __block bool success = YES;
    
    [_database inTransaction:^(FMDatabase *db, BOOL *rollback) {
        
        for(TD_Revision *rev in changes) {
            // Delete existing values
            CDTQSqlParts *parts = [CDTQIndexUpdater partsToDeleteIndexEntriesForDocId:rev.docID
                                                                            fromIndex:indexName];
            [db executeUpdate:parts.sqlWithPlaceholders withArgumentsInArray:parts.placeholderValues];
            
            // Insert new values if the rev isn't deleted
            if (!rev.deleted) {
                // TODO
                // Ignoring the attachments seems reasonable right now as we don't index them.
                CDTDocumentRevision *cdtRev = [[CDTDocumentRevision alloc] initWithDocId:rev.docID
                                                                              revisionId:rev.revID
                                                                                    body:rev.body.properties
                                                                                 deleted:rev.deleted 
                                                                             attachments:@{}  
                                                                                sequence:rev.sequence];
                CDTQSqlParts *insert = [CDTQIndexUpdater partsToIndexRevision:cdtRev
                                                                      inIndex:indexName
                                                               withFieldNames:fieldNames];
                
                // partsToIndexRevision:... returns nil if there are no applicable fields to index
                if (insert) {
                    success = success && [db executeUpdate:insert.sqlWithPlaceholders
                                      withArgumentsInArray:insert.placeholderValues];
                }
                
                if (!success) {
                    LogError(@"Updating index failed, CDTSqlParts: %@", insert);
                }
            }
            if (!success) {
                // TODO fill in error
                *rollback = YES;
                break;
            }
            *lastSequence = [rev sequence];
        }
    }];
    
    // if there was a problem, we rolled back, so the sequence won't be updated
    if (success) {
        return [self updateMetadataForIndex:indexName lastSequence:*lastSequence];
    } else {
        return NO;
    }
}

+ (CDTQSqlParts*)partsToDeleteIndexEntriesForDocId:(NSString*)docId 
                                         fromIndex:(NSString*)indexName
{
    if (!docId) {
        return nil;
    }
    
    if (!indexName) {
        return nil;
    }
    
    NSString *tableName = [CDTQIndexManager tableNameForIndex:indexName];
    
    NSString *sqlDelete = @"DELETE FROM %@ WHERE _id = ?;";
    sqlDelete = [NSString stringWithFormat:sqlDelete, tableName];
    
    return [CDTQSqlParts partsForSql:sqlDelete
                          parameters:@[docId]];
    
}

+ (CDTQSqlParts*)partsToIndexRevision:(CDTDocumentRevision*)rev
                              inIndex:(NSString*)indexName
                       withFieldNames:(NSArray*)fieldNames
{
    if (!rev) {
        return nil;
    }
    
    if (!indexName) {
        return nil;
    }
    
    if (!fieldNames) {
        return nil;
    }
    
    // Field names will equal column names.
    // Therefore need to end up with an array something like:
    // INSERT INTO index_table (_id, fieldName1, fieldName2) VALUES ("abc", "mike", "rhodes")
    // @[ docId, val1, val2 ]
    // INSERT INTO index_table (_id, fieldName1, fieldName2) VALUES ( ?, ?, ? )
    
    // Even if there are no indexable values in the document, we still insert a blank
    // row with the doc ID (this is required for $not amongst other things), so we
    // add the _id info as the first part of the various argument arrays.
    NSMutableArray *args = [NSMutableArray arrayWithArray:@[rev.docId, rev.revId]];
    NSMutableArray *placeholders = [NSMutableArray arrayWithArray:@[@"?", @"?"]];
    NSMutableArray *includedFieldNames = [NSMutableArray arrayWithArray:@[@"_id", @"_rev"]];
    
    for (NSString *fieldName in fieldNames) {
        if ([@[@"_id", @"_rev"] containsObject:fieldNames]) {
            continue;  // these are already included in the arrays, see above
        }
        
        NSObject *value = [CDTQValueExtractor extractValueForFieldName:fieldName
                                                        fromDictionary:rev.body];
        
        if (value) {
            [includedFieldNames addObject:[NSString stringWithFormat:@"\"%@\"", fieldName]];
            [args addObject:value];
            [placeholders addObject:@"?"];
            
            // TODO validate here whether the derived value is suitable for indexing
            //      in addition to its presence.
        }
    }
    
    // If there are no fields, we just index blank for the doc ID
    NSString *sql;
    sql = @"INSERT INTO %@ ( %@ ) VALUES ( %@ );";
    sql = [NSString stringWithFormat:sql, 
           [CDTQIndexManager tableNameForIndex:indexName],
           [includedFieldNames componentsJoinedByString:@", "],
           [placeholders componentsJoinedByString:@", "]
           ];
    
    return [CDTQSqlParts partsForSql:sql parameters:args];
}

- (SequenceNumber)sequenceNumberForIndex:(NSString*)indexName
{
    __block SequenceNumber result = 0;
    
    // get current version
    [_database inDatabase:^(FMDatabase *db) {  
        NSString *sql = @"SELECT last_sequence FROM %@ WHERE index_name = ?";
        sql = [NSString stringWithFormat:sql, kCDTQIndexMetadataTableName];
        FMResultSet *rs= [db executeQuery:sql withArgumentsInArray:@[indexName]];
        while([rs next]) {
            result = [rs longForColumnIndex:0];
            break;  // All rows for a given index will have the same last_sequence, so break
        }
        [rs close];
    }];
    
    return result;
}

-(BOOL)updateMetadataForIndex:(NSString*)indexName
                 lastSequence:(SequenceNumber)lastSequence
{
    __block BOOL success = TRUE;
    
    NSDictionary *v = @{@"name": indexName,
                        @"last_sequence": @(lastSequence)};
    NSString *template = @"UPDATE %@ SET last_sequence = :last_sequence where index_name = :name;";
    NSString *sql = [NSString stringWithFormat:template, kCDTQIndexMetadataTableName];
    
    [_database inDatabase:^(FMDatabase *db) {
        success = [db executeUpdate:sql withParameterDictionary:v];
    }];
    
    return success;
}

@end
