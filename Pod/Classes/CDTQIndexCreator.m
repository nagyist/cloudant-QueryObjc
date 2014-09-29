//
//  CDTQIndexCreator.m
//  Pods
//
//  Created by Michael Rhodes on 29/09/2014.
//
//

#import "CDTQIndexCreator.h"

#import "CDTQIndexManager.h"
#import "CDTQIndexUpdater.h"

#import "CloudantSync.h"
#import "FMDB.h"

@interface CDTQIndexCreator ()

@property (nonatomic,strong) FMDatabaseQueue *database;
@property (nonatomic,strong) CDTDatastore *datastore;

@end

@implementation CDTQIndexCreator

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

+ (NSString*)ensureIndexed:(NSArray*/* NSString */)fieldNames 
                  withName:(NSString*)indexName
            inDatabase:(FMDatabaseQueue*)database
         fromDatastore:(CDTDatastore*)datastore
{
    CDTQIndexCreator *executor = [[CDTQIndexCreator alloc] initWithDatabase:database
                                                                    datastore:datastore];
    return [executor ensureIndexed:fieldNames withName:indexName];
}

#pragma mark Instance methods

/**
 Add a single, possibly compound, index for the given field names.
 
 @param fieldNames List of fieldnames in the sort format
 @param indexName Name of index to create.
 @returns name of created index
 */
- (NSString*)ensureIndexed:(NSArray*/* NSString */)fieldNames withName:(NSString*)indexName
{
    if (fieldNames.count == 0) { 
        return nil;
    }
    
    if (!indexName) {
        return nil;
    }
    
    fieldNames = [CDTQIndexCreator removeDirectionsFromFields:fieldNames];
    
    __block BOOL success = YES;
    
    // TODO validate field names
    // TODO validate index name
    // TODO make sure an index with the same name but different structure doesn't exist
    // TODO create index table
    
    [_database inTransaction:^(FMDatabase *db, BOOL *rollback) {
        
        // Insert metadata table entries
        NSArray *inserts = [CDTQIndexCreator insertMetadataStatementsForIndexName:indexName
                                                                       fieldNames:fieldNames];
        for (CDTQSqlParts *sql in inserts) {
            success = success && [db executeUpdate:sql.sqlWithPlaceholders
                              withArgumentsInArray:sql.placeholderValues];
        }
        
        // Create the table for the index
        CDTQSqlParts *createTable = [CDTQIndexCreator createIndexTableStatementForIndexName:indexName
                                                                                 fieldNames:fieldNames];
        success = success && [db executeUpdate:createTable.sqlWithPlaceholders
                          withArgumentsInArray:createTable.placeholderValues];
        
        // Create the SQLite index on the index table
        
        CDTQSqlParts *createIndex = [CDTQIndexCreator createIndexIndexStatementForIndexName:indexName
                                                                                 fieldNames:fieldNames];
        success = success && [db executeUpdate:createIndex.sqlWithPlaceholders
                          withArgumentsInArray:createIndex.placeholderValues];
        
        if (!success) {
            *rollback = YES;
        }
    }];
    
    // Update the new index if it's been created
    if (success) {
        [CDTQIndexUpdater updateIndex:indexName
                           withFields:fieldNames
                           inDatabase:_database
                        fromDatastore:_datastore
                                error:nil];
    }
    
    return success ? indexName : nil;
}

/**
 We don't support directions on field names, but they are an optimisation so
 we can discard them safely.
 */
+ (NSArray/*NSDictionary or NSString*/*)removeDirectionsFromFields:(NSArray*)fieldNames
{
    NSMutableArray *result = [NSMutableArray array];
    
    for (NSObject *field in fieldNames) {
        if ([field isKindOfClass:[NSDictionary class]]) {
            NSDictionary *specifier = (NSDictionary*)field;
            if (specifier.count == 1) {
                NSString *fieldName = [specifier allKeys][0];
                [result addObject:fieldName];
            }
        } else if ([field isKindOfClass:[NSString class]]) {
            [result addObject:field];
        }
    }
    
    return result;
}

+ (NSArray/*CDTQSqlParts*/*)insertMetadataStatementsForIndexName:(NSString*)indexName
                                                      fieldNames:(NSArray/*NSString*/*)fieldNames
{
    if (!indexName) {
        return nil;
    }
    
    if (!fieldNames || fieldNames.count == 0) {
        return nil;
    }
    
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *fieldName in fieldNames) {
        NSString *sql = @"INSERT INTO %@ "
        "(index_name, field_name, last_sequence) "
        "VALUES (?, ?, 0);";
        sql = [NSString stringWithFormat:sql, kCDTQIndexMetadataTableName];
        
        CDTQSqlParts *parts = [CDTQSqlParts partsForSql:sql
                                             parameters:@[indexName, fieldName]];
        [result addObject:parts];
    }
    return result;
}

+ (CDTQSqlParts*)createIndexTableStatementForIndexName:(NSString*)indexName
                                            fieldNames:(NSArray/*NSString*/*)fieldNames
{
    if (!indexName) {
        return nil;
    }
    
    if (!fieldNames || fieldNames.count == 0) {
        return nil;
    }
    
    NSString *tableName = [CDTQIndexManager tableNameForIndex:indexName];
    NSMutableArray *clauses = [NSMutableArray arrayWithObject:@"docid"];
    for (NSString *fieldName in fieldNames) {
        NSString *clause = [NSString stringWithFormat:@"%@ NONE", fieldName];
        [clauses addObject:clause];
    }
    
    NSString *sql = [NSString stringWithFormat:@"CREATE TABLE %@ ( %@ );", 
                     tableName,
                     [clauses componentsJoinedByString:@", "]];
    return [CDTQSqlParts partsForSql:sql parameters:@[]];
}

+ (CDTQSqlParts*)createIndexIndexStatementForIndexName:(NSString*)indexName
                                            fieldNames:(NSArray/*NSString*/*)fieldNames
{
    if (!indexName) {
        return nil;
    }
    
    if (!fieldNames || fieldNames.count == 0) {
        return nil;
    }
    
    NSString *tableName = [CDTQIndexManager tableNameForIndex:indexName];
    NSString *sqlIndexName = [tableName stringByAppendingString:@"_index"];
    
    NSMutableArray *clauses = [NSMutableArray arrayWithObject:@"docid"];
    for (NSString *fieldName in fieldNames) {
        [clauses addObject:fieldName];
    }
    
    NSString *sql = [NSString stringWithFormat:@"CREATE INDEX %@ ON %@ ( %@ );",
                     sqlIndexName, 
                     tableName, 
                     [clauses componentsJoinedByString:@", "]];
    return [CDTQSqlParts partsForSql:sql parameters:@[]];
}

@end
