//
//  CloudantQueryObjcTests.m
//  CloudantQueryObjcTests
//
//  Created by Michael Rhodes on 09/27/2014.
//  Copyright (c) 2014 Michael Rhodes. All rights reserved.
//

#import <CloudantSync.h>
#import <CDTQIndexManager.h>
#import <CDTQIndexUpdater.h>
#import <CDTQIndexCreator.h>
#import <CDTQResultSet.h>
#import <CDTQQueryExecutor.h>


SpecBegin(CDTQIndexCreator)


describe(@"cloudant query", ^{
    
    __block NSString *factoryPath;
    __block CDTDatastoreManager *factory;
    
    beforeEach(^{
        // Create a new CDTDatastoreFactory at a temp path
        
        NSString *tempDirectoryTemplate =
        [NSTemporaryDirectory() stringByAppendingPathComponent:@"cloudant_sync_ios_tests.XXXXXX"];
        const char *tempDirectoryTemplateCString = [tempDirectoryTemplate fileSystemRepresentation];
        char *tempDirectoryNameCString =  (char *)malloc(strlen(tempDirectoryTemplateCString) + 1);
        strcpy(tempDirectoryNameCString, tempDirectoryTemplateCString);
        
        char *result = mkdtemp(tempDirectoryNameCString);
        expect(result).to.beTruthy();
        
        factoryPath = [[NSFileManager defaultManager]
                       stringWithFileSystemRepresentation:tempDirectoryNameCString
                       length:strlen(result)];
        free(tempDirectoryNameCString);
        
        NSError *error;
        factory = [[CDTDatastoreManager alloc] initWithDirectory:factoryPath error:&error];
    });
    
    afterEach(^{
        // Delete the databases we used
        
        factory = nil;
        NSError *error;
        [[NSFileManager defaultManager] removeItemAtPath:factoryPath error:&error];
    });
    
    
    describe(@"when creating indexes", ^{
        
        __block CDTDatastore *ds;
        __block CDTQIndexManager *im;
        
        beforeEach(^{
            ds = [factory datastoreNamed:@"test" error:nil];
            expect(ds).toNot.beNil();
            im = [CDTQIndexManager managerUsingDatastore:ds error:nil];
            expect(im).toNot.beNil();
        });
        
        it(@"doesn't create an index on no fields", ^{
            NSString *name = [im ensureIndexed:@[] withName:@"basic"];
            expect(name).to.equal(nil);
            
            NSDictionary *indexes = [im listIndexes];
            expect(indexes.allKeys.count).to.equal(0);
        });
        
        it(@"doesn't create an index on nil fields", ^{
            NSString *name = [im ensureIndexed:nil withName:@"basic"];
            expect(name).to.equal(nil);
            
            NSDictionary *indexes = [im listIndexes];
            expect(indexes.allKeys.count).to.equal(0);
        });
        
        it(@"doesn't create an index without a name", ^{
            NSString *name = [im ensureIndexed:@[@"name"] withName:nil];
            expect(name).to.equal(nil);
            
            NSDictionary *indexes = [im listIndexes];
            expect(indexes.allKeys.count).to.equal(0);
        });
        
        it(@"can create an index over one fields", ^{
            NSString *name = [im ensureIndexed:@[@"name"] withName:@"basic"];
            expect(name).to.equal(@"basic");
            
            NSDictionary *indexes = [im listIndexes];
            expect(indexes.allKeys.count).to.equal(1);
            expect(indexes.allKeys).to.contain(@"basic");
            
            expect([indexes[@"basic"] count]).to.equal(1);
            expect(indexes[@"basic"]).to.beSupersetOf(@[@"name"]);
        });
        
        it(@"can create an index over two fields", ^{
            NSString *name = [im ensureIndexed:@[@"name", @"age"] withName:@"basic"];
            expect(name).to.equal(@"basic");
            
            NSDictionary *indexes = [im listIndexes];
            expect(indexes.allKeys.count).to.equal(1);
            expect(indexes.allKeys).to.contain(@"basic");
            
            expect([indexes[@"basic"] count]).to.equal(2);
            expect(indexes[@"basic"]).to.beSupersetOf(@[@"name", @"age"]);
        });
        
        it(@"can create more than one index", ^{
            [im ensureIndexed:@[@"name", @"age"] withName:@"basic"];
            [im ensureIndexed:@[@"name", @"age"] withName:@"another"];
            [im ensureIndexed:@[@"cat"] withName:@"petname"];
            
            NSDictionary *indexes = [im listIndexes];
            expect(indexes.allKeys.count).to.equal(3);
            expect(indexes.allKeys).to.beSupersetOf(@[@"basic", @"another", @"petname"]);
            
            expect([indexes[@"basic"] count]).to.equal(2);
            expect(indexes[@"basic"]).to.beSupersetOf(@[@"name", @"age"]);
            
            expect([indexes[@"another"] count]).to.equal(2);
            expect(indexes[@"another"]).to.beSupersetOf(@[@"name", @"age"]);
            
            expect([indexes[@"petname"] count]).to.equal(1);
            expect(indexes[@"petname"]).to.beSupersetOf(@[@"cat"]);
        });
        
        it(@"can create indexes specified with asc/desc", ^{
            NSString *name = [im ensureIndexed:@[@{@"name": @"asc"}, @{@"age": @"desc"}]
                                      withName:@"basic"];
            expect(name).to.equal(@"basic");
            
            NSDictionary *indexes = [im listIndexes];
            expect(indexes.allKeys.count).to.equal(1);
            expect(indexes.allKeys).to.contain(@"basic");
            
            expect([indexes[@"basic"] count]).to.equal(2);
            expect(indexes[@"basic"]).to.beSupersetOf(@[@"name", @"age"]);
        });
        
    });
    
    
    describe(@"when using non-ascii text", ^{
        
        __block CDTDatastore *ds;
        __block CDTQIndexManager *im;
        
        beforeEach(^{
            ds = [factory datastoreNamed:@"test" error:nil];
            expect(ds).toNot.beNil();
            
            im = [CDTQIndexManager managerUsingDatastore:ds error:nil];
            expect(im).toNot.beNil();
        });
        
        it(@"can create indexes successfully", ^{
            expect([im ensureIndexed:@[@"اسم", @"@datatype", @"ages"] withName:@"nonascii"]).toNot.beNil();
        });
    });
    
    describe(@"when normalising index fields", ^{
        
        it(@"removes directions from the field specifiers", ^{
            NSArray *fields = [CDTQIndexCreator removeDirectionsFromFields:@[@{@"name": @"asc"},
                                                                             @{@"pet": @"asc"},
                                                                             @"age"]]; 
            expect(fields).to.equal(@[@"name", @"pet", @"age"]);
        });
        
    });
    
    describe(@"when SQL statements to create indexes", ^{
        
        // INSERT INTO metdata table
        
        it(@"doesn't create insert statements when there are no fields", ^{
            NSArray *fieldNames = @[];
            NSArray *parts = [CDTQIndexCreator insertMetadataStatementsForIndexName:@"anIndex"
                                                                         fieldNames:fieldNames];
            expect(parts).to.beNil();
        });
        
        it(@"can create insert statements for an index with one field", ^{
            NSArray *fieldNames = @[@"name"];
            NSArray *parts = [CDTQIndexCreator insertMetadataStatementsForIndexName:@"anIndex"
                                                                         fieldNames:fieldNames];
            
            CDTQSqlParts *part;
            
            part = parts[0];
            expect(part.sqlWithPlaceholders).to.equal(@"INSERT INTO _t_cloudant_sync_query_metadata" 
                                                      " (index_name, field_name, last_sequence) "
                                                      "VALUES (?, ?, 0);");
            expect(part.placeholderValues).to.equal(@[@"anIndex", @"name"]);
        });
        
        it(@"can create insert statements for an index with many fields", ^{
            NSArray *fieldNames = @[@"name", @"age", @"pet"];
            NSArray *parts = [CDTQIndexCreator insertMetadataStatementsForIndexName:@"anIndex"
                                                                         fieldNames:fieldNames];
            
            CDTQSqlParts *part;
            
            part = parts[0];
            expect(part.sqlWithPlaceholders).to.equal(@"INSERT INTO _t_cloudant_sync_query_metadata" 
                                                      " (index_name, field_name, last_sequence) "
                                                      "VALUES (?, ?, 0);");
            expect(part.placeholderValues).to.equal(@[@"anIndex", @"name"]);
            
            part = parts[1];
            expect(part.sqlWithPlaceholders).to.equal(@"INSERT INTO _t_cloudant_sync_query_metadata" 
                                                      " (index_name, field_name, last_sequence) "
                                                      "VALUES (?, ?, 0);");
            expect(part.placeholderValues).to.equal(@[@"anIndex", @"age"]);
            
            part = parts[2];
            expect(part.sqlWithPlaceholders).to.equal(@"INSERT INTO _t_cloudant_sync_query_metadata" 
                                                      " (index_name, field_name, last_sequence) "
                                                      "VALUES (?, ?, 0);");
            expect(part.placeholderValues).to.equal(@[@"anIndex", @"pet"]);
        });
        
        // CREATE TABLE for Cloudant Query index
        
        it(@"doesn't create table statements when there are no fields", ^{
            NSArray *fieldNames = @[];
            CDTQSqlParts *parts = [CDTQIndexCreator createIndexTableStatementForIndexName:@"anIndex"
                                                                               fieldNames:fieldNames];
            expect(parts).to.beNil();
        });
        
        it(@"can create table statements for an index with many fields", ^{
            NSArray *fieldNames = @[@"name"];
            CDTQSqlParts *parts = [CDTQIndexCreator createIndexTableStatementForIndexName:@"anIndex"
                                                                               fieldNames:fieldNames];
            expect(parts.sqlWithPlaceholders).to.equal(@"CREATE TABLE _t_cloudant_sync_query_index_anIndex" 
                                                       " ( docid, \"name\" NONE );");
            expect(parts.placeholderValues).to.equal(@[]);
        });
        
        it(@"can create table statements for an index with many fields", ^{
            NSArray *fieldNames = @[@"name", @"age", @"pet"];
            CDTQSqlParts *parts = [CDTQIndexCreator createIndexTableStatementForIndexName:@"anIndex"
                                                                               fieldNames:fieldNames];
            expect(parts.sqlWithPlaceholders).to.equal(@"CREATE TABLE _t_cloudant_sync_query_index_anIndex" 
                                                       " ( docid, \"name\" NONE, \"age\" NONE, \"pet\" NONE );");
            expect(parts.placeholderValues).to.equal(@[]);
        });
        
        // CREATE INDEX for Cloudant Query index
        
        it(@"doesn't create table index statements when there are no fields", ^{
            NSArray *fieldNames = @[];
            CDTQSqlParts *parts = [CDTQIndexCreator createIndexIndexStatementForIndexName:@"anIndex"
                                                                               fieldNames:fieldNames];
            expect(parts).to.beNil();
        });
        
        it(@"can create table index statements for an index with many fields", ^{
            NSArray *fieldNames = @[@"name"];
            CDTQSqlParts *parts = [CDTQIndexCreator createIndexIndexStatementForIndexName:@"anIndex"
                                                                               fieldNames:fieldNames];
            expect(parts.sqlWithPlaceholders).to.equal(@"CREATE INDEX _t_cloudant_sync_query_index_anIndex_index " 
                                                       "ON _t_cloudant_sync_query_index_anIndex" 
                                                       " ( docid, \"name\" );");
            expect(parts.placeholderValues).to.equal(@[]);
        });
        
        it(@"can create table index statements for an index with many fields", ^{
            NSArray *fieldNames = @[@"name", @"age", @"pet"];
            CDTQSqlParts *parts = [CDTQIndexCreator createIndexIndexStatementForIndexName:@"anIndex"
                                                                               fieldNames:fieldNames];
            expect(parts.sqlWithPlaceholders).to.equal(@"CREATE INDEX _t_cloudant_sync_query_index_anIndex_index " 
                                                       "ON _t_cloudant_sync_query_index_anIndex" 
                                                       " ( docid, \"name\", \"age\", \"pet\" );");
            expect(parts.placeholderValues).to.equal(@[]);
        });
    });
});

SpecEnd
