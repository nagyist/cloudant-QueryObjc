//
//  CDTQValueExtractor.m
//
//  Created by Michael Rhodes on 01/10/2014.
//  Copyright (c) 2014 Cloudant. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CDTQValueExtractor.h"

@implementation CDTQValueExtractor

+ (NSObject*)extractValueForFieldName:(NSString*)fieldName
                       fromDictionary:(NSDictionary*)body
{
    // The algorithm here is to split the fields into a "path" and a "lastSegment".
    // The path leads us to the final sub-document. We know that if we have either
    // nil or a non-dictionary object while traversing path that the body doesn't
    // have the right fields for this field selector -- it allows us to make sure
    // that each level of the `path` results in a document rather than a value,
    // because if it's a value, we can't continue the selection process.
    
    NSArray *fields = [fieldName componentsSeparatedByString:@"."];
    
    NSRange pathLen;
    pathLen.location = 0;
    pathLen.length = fields.count - 1;
    NSArray *path = [fields subarrayWithRange:pathLen];
    NSString *lastSegment = [fields lastObject];
    
    NSDictionary *currentLevel = body;
    for (NSString *field in path) {
        currentLevel = currentLevel[field];
        if (currentLevel == nil || ![currentLevel isKindOfClass:[NSDictionary class]]) {
            return nil;  // we ran out of stuff before we reached the full path length
        }
    }
    
    return currentLevel[lastSegment];
}

@end
