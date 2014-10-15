//
//  CDTQInvalidQuerySyntax.m
//  CloudantQueryObjc
//
//  Created by Rhys Short on 14/10/2014.
//  Copyright (c) 2014 Michael Rhodes. All rights reserved.
//

#import <CloudantSync.h>
#import <CDTQIndexManager.h>
#import <CDTQIndexUpdater.h>
#import <CDTQIndexCreator.h>
#import <CDTQResultSet.h>
#import <CDTQQueryExecutor.h>



SpecBegin(CDTQQueryExecutorInvalidSyntax)


describe(@"cloudant query using invalid syntax", ^{
    
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

describe(@"When using query ", ^{
    
    __block CDTDatastore *ds;
    __block CDTQIndexManager *im;
    
    beforeEach(^{
        ds = [factory datastoreNamed:@"test" error:nil];
        expect(ds).toNot.beNil();

        im = [CDTQIndexManager managerUsingDatastore:ds error:nil];
        expect(im).toNot.beNil();

    });
    
    it(@"returns nil when arugment to $or is a string",^{
        NSDictionary * query = @{@"$or":@"I should be an array"};
        CDTQResultSet *result = [im find:query];
        expect(result).to.beNil();
    });
    
    it(@"returns nil when array passed to $or contains only a string",^{
        NSDictionary * query = @{@"$or":@[@"I should be an array"]};
        CDTQResultSet *result = [im find:query];
        expect(result).to.beNil();
    });
    
    it(@"returns nil when array passed to $or contains only one empty dict",^{
        NSDictionary * query = @{@"$or":@[@{}]};
        CDTQResultSet *result = [im find:query];
        expect(result).to.beNil();
    });
    
    it(@"returns nil when array passed to $or contains one correct dict",^{
        NSDictionary * query = @{@"$or":@[@{@"name":@"mike"}]};
        CDTQResultSet *result = [im find:query];
        expect(result).to.beNil();
    });
    
    
    it(@"returns nil when $or syntax is incorrect, using one correct dict and one empty dict",^{
        NSDictionary * query = @{@"$or":@[@{@"name":@"mike"},@{}]};
        CDTQResultSet *result = [im find:query];
        expect(result).to.beNil();
    });
    
    it(@"returns nil when comparing strings with the $lt operator",^{
        NSDictionary * query = @{@"name":@{@"$lt":@"mike"}};
        CDTQResultSet *result = [im find:query];
        expect(result).to.beNil();
        
    });
    
    it(@"returns nil when comparing strings with the $gt operator", ^{
        NSDictionary * query = @{@"name":@{@"$gt":@"mike"}};
        CDTQResultSet *result = [im find:query];
        expect(result).to.beNil();
    });
    
    it(@"returns nil when comparing an array with an empty array",^{
        NSDictionary * query = @{@"friends":@[]};
        CDTQResultSet * result = [im find:query];
        expect(result).to.beNil();
    });
    
    it(@"returns nil when arugment to $eq is a string",^{
        NSDictionary * query = @{@"$eq":@"I should be an array"};
        CDTQResultSet *result = [im find:query];
        expect(result).to.beNil();
    });
    
    it(@"returns nil when array passed to $eq contains only a string",^{
        NSDictionary * query = @{@"$eq":@[@"I should be an array"]};
        CDTQResultSet *result = [im find:query];
        expect(result).to.beNil();
    });
    
    it(@"returns nil when array passed to $eq contains only one empty dict",^{
        NSDictionary * query = @{@"$eq":@[@{}]};
        CDTQResultSet *result = [im find:query];
        expect(result).to.beNil();
    });
    
    it(@"returns nil when array passed to $eq contains one correct dict",^{
        NSDictionary * query = @{@"$eq":@[@{@"name":@"mike"}]};
        CDTQResultSet *result = [im find:query];
        expect(result).to.beNil();
    });
    
    
    it(@"returns nil when $eq syntax is incorrect, using one correct dict and one empty dict",^{
        NSDictionary * query = @{@"$eq":@[@{@"name":@"mike"},@{}]};
        CDTQResultSet *result = [im find:query];
        expect(result).to.beNil();
    });
    
    it(@"returns nil when $eq syntax is correct but contains NSData object as param",^{
        
        NSData * data  = [@"mike" dataUsingEncoding:NSUTF8StringEncoding];
        
        NSDictionary * query = @{@"$eq":@{@"name":data}};
        CDTQResultSet *result = [im find:query];
        expect(result).to.beNil();
    });
    
    it(@"returns nil when implicait $eq syntax is correct but contains NSData object as param",^{
        
        NSData * data  = [@"mike" dataUsingEncoding:NSUTF8StringEncoding];
        
        NSDictionary * query = @{@"name":data};
        CDTQResultSet *result = [im find:query];
        expect(result).to.beNil();
    });
    
    it(@"returns nil when $or syntax is incorrect, using one correct dict and one empty dict",^{
        NSData * data  = [@"mike" dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary * query = @{@"$or":@[@{@"name":@"mike"},@{@"name":data}]};
        CDTQResultSet *result = [im find:query];
        expect(result).to.beNil();
    });
    
    
});

    
});


SpecEnd

