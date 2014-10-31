//
//  CloudantQueryObjcTests.m
//  CloudantQueryObjcTests
//
//  Created by Michael Rhodes on 31/10/2014.
//  Copyright (c) 2014 Cloudant. All rights reserved.
//

#import <CloudantSync.h>
#import <CDTQIndexManager.h>
#import <CDTQIndexUpdater.h>
#import <CDTQIndexCreator.h>
#import <CDTQResultSet.h>
#import <CDTQQueryExecutor.h>
#import <CDTQUnindexedMatcher.h>


SpecBegin(CDTQUnindexedMatcher)


describe(@"matcherWithSelector", ^{
    
    it(@"returns initialised object", ^{
        CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:@{@"n": @"m"}];
        expect(matcher).toNot.beNil();
    });
    
});

describe(@"matches", ^{
    
    __block CDTDocumentRevision *rev;
    
    beforeAll(^{
        NSDictionary *body = @{@"name": @"mike",
                               @"age": @31,
                               @"pets": @[ @"white_cat", @"black_cat" ],
                               @"address": @{ @"number": @"1", @"road": @"infinite loop" } };
        rev = [[CDTDocumentRevision alloc] initWithDocId:@"dsfsdfdfs"
                                              revisionId:@"qweqeqwewqe"
                                                    body:body
                                             attachments:nil];
    });
    
    context(@"single", ^{
        
        context(@"eq", ^{
            
            it(@"matches", ^{
                NSDictionary *selector = @{@"name": @{ @"$eq": @"mike"} };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beTruthy();
            });
            
            it(@"doesn't match", ^{
                NSDictionary *selector = @{@"name": @{ @"$eq": @"fred"} };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beFalsy();
            });
            
            it(@"doesn't match bad field", ^{
                NSDictionary *selector = @{@"species": @{ @"$eq": @"fred"} };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beFalsy();
            });
            
        });
        
        context(@"implied eq", ^{
            
            it(@"matches", ^{
                NSDictionary *selector = @{@"name": @"mike" };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beTruthy();
            });
            
            it(@"doesn't match", ^{
                NSDictionary *selector = @{@"name": @"fred" };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beFalsy();
            });
            
            it(@"doesn't match bad field", ^{
                NSDictionary *selector = @{@"species": @"fred" };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beFalsy();
            });
            
        });
        
        context(@"ne", ^{
            
            it(@"matches", ^{
                NSDictionary *selector = @{@"name": @{ @"$ne": @"fred"} };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beTruthy();
            });
            
            it(@"doesn't match", ^{
                NSDictionary *selector = @{@"name": @{ @"$ne": @"mike"} };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beFalsy();
            });
            
            it(@"matches bad field", ^{
                NSDictionary *selector = @{@"species": @{ @"$ne": @"fred"} };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beTruthy();
            });
            
        });
        
        context(@"gt", ^{
            
            it(@"matches string", ^{
                NSDictionary *selector = @{@"name": @{ @"$gt": @"andy"} };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beTruthy();
            });
            
            it(@"matches int", ^{
                NSDictionary *selector = @{@"age": @{ @"$gt": @12} };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beTruthy();
            });
            
            it(@"doesn't match string", ^{
                NSDictionary *selector = @{@"name": @{ @"$gt": @"robert"} };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beFalsy();
            });
            
            it(@"doesn't match int", ^{
                NSDictionary *selector = @{@"age": @{ @"$gt": @45} };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beFalsy();
            });
            
            it(@"doesn't match bad field", ^{
                NSDictionary *selector = @{@"species": @{ @"$gt": @"fred"} };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beFalsy();
            });
            
        });
        
        context(@"gte", ^{
            
            it(@"matches string", ^{
                NSDictionary *selector = @{@"name": @{ @"$gte": @"andy"} };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beTruthy();
            });
            
            it(@"matches equal string", ^{
                NSDictionary *selector = @{@"name": @{ @"$gte": @"mike"} };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beTruthy();
            });
            
            it(@"matches int", ^{
                NSDictionary *selector = @{@"age": @{ @"$gte": @12} };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beTruthy();
            });
            
            it(@"matches equal int", ^{
                NSDictionary *selector = @{@"age": @{ @"$gte": @31} };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beTruthy();
            });
            
            it(@"doesn't match string", ^{
                NSDictionary *selector = @{@"name": @{ @"$gte": @"robert"} };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beFalsy();
            });
            
            it(@"doesn't match int", ^{
                NSDictionary *selector = @{@"age": @{ @"$gte": @45} };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beFalsy();
            });
            
            it(@"doesn't match bad field", ^{
                NSDictionary *selector = @{@"species": @{ @"$gte": @"fred"} };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beFalsy();
            });
            
        });
        
        context(@"lt", ^{
            
            it(@"matches string", ^{
                NSDictionary *selector = @{@"name": @{ @"$lt": @"robert"} };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beTruthy();
            });
            
            it(@"matches int", ^{
                NSDictionary *selector = @{@"age": @{ @"$lt": @45} };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beTruthy();
            });
            
            it(@"doesn't match string", ^{
                NSDictionary *selector = @{@"name": @{ @"$lt": @"andy"} };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beFalsy();
            });
            
            it(@"doesn't match int", ^{
                NSDictionary *selector = @{@"age": @{ @"$lt": @12} };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beFalsy();
            });
            
            it(@"doesn't match bad field", ^{
                NSDictionary *selector = @{@"species": @{ @"$lt": @"fred"} };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beFalsy();
            });
            
        });
        context(@"lte", ^{
            
            it(@"matches string", ^{
                NSDictionary *selector = @{@"name": @{ @"$lte": @"robert"} };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beTruthy();
            });
            
            it(@"matches equal string", ^{
                NSDictionary *selector = @{@"name": @{ @"$lte": @"mike"} };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beTruthy();
            });
            
            it(@"matches int", ^{
                NSDictionary *selector = @{@"age": @{ @"$lte": @45} };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beTruthy();
            });
            
            it(@"matches equal int", ^{
                NSDictionary *selector = @{@"age": @{ @"$lte": @31} };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beTruthy();
            });
            
            it(@"doesn't match string", ^{
                NSDictionary *selector = @{@"name": @{ @"$lte": @"andy"} };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beFalsy();
            });
            
            it(@"doesn't match int", ^{
                NSDictionary *selector = @{@"age": @{ @"$lte": @12} };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beFalsy();
            });
            
            it(@"doesn't match bad field", ^{
                NSDictionary *selector = @{@"species": @{ @"$lte": @"fred"} };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beFalsy();
            });
            
        });
        
        context(@"exists", ^{
            
            it(@"matches existing", ^{
                NSDictionary *selector = @{@"name": @{ @"$exists": @YES} };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beTruthy();
            });
            
            it(@"doesn't match existing", ^{
                NSDictionary *selector = @{@"name": @{ @"$exists": @NO} };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beFalsy();
            });
            
            it(@"matches missing", ^{
                NSDictionary *selector = @{@"species": @{ @"$exists": @NO} };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beTruthy();
            });
            
            it(@"doesn't match missing", ^{
                NSDictionary *selector = @{@"species": @{ @"$exists": @YES} };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beFalsy();
            });
            
        });
        
    });
    
    context(@"compound", ^{
        
        context(@"and", ^{
            
            it(@"matches all", ^{
                NSDictionary *selector = @{ @"$and": @[ @{@"name": @{ @"$eq": @"mike"} }, 
                                                       @{ @"age": @{ @"$eq": @31} } 
                                                       ]};
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beTruthy();
            });
            
            it(@"doesn't match some", ^{
                NSDictionary *selector = @{ @"$and": @[ @{@"name": @{ @"$eq": @"mike"} }, 
                                                       @{ @"age": @{ @"$eq": @12} } 
                                                       ]};
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beFalsy();
            });
            
            it(@"doesn't match any", ^{
                NSDictionary *selector = @{ @"$and": @[ @{@"name": @{ @"$eq": @"fred"} }, 
                                                       @{ @"age": @{ @"$eq": @12} } 
                                                       ]};
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beFalsy();
            });
            
        });
        
        context(@"implicit and", ^{
                        
            it(@"matches", ^{
                NSDictionary *selector = @{ @"name": @{ @"$eq": @"mike"}, @"age": @{ @"$eq": @31} };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beTruthy();
            });
            
            it(@"doesn't match", ^{
                NSDictionary *selector = @{ @"name": @{ @"$eq": @"mike"}, @"age": @{ @"$eq": @12} };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beFalsy();
            });
            
        });
        
        context(@"or", ^{
            
            it(@"matches all okay", ^{
                NSDictionary *selector = @{ @"$or": @[ @{@"name": @{ @"$eq": @"mike"} }, 
                                                       @{ @"age": @{ @"$eq": @31} } 
                                                       ]};
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beTruthy();
            });
            
            it(@"matches one okay", ^{
                NSDictionary *selector = @{ @"$or": @[ @{@"name": @{ @"$eq": @"mike"} }, 
                                                       @{ @"age": @{ @"$eq": @12} } 
                                                       ]};
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beTruthy();
            });
            
            it(@"doesn't match", ^{
                NSDictionary *selector = @{ @"$or": @[ @{@"name": @{ @"$eq": @"fred"} }, 
                                                       @{ @"age": @{ @"$eq": @12} } 
                                                       ]};
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beFalsy();
            });
            
        });
    });
    
    context(@"not", ^{
       
        // We can be fairly simple here as we know that the internal is that not just negates.
        
        context(@"eq", ^{
            
            it(@"doesn't match", ^{
                NSDictionary *selector = @{@"name": @{ @"$not": @{ @"$eq": @"mike"} } };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beFalsy();
            });
            
            it(@"matches", ^{
                NSDictionary *selector = @{@"name": @{ @"$not": @{ @"$eq": @"fred"} } };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beTruthy();
            });
            
            it(@"matches bad field", ^{
                NSDictionary *selector = @{@"species": @{ @"$not": @{ @"$eq": @"fred"} } };
                CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
                expect([matcher matches:rev]).to.beTruthy();
            });
            
        });
        
    });
    
    context(@"array fields", ^{
        
        it(@"matches", ^{
            NSDictionary *selector = @{ @"pets": @"white_cat" };
            CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
            expect([matcher matches:rev]).to.beTruthy();
        });
        
        it(@"matches good item with not", ^{
            NSDictionary *selector = @{ @"pets": @{ @"$not": @{ @"$eq": @"white_cat" } } };
            CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
            expect([matcher matches:rev]).to.beTruthy();
        });

        it(@"doesn't match bad item", ^{
            NSDictionary *selector = @{ @"pets": @"tabby_cat" };
            CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
            expect([matcher matches:rev]).to.beFalsy();
        });
        
        it(@"matches bad item with not", ^{
            NSDictionary *selector = @{ @"pets": @{ @"$not": @{ @"$eq": @"tabby_cat" } } };
            CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
            expect([matcher matches:rev]).to.beTruthy();
        });
        
    });
    
    context(@"dotted fields", ^{
        
        it(@"matches", ^{
            NSDictionary *selector = @{ @"address.number": @"1" };
            CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
            expect([matcher matches:rev]).to.beTruthy();
        });
        
        it(@"doesn't match", ^{
            NSDictionary *selector = @{ @"address.number": @"2" };
            CDTQUnindexedMatcher *matcher = [CDTQUnindexedMatcher matcherWithSelector:selector];
            expect([matcher matches:rev]).to.beFalsy();
        });
        
    });
    
});

SpecEnd
