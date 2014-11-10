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
@property (nonatomic, strong, readwrite) NSArray *fields;
@end

@implementation CDTQResultSetBuilder

- (CDTQResultSet *)build;
{
    return [[CDTQResultSet alloc] initWithBuilder:self];
}

@end

@implementation CDTQResultSet

- (instancetype)initWithBuilder:(CDTQResultSetBuilder *)builder
{
    self = [super init];
    if (self) {
        _originalDocumentIds = builder.docIds;
        _datastore = builder.datastore;
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

- (NSArray /* NSString */ *)documentIds
{
    // This is implemented using -enumerateObjectsUsingBlock so that when we're using
    // skip, limit or post hoc matching the documentIds array is output correctly.
    NSMutableArray *accumulator = [NSMutableArray array];
    [self enumerateObjectsUsingBlock:^(CDTDocumentRevision *rev, NSUInteger idx, BOOL *stop) {
        [accumulator addObject:rev.docId];
    }];
    return [NSArray arrayWithArray:accumulator];
}

- (void)enumerateObjectsUsingBlock:(void (^)(CDTDocumentRevision *rev, NSUInteger idx,
                                             BOOL *stop))block
{
    NSUInteger idx = 0;
    BOOL stop = NO;
    NSUInteger batchSize = 50;
    NSRange range = NSMakeRange(0, batchSize);
    while (range.location < _originalDocumentIds.count) {
        range.length = MIN(batchSize, _originalDocumentIds.count - range.location);
        NSArray *batch = [_originalDocumentIds subarrayWithRange:range];

        NSArray *docs = [_datastore getDocumentsWithIds:batch];
        if (self.fields) {
            docs =
                [CDTQResultSet projectFields:self.fields fromRevisions:docs datastore:_datastore];
        }

        for (CDTDocumentRevision *rev in docs) {
            block(rev, idx, &stop);
            if (stop) {
                break;
            }
            idx++;
        }

        range.location += range.length;
    }
}

+ (NSArray *)projectFields:(NSArray *)fields
             fromRevisions:(NSArray *)revisions
                 datastore:(CDTDatastore *)datastore
{
    NSMutableArray *projectedDocs = [NSMutableArray array];

    for (CDTDocumentRevision *rev in revisions) {
        // grab the dictionary filter fields and rebuild object
        NSDictionary *body = [rev.body dictionaryWithValuesForKeys:fields];
        CDTQProjectedDocumentRevision *rev2 =
            [[CDTQProjectedDocumentRevision alloc] initWithDocId:rev.docId
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
