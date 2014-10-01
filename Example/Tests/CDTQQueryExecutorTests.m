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


SpecBegin(CDTQQueryExecutor)


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
    
    describe(@"when executing queries", ^{
        
        __block CDTDatastore *ds;
        __block CDTQIndexManager *im;
        
        beforeEach(^{
            ds = [factory datastoreNamed:@"test" error:nil];
            expect(ds).toNot.beNil();
            
            CDTMutableDocumentRevision *rev = [CDTMutableDocumentRevision revision];
            
            rev.docId = @"mike12";
            rev.body = @{ @"name": @"mike", @"age": @12, @"pet": @"cat" };
            [ds createDocumentFromRevision:rev error:nil];
            
            rev.docId = @"mike34";
            rev.body = @{ @"name": @"mike", @"age": @34, @"pet": @"dog" };
            [ds createDocumentFromRevision:rev error:nil];
            
            rev.docId = @"mike72";
            rev.body = @{ @"name": @"mike", @"age": @34, @"pet": @"cat" };
            [ds createDocumentFromRevision:rev error:nil];
            
            rev.docId = @"fred34";
            rev.body = @{ @"name": @"fred", @"age": @34, @"pet": @"cat" };
            [ds createDocumentFromRevision:rev error:nil];
            
            rev.docId = @"fred12";
            rev.body = @{ @"name": @"fred", @"age": @12 };
            [ds createDocumentFromRevision:rev error:nil];
            
            im = [CDTQIndexManager managerUsingDatastore:ds error:nil];
            expect(im).toNot.beNil();
            
            expect([im ensureIndexed:@[@"name", @"age"] withName:@"basic"]).toNot.beNil();
            expect([im ensureIndexed:@[@"name", @"pet"] withName:@"pet"]).toNot.beNil();
        });
        
        it(@"can query over one string field", ^{
            NSDictionary *query = @{@"name": @{@"$eq": @"mike"}};
            CDTQResultSet *result = [im find:query];
            expect(result).toNot.beNil();
            expect(result.documentIds.count).to.equal(3);
        });
        
        it(@"can query over one number field", ^{
            NSDictionary *query = @{@"age": @{@"$eq": @12}};
            CDTQResultSet *result = [im find:query];
            expect(result).toNot.beNil();
            expect(result.documentIds.count).to.equal(2);
        });
        
        it(@"can query over two string fields", ^{
            NSDictionary *query = @{@"name": @{@"$eq": @"mike"}, 
                                    @"pet": @{@"$eq": @"cat"}};
            CDTQResultSet *result = [im find:query];
            expect(result).toNot.beNil();
            expect(result.documentIds.count).to.equal(2);
        });
        
        it(@"can query over two mixed fields", ^{
            NSDictionary *query = @{@"name": @{@"$eq": @"mike"}, 
                                    @"age": @{@"$eq": @12}};
            CDTQResultSet *result = [im find:query];
            expect(result).toNot.beNil();
            expect(result.documentIds.count).to.equal(1);
        });
        
        it(@"returns no results when query is for one predicate without match", ^{
            NSDictionary *query = @{@"name": @{@"$eq": @"bill"}};
            CDTQResultSet *result = [im find:query];
            expect(result).toNot.beNil();
            expect(result.documentIds.count).to.equal(0);
        });
        
        it(@"returns no results when query is for two predicates, one without matches", ^{
            NSDictionary *query = @{@"name": @{@"$eq": @"bill"}, 
                                    @"age": @{@"$eq": @12}};
            CDTQResultSet *result = [im find:query];
            expect(result).toNot.beNil();
            expect(result.documentIds.count).to.equal(0);
        });
        
        it(@"returns no results when query is for two predicates, both without matches", ^{
            NSDictionary *query = @{@"name": @{@"$eq": @"bill"}, 
                                    @"age": @{@"$eq": @17}};
            CDTQResultSet *result = [im find:query];
            expect(result).toNot.beNil();
            expect(result.documentIds.count).to.equal(0);
        });
        
        it(@"query without index", ^{
            NSDictionary *query = @{@"pet": @{@"$eq": @"mike"}, 
                                    @"age": @{@"$eq": @12}};
            CDTQResultSet *result = [im find:query];
            expect(result).to.beNil();
        });
        
    });
    
    describe(@"when using dotted notation", ^{
        
        __block CDTDatastore *ds;
        __block CDTQIndexManager *im;
        
        beforeEach(^{
            ds = [factory datastoreNamed:@"test" error:nil];
            expect(ds).toNot.beNil();
            
            CDTMutableDocumentRevision *rev = [CDTMutableDocumentRevision revision];
            
            rev.docId = @"mike12";
            rev.body = @{ @"name": @"mike", 
                          @"age": @12, 
                          @"pet": @{@"species": @"cat", @"name": @"mike"}};
            [ds createDocumentFromRevision:rev error:nil];
            
            rev.docId = @"mike23";
            rev.body = @{ @"name": @"mike", 
                          @"age": @23, 
                          @"pet": @{@"species": @"cat", @"name": @{ @"first": @"mike" }}};
            [ds createDocumentFromRevision:rev error:nil];
            
            rev.docId = @"mike34";
            rev.body = @{ @"name": @"mike", 
                          @"age": @34, 
                          @"pet": @{@"species": @"cat", @"name": @"mike" } };
            [ds createDocumentFromRevision:rev error:nil];
            
            rev.docId = @"mike72";
            rev.body = @{ @"name": @"mike", @"age": @34, @"pet": @"cat" };
            [ds createDocumentFromRevision:rev error:nil];
            
            rev.docId = @"fred34";
            rev.body = @{ @"name": @"fred", @"age": @34, @"pet": @"cat" };
            [ds createDocumentFromRevision:rev error:nil];
            
            rev.docId = @"fred12";
            rev.body = @{ @"name": @"fred", @"age": @12 };
            [ds createDocumentFromRevision:rev error:nil];
            
            im = [CDTQIndexManager managerUsingDatastore:ds error:nil];
            expect(im).toNot.beNil();
            
            expect([im ensureIndexed:@[@"age", @"pet.name", @"pet.species"] withName:@"pet"]).toNot.beNil();
            expect([im ensureIndexed:@[@"age", @"pet.name.first"] withName:@"firstname"]).toNot.beNil();
        });
        
        it(@"query with two level dotted no results", ^{
            NSDictionary *query = @{@"pet.name": @{@"$eq": @"fred"}, 
                                    @"age": @{@"$eq": @12}};
            CDTQResultSet *result = [im find:query];
            expect(result).toNot.beNil();
            expect(result.documentIds).to.equal(@[]);
        });
        
        it(@"query with two level dotted one result", ^{
            NSDictionary *query = @{@"pet.name": @{@"$eq": @"mike"}, 
                                    @"age": @{@"$eq": @12}};
            CDTQResultSet *result = [im find:query];
            expect(result.documentIds).to.equal(@[@"mike12"]);
        });
        
        it(@"query with two level dotted multiple results", ^{
            NSDictionary *query = @{@"pet.species": @{@"$eq": @"cat"}};
            CDTQResultSet *result = [im find:query];
            expect(result.documentIds).to.equal(@[@"mike12", @"mike23", @"mike34"]);
        });
        
        it(@"query with three level dotted", ^{
            NSDictionary *query = @{@"pet.name.first": @{@"$eq": @"mike"}};
            CDTQResultSet *result = [im find:query];
            expect(result.documentIds).to.equal(@[@"mike23"]);
        });
        
    });
    
    describe(@"when using non-ascii text", ^{
        
        __block CDTDatastore *ds;
        __block CDTQIndexManager *im;
        
        beforeEach(^{
            ds = [factory datastoreNamed:@"test" error:nil];
            expect(ds).toNot.beNil();
            
            CDTMutableDocumentRevision *rev = [CDTMutableDocumentRevision revision];
            
            rev.docId = @"mike12";
            rev.body = @{ @"name": @"mike", @"age": @12, @"pet": @"cat" };
            [ds createDocumentFromRevision:rev error:nil];
            
            rev.docId = @"mike34";
            rev.body = @{ @"name": @"mike", @"age": @34, @"pet": @"dog" };
            [ds createDocumentFromRevision:rev error:nil];
            
            rev.docId = @"mike72";
            rev.body = @{ @"name": @"mike", @"age": @34, @"pet": @"cat" };
            [ds createDocumentFromRevision:rev error:nil];
            
            rev.docId = @"اسم34";
            rev.body = @{ @"name": @"اسم", @"age": @34, @"pet": @"cat" };
            [ds createDocumentFromRevision:rev error:nil];
            
            rev.docId = @"fred12";
            rev.body = @{ @"name": @"fred", @"age": @12 };
            [ds createDocumentFromRevision:rev error:nil];
            
            rev.docId = @"fredarabic";
            rev.body = @{ @"اسم": @"fred", @"age": @12 };
            [ds createDocumentFromRevision:rev error:nil];
            
            rev.docId = @"freddatatype";
            rev.body = @{ @"@datatype": @"fred", @"age": @12 };
            [ds createDocumentFromRevision:rev error:nil];
            
            im = [CDTQIndexManager managerUsingDatastore:ds error:nil];
            expect(im).toNot.beNil();
        });
        
        it(@"can query for values non-ascii", ^{
            expect([im ensureIndexed:@[@"name"] withName:@"nonascii"]).toNot.beNil();
            
            NSDictionary *query = @{@"name": @{@"$eq": @"اسم"}};
            CDTQResultSet *result = [im find:query];
            expect(result).toNot.beNil();
            expect(result.documentIds.count).to.equal(1);
        });
        
        it(@"can use fields with odd names", ^{
            expect([im ensureIndexed:@[@"اسم", @"@datatype", @"age"] withName:@"nonascii"]).toNot.beNil();
            
            NSDictionary *query = @{@"اسم": @{@"$eq": @"fred"}, 
                                    @"age": @{@"$eq": @12}};
            CDTQResultSet *result = [im find:query];
            expect(result).toNot.beNil();
            expect(result.documentIds.count).to.equal(1);
            
            query = @{@"@datatype": @{@"$eq": @"fred"}, 
                      @"age": @{@"$eq": @12}};
            result = [im find:query];
            expect(result).toNot.beNil();
            expect(result.documentIds.count).to.equal(1);
        });
    });
    
    describe(@"when selecting an index to use", ^{
        
        __block CDTDatastore *ds;
        __block CDTQIndexManager *im;
        
        beforeEach(^{
            ds = [factory datastoreNamed:@"test" error:nil];
            im = [CDTQIndexManager managerUsingDatastore:ds error:nil];
        });
        
        it(@"fails if no indexes available", ^{
            expect([CDTQQueryExecutor chooseIndexForQuery:@{@"name": @"mike"}
                                              fromIndexes:@{}]).to.beNil();
        });
        
        it(@"fails if no keys in query", ^{
            NSDictionary *indexes = @{@"named": @[@"name", @"age", @"pet"]};
            expect([CDTQQueryExecutor chooseIndexForQuery:@{} fromIndexes:indexes]).to.beNil();
        });
        
        it(@"selects an index for single field queries", ^{
            NSDictionary *indexes = @{@"named": @[@"name"]};
            NSString *idx = [CDTQQueryExecutor chooseIndexForQuery:@{@"name": @"mike"} 
                                                       fromIndexes:indexes];
            expect(idx).to.equal(@"named");
        });
        
        it(@"selects an index for multi-field queries", ^{
            NSDictionary *indexes = @{@"named": @[@"name", @"age", @"pet"]};
            NSString *idx = [CDTQQueryExecutor chooseIndexForQuery:@{@"name": @"mike", @"pet": @"cat"} 
                                                       fromIndexes:indexes];
            expect(idx).to.equal(@"named");
        });
        
        it(@"selects an index from several indexes for multi-field queries", ^{
            NSDictionary *indexes = @{@"named": @[@"name", @"age", @"pet"],
                                      @"bopped": @[@"house_number", @"pet"],
                                      @"unsuitable": @[@"name"],};
            NSString *idx = [CDTQQueryExecutor chooseIndexForQuery:@{@"name": @"mike", @"pet": @"cat"} 
                                                       fromIndexes:indexes];
            expect(idx).to.equal(@"named");
        });
        
        it(@"selects an correct index when several match", ^{
            NSDictionary *indexes = @{@"named": @[@"name", @"age", @"pet"],
                                      @"bopped": @[@"name", @"age", @"pet"],
                                      @"many_field": @[@"name", @"age", @"pet", @"car", @"van"],
                                      @"unsuitable": @[@"name"],};
            NSString *idx = [CDTQQueryExecutor chooseIndexForQuery:@{@"name": @"mike", @"pet": @"cat"} 
                                                       fromIndexes:indexes];
            expect([@[@"named", @"bopped"] containsObject:idx]).to.beTruthy();
        });
        
        it(@"fails if no suitable index is available", ^{
            NSDictionary *indexes = @{@"named": @[@"name", @"age"],
                                      @"unsuitable": @[@"name"],};
            expect([CDTQQueryExecutor chooseIndexForQuery:@{@"pet": @"cat"} 
                                              fromIndexes:indexes]).to.beNil();
        });
        
    });
    
    describe(@"when generating query WHERE clauses", ^{
        
        it(@"returns nil when no query terms", ^{
            CDTQSqlParts *parts = [CDTQQueryExecutor wherePartsForQuery:@{}];
            expect(parts).to.beNil();
        });
        
        it(@"returns correctly for a single term", ^{
            CDTQSqlParts *parts = [CDTQQueryExecutor wherePartsForQuery:@{@"name": @{@"$eq": @"mike"}}];
            expect(parts.sqlWithPlaceholders).to.equal(@"\"name\" = ?");
            expect(parts.placeholderValues).to.equal(@[@"mike"]);
        });
        
        it(@"returns correctly for many query terms", ^{
            CDTQSqlParts *parts = [CDTQQueryExecutor wherePartsForQuery:@{@"name": @{@"$eq": @"mike"},
                                                                          @"age": @{@"$eq": @12},
                                                                          @"pet": @{@"$eq": @"cat"}}];
            expect(parts.sqlWithPlaceholders).to.equal(@"\"age\" = ? AND \"name\" = ? AND \"pet\" = ?");
            expect(parts.placeholderValues).to.equal(@[@12, @"mike", @"cat"]);
        });
        
    });
    
    describe(@"when generating query SELECT clauses", ^{
        
        it(@"returns nil for no query terms", ^{
            CDTQSqlParts *parts = [CDTQQueryExecutor selectStatementForQuery:@{}
                                                                  usingIndex:@"named"];
            expect(parts).to.beNil();
        });
        
        it(@"returns nil for no index name", ^{
            CDTQSqlParts *parts = [CDTQQueryExecutor selectStatementForQuery:@{}
                                                                  usingIndex:nil];
            expect(parts).to.beNil();
        });
        
        it(@"returns correctly for single query term", ^{
            CDTQSqlParts *parts = [CDTQQueryExecutor selectStatementForQuery:@{@"name": @{@"$eq": @"mike"}}
                                                                  usingIndex:@"anIndex"];
            NSString *sql = @"SELECT docid FROM _t_cloudant_sync_query_index_anIndex "
            "WHERE \"name\" = ?;";
            expect(parts.sqlWithPlaceholders).to.equal(sql);
            expect(parts.placeholderValues).to.equal(@[@"mike"]);
        });
        
        it(@"returns correctly for many query terms", ^{
            CDTQSqlParts *parts = [CDTQQueryExecutor selectStatementForQuery:@{@"name": @{@"$eq": @"mike"},
                                                                               @"age": @{@"$eq": @12},
                                                                               @"pet": @{@"$eq": @"cat"}}
                                                                  usingIndex:@"anIndex"];
            NSString *sql = @"SELECT docid FROM _t_cloudant_sync_query_index_anIndex "
            "WHERE \"age\" = ? AND \"name\" = ? AND \"pet\" = ?;";
            expect(parts.sqlWithPlaceholders).to.equal(sql);
            expect(parts.placeholderValues).to.equal(@[@12, @"mike", @"cat"]);
        });
        
    });
    
});

SpecEnd
