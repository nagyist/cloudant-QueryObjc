//
//  CDTQResultSet.m
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

#import "CDTQResultSet.h"
#import "CDTQLogging.h"
#import "CDTQProjectedDocumentRevision.h"

#import <CloudantSync.h>

@interface CDTQResultSet ()
@property (nonatomic,strong,readwrite) NSArray *fields;
@end

@implementation CDTQResultSetBuilder

- (CDTQResultSet*)build;
{
    return [[CDTQResultSet alloc] initWithBuilder:self];
}

@end

@implementation CDTQResultSet

-(instancetype)initWithBuilder:(CDTQResultSetBuilder*)builder
{
    self = [super init];
    if (self) {
        _documentIds = builder.docIds;
        _datastore   = builder.datastore;
        _fields = builder.fields;
    }
    return self;
}

+ (instancetype)resultSetWithBlock:(CDTQResultSetBuilderBlock)block 
{
    NSParameterAssert(block);
    
    CDTQResultSetBuilder *builder = [[CDTQResultSetBuilder alloc] init];
    block(builder);
    return [builder build];
}

-(NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                 objects:(id __unsafe_unretained [])buffer
                                   count:(NSUInteger)len
{
    if(state->state == 0) {
        state->state = 1;
        // this is our index into docids list
        state->extra[0] = 0;
        // number of mutations, although we ignore this
        state->mutationsPtr = &state->extra[1];
    }
    // get our current index for this batch
    unsigned long *index = &state->extra[0];
    
    NSRange range;
    range.location = (unsigned int)*index;
    range.length   = MIN((len), ([_documentIds count]-range.location));
    
    // get documents for this batch of documentids
    NSArray *batchIds = [_documentIds subarrayWithRange:range];
    __unsafe_unretained NSArray *docs = [_datastore getDocumentsWithIds:batchIds];
    
    if(self.fields){
        docs = [CDTQResultSet projectFields:self.fields fromRevisions:docs datastore:_datastore];
    }
    
    int i;
    for (i=0; i < range.length; i++){
        buffer[i] = docs[i];
    }
    // update index ready for next time round
    (*index) += i;
    
    state->itemsPtr = buffer;
    return i;
}

+ (NSArray *)projectFields:(NSArray*)fields 
             fromRevisions:(NSArray*)revisions
                 datastore:(CDTDatastore*)datastore
{

    NSMutableArray * projectedDocs = [NSMutableArray array];
    
    for(CDTDocumentRevision * rev in revisions){
        //grab the dictionary filter fields and rebuild object
        NSDictionary * body = [rev.body dictionaryWithValuesForKeys:fields];
        CDTQProjectedDocumentRevision *rev2 = [[CDTQProjectedDocumentRevision alloc]
                                               initWithDocId:rev.docId
                                               revisionId:rev.revId
                                               body:body
                                               deleted:rev.deleted
                                               attachments:rev.attachments
                                               sequence:rev.sequence
                                               datastore:datastore];
        [projectedDocs addObject:rev2];
    }
    return projectedDocs;

}

@end
