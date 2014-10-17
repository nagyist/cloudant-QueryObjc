//
//  CDTQFilterFieldsTest.m
//  CloudantQueryObjc
//
//  Created by Rhys Short on 16/10/2014.
//  Copyright (c) 2014 Michael Rhodes. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Specta.h"
#import "Expecta.h"
#import <CloudantSync.h>
#import <CDTQIndexManager.h>
#import <CDTQIndexUpdater.h>
#import <CDTQIndexCreator.h>
#import <CDTQResultSet.h>
#import <CDTQQueryExecutor.h>


SpecBegin(CDTQFilterFieldsTest)


describe(@"When filtering fields on find ", ^{
    
    __block NSString *factoryPath;
    __block CDTDatastoreManager *factory;
    __block CDTDatastore *ds;
    __block CDTQIndexManager *im;
    
    beforeAll(^{
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
    
    it(@"returns only field specified in fields param in the document body", ^{
        NSDictionary *query = @{@"name":@"mike"};
        CDTQResultSet *result = [im find:query skip:0 limit:NSUIntegerMax fields:@[@"name"]];
        expect(result).toNot.beNil();
        
        for (CDTDocumentRevision * revision in result) {
            expect([revision.body count]).to.equal(1);
            expect([revision.body objectForKey:@"name"]).to.equal(@"mike");
        }
    });
    
    it(@"returns all fields when fields array is empty",^{
        NSDictionary *query = @{@"name":@"mike"};
        CDTQResultSet *result = [im find:query skip:0 limit:NSUIntegerMax fields:@[]];
        expect(result).toNot.beNil();
        
        for (CDTDocumentRevision * revision in result) {
            expect([revision.body count]).to.equal(3);
            expect([revision.body objectForKey:@"name"]).toNot.beNil();
            expect([revision.body objectForKey:@"pet"]).toNot.beNil();
            expect([revision.body objectForKey:@"age"]).toNot.beNil();
        }
    });
    
    it(@"returns all fields when fields array is nil",^{
        NSDictionary *query = @{@"name":@"mike"};
        CDTQResultSet *result = [im find:query skip:0 limit:NSUIntegerMax fields:@[]];
        expect(result).toNot.beNil();
        
        for (CDTDocumentRevision * revision in result) {
            expect([revision.body count]).to.equal(3);
            expect([revision.body objectForKey:@"name"]).toNot.beNil();
            expect([revision.body objectForKey:@"pet"]).toNot.beNil();
            expect([revision.body objectForKey:@"age"]).toNot.beNil();
        }
    });
    
    it(@"returns nil when fields array contains a type other than NSString",^{
        NSDictionary *query = @{@"name":@"mike"};
        CDTQResultSet *result = [im find:query skip:0 limit:NSUIntegerMax fields:@[@{}]];
        expect(result).to.beNil();
    });
    
    it(@"returns nil when using dotted notation", ^{
        NSDictionary *query = @{@"name":@"mike"};
        CDTQResultSet *result = [im find:query skip:0 limit:NSUIntegerMax fields:@[@"name.blah"]];
        expect(result).to.beNil();
    });
    
    it(@"returns only pet and name fields in a document revision, when they are specfied in fields",^{
        NSDictionary *query = @{@"name":@"mike"};
        CDTQResultSet *result = [im find:query skip:0 limit:NSUIntegerMax fields:@[@"name",@"pet"]];
        expect(result).toNot.beNil();
        
        for (CDTDocumentRevision * revision in result) {
            expect([revision.body count]).to.equal(2);
            expect([revision.body objectForKey:@"name"]).toNot.beNil();
            expect([revision.body objectForKey:@"pet"]).toNot.beNil();
        }
    });
    
    
    
});



SpecEnd