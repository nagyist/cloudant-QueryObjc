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
#import <CDTQQuerySqlTranslator.h>


SpecBegin(CDTQQuerySqlTranslator)


describe(@"cdtq", ^{
    
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
    
    describe(@"when selecting an index to use", ^{
        
        __block CDTDatastore *ds;
        __block CDTQIndexManager *im;
        
        beforeEach(^{
            ds = [factory datastoreNamed:@"test" error:nil];
            im = [CDTQIndexManager managerUsingDatastore:ds error:nil];
        });
        
        it(@"fails if no indexes available", ^{
            expect([CDTQQuerySqlTranslator chooseIndexForAndClause:@[@{@"name": @"mike"}]
                                                       fromIndexes:@{}]).to.beNil();
        });
        
        it(@"fails if no keys in query", ^{
            NSDictionary *indexes = @{@"named": @[@"name", @"age", @"pet"]};
            expect([CDTQQuerySqlTranslator chooseIndexForAndClause:@[@{}]
                                                       fromIndexes:indexes]).to.beNil();
        });
        
        it(@"selects an index for single field queries", ^{
            NSDictionary *indexes = @{@"named": @{@"name": @"named", 
                                                  @"type": @"json", 
                                                  @"fields": @[@"name"]}};
            NSString *idx = [CDTQQuerySqlTranslator chooseIndexForAndClause:@[@{@"name": @"mike"}]
                                                                fromIndexes:indexes];
            expect(idx).to.equal(@"named");
        });
        
        it(@"selects an index for multi-field queries", ^{
            NSDictionary *indexes = @{@"named": @{@"name": @"named", 
                                                  @"type": @"json", 
                                                  @"fields": @[@"name", @"age", @"pet"]}};
            NSString *idx = [CDTQQuerySqlTranslator chooseIndexForAndClause:@[@{@"name": @"mike"}, 
                                                                              @{@"pet": @"cat"}]
                                                                fromIndexes:indexes];
            expect(idx).to.equal(@"named");
        });
        
        it(@"selects an index from several indexes for multi-field queries", ^{
            NSDictionary *indexes = @{@"named": @{@"name": @"named", 
                                                  @"type": @"json", 
                                                  @"fields": @[@"name", @"age", @"pet"]},
                                      @"bopped": @{@"name": @"named", 
                                                   @"type": @"json", 
                                                   @"fields": @[@"house_number", @"pet"]},
                                      @"unsuitable": @{@"name": @"named", 
                                                       @"type": @"json", 
                                                       @"fields": @[@"name"]},};
            NSString *idx = [CDTQQuerySqlTranslator chooseIndexForAndClause:@[@{@"name": @"mike"},
                                                                              @{@"pet": @"cat"}]
                                                                fromIndexes:indexes];
            expect(idx).to.equal(@"named");
        });
        
        it(@"selects an correct index when several match", ^{
            NSDictionary *indexes = @{@"named": @{@"name": @"named", 
                                                  @"type": @"json", 
                                                  @"fields": @[@"name", @"age", @"pet"]},
                                      @"bopped": @{@"name": @"named", 
                                                   @"type": @"json", 
                                                   @"fields": @[@"name", @"age", @"pet"]},
                                      @"many_field": @{@"name": @"named", 
                                                       @"type": @"json", 
                                                       @"fields": @[@"name", @"age", @"pet", @"car", @"van"]},
                                      @"unsuitable": @{@"name": @"named", 
                                                       @"type": @"json", 
                                                       @"fields": @[@"name"]},};
            NSString *idx = [CDTQQuerySqlTranslator chooseIndexForAndClause:@[@{@"name": @"mike"}, 
                                                                              @{@"pet": @"cat"}]
                                                                fromIndexes:indexes];
            expect([@[@"named", @"bopped"] containsObject:idx]).to.beTruthy();
        });
        
        it(@"fails if no suitable index is available", ^{
            NSDictionary *indexes = @{@"named": @{@"name": @"named", 
                                                  @"type": @"json", 
                                                  @"fields": @[@"name", @"age"]},
                                      @"unsuitable": @{@"name": @"named", 
                                                       @"type": @"json", 
                                                       @"fields": @[@"name"]},};
            expect([CDTQQuerySqlTranslator chooseIndexForAndClause:@[@{@"pet": @"cat"}]
                                                       fromIndexes:indexes]).to.beNil();
        });
        
    });
    
    describe(@"when generating query WHERE clauses", ^{
        
        it(@"returns nil when no query terms", ^{
            CDTQSqlParts *parts = [CDTQQuerySqlTranslator wherePartsForAndClause:@[]];
            expect(parts).to.beNil();
        });
        
        
        describe(@"when using $eq operator", ^{
            
            it(@"returns correctly for a single term", ^{
                CDTQSqlParts *parts = [CDTQQuerySqlTranslator wherePartsForAndClause:@[@{@"name": @{@"$eq": @"mike"}}]];
                expect(parts.sqlWithPlaceholders).to.equal(@"\"name\" = ?");
                expect(parts.placeholderValues).to.equal(@[@"mike"]);
            });
            
            it(@"returns correctly for many query terms", ^{
                NSArray *query = @[@{@"name": @{@"$eq": @"mike"}},
                                   @{@"age": @{@"$eq": @12}},
                                   @{@"pet": @{@"$eq": @"cat"}}];
                CDTQSqlParts *parts = [CDTQQuerySqlTranslator wherePartsForAndClause:query];
                expect(parts.sqlWithPlaceholders).to.equal(@"\"name\" = ? AND \"age\" = ? AND \"pet\" = ?");
                expect(parts.placeholderValues).to.equal(@[@"mike", @12, @"cat"]);
            });
            
        });
        
        describe(@"when using unsupported operator", ^{
            it(@"uses correct SQL operator", ^{
                CDTQSqlParts *parts = [CDTQQuerySqlTranslator wherePartsForAndClause:@[@{@"name": @{@"$blah": @"mike"}}]];
                expect(parts).to.beNil();
            });
        });
        
        describe(@"when using $gt operator", ^{
            it(@"uses correct SQL operator", ^{
                CDTQSqlParts *parts = [CDTQQuerySqlTranslator wherePartsForAndClause:@[@{@"name": @{@"$gt": @"mike"}}]];
                expect(parts.sqlWithPlaceholders).to.equal(@"\"name\" > ?");
            });
        });
        
        describe(@"when using $gte operator", ^{
            it(@"uses correct SQL operator", ^{
                CDTQSqlParts *parts = [CDTQQuerySqlTranslator wherePartsForAndClause:@[@{@"name": @{@"$gte": @"mike"}}]];
                expect(parts.sqlWithPlaceholders).to.equal(@"\"name\" >= ?");
            });
        });
        
        describe(@"when using $lt operator", ^{
            it(@"uses correct SQL operator", ^{
                CDTQSqlParts *parts = [CDTQQuerySqlTranslator wherePartsForAndClause:@[@{@"name": @{@"$lt": @"mike"}}]];
                expect(parts.sqlWithPlaceholders).to.equal(@"\"name\" < ?");
            });
        });
        
        describe(@"when using $lte operator", ^{
            it(@"uses correct SQL operator", ^{
                CDTQSqlParts *parts = [CDTQQuerySqlTranslator wherePartsForAndClause:@[@{@"name": @{@"$lte": @"mike"}}]];
                expect(parts.sqlWithPlaceholders).to.equal(@"\"name\" <= ?");
            });
        });
        
        
    });
    
    describe(@"when generating query SELECT clauses", ^{
        
        it(@"returns nil for no query terms", ^{
            CDTQSqlParts *parts = [CDTQQuerySqlTranslator selectStatementForAndClause:@[]
                                                                           usingIndex:@"named"];
            expect(parts).to.beNil();
        });
        
        it(@"returns nil for no index name", ^{
            CDTQSqlParts *parts = [CDTQQuerySqlTranslator selectStatementForAndClause:@[@{@"name": @{@"$eq": @"mike"}}]
                                                                           usingIndex:nil];
            expect(parts).to.beNil();
        });
        
        it(@"returns correctly for single query term", ^{
            CDTQSqlParts *parts = [CDTQQuerySqlTranslator selectStatementForAndClause:@[@{@"name": @{@"$eq": @"mike"}}]
                                                                           usingIndex:@"anIndex"];
            NSString *sql = @"SELECT docid FROM _t_cloudant_sync_query_index_anIndex "
            "WHERE \"name\" = ?;";
            expect(parts.sqlWithPlaceholders).to.equal(sql);
            expect(parts.placeholderValues).to.equal(@[@"mike"]);
        });
        
        it(@"returns correctly for many query terms", ^{
            NSArray *andClause = @[@{@"name": @{@"$eq": @"mike"}},
                                   @{@"age": @{@"$eq": @12}},
                                   @{@"pet": @{@"$eq": @"cat"}}];
            CDTQSqlParts *parts = [CDTQQuerySqlTranslator selectStatementForAndClause:andClause
                                                                           usingIndex:@"anIndex"];
            NSString *sql = @"SELECT docid FROM _t_cloudant_sync_query_index_anIndex "
            "WHERE \"name\" = ? AND \"age\" = ? AND \"pet\" = ?;";
            expect(parts.sqlWithPlaceholders).to.equal(sql);
            expect(parts.placeholderValues).to.equal(@[@"mike", @12, @"cat"]);
        });
        
    });
    
    describe(@"when normalising queries", ^{
        
        it(@"expands top-level implicit $and single field", ^{
            NSDictionary *actual = [CDTQQuerySqlTranslator normaliseQuery:@{@"name": @"mike"}];
            expect(actual).to.equal(@{@"$and": @[@{@"name": @"mike"}]});
        });
        
        it(@"expands top-level implicit $and multi field", ^{
            NSDictionary *actual = [CDTQQuerySqlTranslator normaliseQuery:@{@"name": @"mike",
                                                                            @"pet": @"cat",
                                                                            @"age": @12}];
            expect(actual).to.equal(@{@"$and": @[@{@"pet": @"cat"}, 
                                                 @{@"name": @"mike"}, 
                                                 @{@"age": @12}]});
        });
        
        it(@"doesn't change already normalised query", ^{
            NSDictionary *actual = [CDTQQuerySqlTranslator normaliseQuery:@{@"$and": @[@{@"name": @"mike"}, 
                                                                                       @{@"pet": @"cat"}, 
                                                                                       @{@"age": @12}]}];
            expect(actual).to.equal(@{@"$and": @[@{@"name": @"mike"}, 
                                                 @{@"pet": @"cat"}, 
                                                 @{@"age": @12}]});
        });
        
    });
    
    describe(@"when extracting and clause field names", ^{
        
        it(@"extracts a no field names", ^{
            NSArray *fields = [CDTQQuerySqlTranslator fieldsForAndClause:@[]];
            expect(fields).to.equal(@[]);
        });
        
        it(@"extracts a single field name", ^{
            NSArray *fields = [CDTQQuerySqlTranslator fieldsForAndClause:@[@{@"name": @"mike"}]];
            expect(fields).to.equal(@[@"name"]);
        });
        
        it(@"extracts a multiple field names", ^{
            NSArray *fields = [CDTQQuerySqlTranslator fieldsForAndClause:@[@{@"name": @"mike"}, 
                                                                           @{@"pet": @"cat"}, 
                                                                           @{@"age": @12}]];
            expect(fields).to.equal(@[@"name", @"pet", @"age"]);
        });
        
    });
    
    
});

SpecEnd
