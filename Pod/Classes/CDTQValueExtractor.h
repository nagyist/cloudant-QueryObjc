//
//  CDTQValueExtractor.h
//  Pods
//
//  Created by Michael Rhodes on 01/10/2014.
//
//

#import <Foundation/Foundation.h>

/**
 Extracts values from dictionaries using a field name.
 */
@interface CDTQValueExtractor : NSObject

+ (NSObject*)extractValueForFieldName:(NSString*)fieldName
                       fromDictionary:(NSDictionary*)body;

@end
