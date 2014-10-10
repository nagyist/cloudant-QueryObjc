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


SpecBegin(CDTQIndexUpdater)


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
    
    describe(@"when generating DELETE index entries statements", ^{
        
        it(@"returns nil for no docid", ^{
            CDTQSqlParts *parts = [CDTQIndexUpdater partsToDeleteIndexEntriesForDocId:nil
                                                                            fromIndex:@"anIndex"];
            expect(parts).to.beNil();
        });
        
        it(@"returns nil for no index name", ^{
            CDTQSqlParts *parts = [CDTQIndexUpdater partsToDeleteIndexEntriesForDocId:@"123"
                                                                            fromIndex:nil];
            expect(parts).to.beNil();
        });
        
        it(@"returns correctly for document", ^{
            CDTQSqlParts *parts = [CDTQIndexUpdater partsToDeleteIndexEntriesForDocId:@"123"
                                                                            fromIndex:@"anIndex"];
            NSString *sql = @"DELETE FROM _t_cloudant_sync_query_index_anIndex WHERE docid = ?;";
            expect(parts.sqlWithPlaceholders).to.equal(sql);
            expect(parts.placeholderValues).to.equal(@[@"123"]);
        });
        
    });
    
    describe(@"when generating INSERT statements for adding documents", ^{
        
        it(@"returns correctly for single field", ^{
            CDTMutableDocumentRevision *rev = [CDTMutableDocumentRevision revision];
            rev.docId = @"id123";
            rev.body = @{@"name": @"mike"};
            CDTQSqlParts *parts = [CDTQIndexUpdater partsToIndexRevision:rev 
                                                                 inIndex:@"anIndex"
                                                          withFieldNames:@[@"name"]];
            
            NSString *sql = @"INSERT INTO _t_cloudant_sync_query_index_anIndex "
            "( docid, \"name\" ) VALUES ( ?, ? );";
            expect(parts.sqlWithPlaceholders).to.equal(sql);
            expect(parts.placeholderValues).to.equal(@[@"id123", @"mike"]);
        });
        
        it(@"returns correctly for two fields", ^{
            CDTMutableDocumentRevision *rev = [CDTMutableDocumentRevision revision];
            rev.docId = @"id123";
            rev.body = @{@"name": @"mike", @"age": @12};
            CDTQSqlParts *parts = [CDTQIndexUpdater partsToIndexRevision:rev 
                                                                 inIndex:@"anIndex"
                                                          withFieldNames:@[@"age", @"name"]];
            
            NSString *sql = @"INSERT INTO _t_cloudant_sync_query_index_anIndex "
            "( docid, \"age\", \"name\" ) VALUES ( ?, ?, ? );";
            expect(parts.sqlWithPlaceholders).to.equal(sql);
            expect(parts.placeholderValues).to.equal(@[@"id123", @12, @"mike"]);
        });
        
        it(@"returns correctly for multiple fields", ^{
            CDTMutableDocumentRevision *rev = [CDTMutableDocumentRevision revision];
            rev.docId = @"id123";
            rev.body = @{@"name": @"mike", 
                         @"age": @12,
                         @"pet": @"cat",
                         @"car": @"mini",
                         @"ignored": @"something"};
            CDTQSqlParts *parts = [CDTQIndexUpdater partsToIndexRevision:rev 
                                                                 inIndex:@"anIndex"
                                                          withFieldNames:@[@"age", @"name", @"pet", @"car"]];
            
            NSString *sql = @"INSERT INTO _t_cloudant_sync_query_index_anIndex "
            "( docid, \"age\", \"name\", \"pet\", \"car\" ) VALUES ( ?, ?, ?, ?, ? );";
            expect(parts.sqlWithPlaceholders).to.equal(sql);
            expect(parts.placeholderValues).to.equal(@[@"id123", @12, @"mike", @"cat", @"mini"]);
        });
        
        it(@"returns correctly for missing fields", ^{
            CDTMutableDocumentRevision *rev = [CDTMutableDocumentRevision revision];
            rev.docId = @"id123";
            rev.body = @{@"name": @"mike", 
                         @"pet": @"cat",
                         @"ignored": @"something"};
            CDTQSqlParts *parts = [CDTQIndexUpdater partsToIndexRevision:rev 
                                                                 inIndex:@"anIndex"
                                                          withFieldNames:@[@"age", @"name", @"pet", @"car"]];
            
            NSString *sql = @"INSERT INTO _t_cloudant_sync_query_index_anIndex "
            "( docid, \"name\", \"pet\" ) VALUES ( ?, ?, ? );";
            expect(parts.sqlWithPlaceholders).to.equal(sql);
            expect(parts.placeholderValues).to.equal(@[@"id123", @"mike", @"cat"]);
        });
        
        it(@"returns nil if a document has no indexable fields", ^{
            CDTMutableDocumentRevision *rev = [CDTMutableDocumentRevision revision];
            rev.docId = @"id123";
            rev.body = @{@"name": @"mike", 
                         @"pet": @"cat",
                         @"ignored": @"something"};
            CDTQSqlParts *parts = [CDTQIndexUpdater partsToIndexRevision:rev 
                                                                 inIndex:@"anIndex"
                                                          withFieldNames:@[@"car", @"van"]];
            expect(parts).to.beNil();
        });
        
    });
    
    describe(@"when setting sequence numbers", ^{
        
        __block CDTDatastore *ds;
        __block CDTQIndexManager *im;
        
        beforeEach(^{
            ds = [factory datastoreNamed:@"test" error:nil];
            expect(ds).toNot.beNil();
            
            CDTMutableDocumentRevision *rev = [CDTMutableDocumentRevision revision];
            
            rev.docId = @"mike12";
            rev.body = @{ @"name": @"mike", 
                          @"age": @12, 
                          @"pet": @"cat"};
            [ds createDocumentFromRevision:rev error:nil];
            
            rev.docId = @"mike23";
            rev.body = @{ @"name": @"mike", 
                          @"age": @23, 
                          @"pet": @"parrot"};
            [ds createDocumentFromRevision:rev error:nil];
            
            rev.docId = @"mike34";
            rev.body = @{ @"name": @"mike", 
                          @"age": @34, 
                          @"pet": @"dog" };
            [ds createDocumentFromRevision:rev error:nil];
            
            rev.docId = @"john72";
            rev.body = @{ @"name": @"john", 
                          @"age": @34, 
                          @"pet": @"fish" };
            [ds createDocumentFromRevision:rev error:nil];
            
            rev.docId = @"fred34";
            rev.body = @{ @"name": @"fred", 
                          @"age": @43, 
                          @"pet": @"snake" };
            [ds createDocumentFromRevision:rev error:nil];
            
            rev.docId = @"fred12";
            rev.body = @{ @"name": @"fred", 
                          @"age": @12 };
            [ds createDocumentFromRevision:rev error:nil];
            
            im = [CDTQIndexManager managerUsingDatastore:ds error:nil];
            expect(im).toNot.beNil();
            
        });
        
        it(@"sets correct sequence number", ^{
            
            expect([im ensureIndexed:@[@"age", @"pet", @"name"] withName:@"basic"]).toNot.beNil();
            
            FMDatabaseQueue *queue = (FMDatabaseQueue*)[im performSelector:@selector(database)];
            
            CDTQIndexUpdater *updater = [[CDTQIndexUpdater alloc] initWithDatabase:queue
                                                                         datastore:ds];
            expect([updater sequenceNumberForIndex:@"basic"]).to.equal(6);
            
            expect([updater updateAllIndexes:[im listIndexes]]).to.beTruthy();
            
            expect([updater sequenceNumberForIndex:@"basic"]).to.equal(6);
            
        });
        
        it(@"sets correct sequence number after update", ^{
            expect([im ensureIndexed:@[@"age", @"pet", @"name"] withName:@"basic"]).toNot.beNil();
            FMDatabaseQueue *queue = (FMDatabaseQueue*)[im performSelector:@selector(database)];
            CDTQIndexUpdater *updater = [[CDTQIndexUpdater alloc] initWithDatabase:queue
                                                                         datastore:ds];
            
            CDTMutableDocumentRevision *rev = [CDTMutableDocumentRevision revision];
            rev.docId = @"newdoc";
            rev.body = @{ @"name": @"fred", 
                          @"age": @12 };
            [ds createDocumentFromRevision:rev error:nil];
            
            expect([updater updateAllIndexes:[im listIndexes]]).to.beTruthy();
            
            expect([updater sequenceNumberForIndex:@"basic"]).to.equal(7);
            
        });
        
    });
});

SpecEnd
