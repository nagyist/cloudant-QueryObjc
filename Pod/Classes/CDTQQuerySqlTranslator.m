//
//  CDTQQuerySqlTranslator.m
//
//  Created by Michael Rhodes on 03/10/2014.
//  Copyright (c) 2014 Cloudant. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CDTQQuerySqlTranslator.h"

#import "CDTQQueryExecutor.h"
#import "CDTQIndexManager.h"
#import "CDTQLogging.h"

@implementation CDTQQueryNode

@end

@implementation CDTQChildrenQueryNode

- (instancetype)init
{
    self = [super init];
    if (self) {
        _children = [NSMutableArray array];
    }
    return self;
}

@end

@implementation CDTQAndQueryNode

@end

@implementation CDTQOrQueryNode

@end

@implementation CDTQSqlQueryNode

@end

@implementation CDTQQuerySqlTranslator

static NSString *const AND = @"$and";
static NSString *const OR = @"$or";
static NSString *const EQ = @"$eq";

+ (CDTQQueryNode*)translateQuery:(NSDictionary*)query toUseIndexes:(NSDictionary*)indexes
{
    query = [CDTQQuerySqlTranslator normaliseQuery:query];
    
    // At this point we will have a root compound predicate, AND or OR, and
    // the query will be reduced to a single entry:
    // @{ @"$and": @[ ... predicates (possibly compound) ... ] }
    // @{ @"$or": @[ ... predicates (possibly compound) ... ] }
    
    CDTQChildrenQueryNode *root;
    NSArray *clauses;
    
    if (query[AND]) {
        clauses = query[AND];
        root = [[CDTQAndQueryNode alloc] init];
    } else if (query[OR]) {
        clauses = query[OR];
        root = [[CDTQOrQueryNode alloc] init];
    } 

    if (![clauses isKindOfClass:[NSArray class]]) {
        LogError(@"Arugment to compound operator is not an NSArray: %@", [query description]);
        return nil;
    }

    //validate arugments to operator first
    __block BOOL error = NO;
    [clauses enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        if ([obj isKindOfClass:[NSDictionary class]]){
            NSDictionary *clause = (NSDictionary*)obj;
            if( [clause count] != 1){
                LogError(@"Operator argument clause should only have one key value pair: %@",
                         [query description]);
                *stop = YES;
                error = YES;
                return;
            
            }
        } else {
            LogError(@"Operator argument must be a dictionary %@",
                     [query description]);
            *stop = YES;
            error = YES;
            return;
        }
    }];
    
    if(error){
        return nil;
    }

    //
    // First handle the simple @"field": @{ @"$operator": @"value" } clauses. These are
    // handled differently for AND and OR parents, so we need to have the conditional
    // logic below.
    //
        
    NSMutableArray *basicClauses = [NSMutableArray array];

    [clauses enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        NSDictionary *clause = (NSDictionary*)obj;
        NSString *field = clause.allKeys[0];
        if (![field hasPrefix:@"$"]) {
            [basicClauses addObject:clauses[idx]];
        }
    }];
    

    
    if (query[AND]) {
        
        // For an AND query, we require a single compound index and we generate a
        // single SQL statement to use that index to satisfy the clauses.
        
        NSString *chosenIndex = [CDTQQuerySqlTranslator chooseIndexForAndClause:basicClauses
                                                                    fromIndexes:indexes];
        if (!chosenIndex) {
            LogError(@"No single index contains all of %@; please add an index on these fields.", 
                     basicClauses);
            return nil;
        }
        
        // Execute SQL on that index with appropriate values
        CDTQSqlParts *select = [CDTQQuerySqlTranslator selectStatementForAndClause:basicClauses
                                                                        usingIndex:chosenIndex];
        
        if (!select) {
            LogError(@"Error generating SELECT clause for %@", basicClauses);
            return nil;
        }
        
        CDTQSqlQueryNode *sql = [[CDTQSqlQueryNode alloc] init];
        sql.sql = select;
        
        [root.children addObject:sql];
        
    } else if (query[OR]) {
        
        // OR nodes require a query for each clause.
        //
        // We want to allow OR clauses to use separate indexes, unlike for AND, to allow
        // users to query over multiple indexes during a single query. This prevents users
        // having to create a single huge index just because one query in their application
        // requires it, slowing execution of all the other queries down.
        //
        // We could optimise for OR parts where we have an appropriate compound index,
        // but we don't for now.
        
        for (NSDictionary *clause in basicClauses) {
            
            NSArray *wrappedClause = @[clause];
            
            NSString *chosenIndex = [CDTQQuerySqlTranslator chooseIndexForAndClause:wrappedClause
                                                                        fromIndexes:indexes];
            if (!chosenIndex) {
                LogError(@"No single index contains all of %@; please add an index on these fields.", 
                         basicClauses);
                return nil;
            }
            
            // Execute SQL on that index with appropriate values
            CDTQSqlParts *select = [CDTQQuerySqlTranslator selectStatementForAndClause:wrappedClause
                                                                            usingIndex:chosenIndex];
            
            if (!select) {
                LogError(@"Error generating SELECT clause for %@", basicClauses);
                return nil;
            }
            
            CDTQSqlQueryNode *sql = [[CDTQSqlQueryNode alloc] init];
            sql.sql = select;
            
            [root.children addObject:sql];
            
        }
    }
    
    //
    // AND and OR subclauses are handled identically whatever the parent is.
    // We go through the query twice to order the OR clauses before the AND
    // clauses, for predictability.
    //
    
    // Add subclauses that are OR
    [clauses enumerateObjectsUsingBlock:^void(id obj, NSUInteger idx, BOOL *stop) {
        NSDictionary *clause = (NSDictionary*)obj;
        NSString *field = clause.allKeys[0];
        if ([field hasPrefix:@"$or"]) {
            CDTQQueryNode *orNode = [CDTQQuerySqlTranslator translateQuery:clauses[idx]
                                                              toUseIndexes:indexes];
            [root.children addObject:orNode];
        }
    }];
    
    // Add subclauses that are AND
    [clauses enumerateObjectsUsingBlock:^void(id obj, NSUInteger idx, BOOL *stop) {
        NSDictionary *clause = (NSDictionary*)obj;
        NSString *field = clause.allKeys[0];
        if ([field hasPrefix:@"$and"]) {
            CDTQQueryNode *andNode = [CDTQQuerySqlTranslator translateQuery:clauses[idx]
                                                              toUseIndexes:indexes];
            [root.children addObject:andNode];
        }
    }];
    
    return root;
}

#pragma mark Pre-process query

+ (NSDictionary*)normaliseQuery:(NSDictionary*)query
{
    // First expand the query to include a leading compound predicate
    // if there isn't one already.
    query = [CDTQQuerySqlTranslator addImplicitAnd:query];
    
    // At this point we will have a single entry dict, key AND or OR,
    // forming the compound predicate.
    // Next make sure all the predicates have an operator -- the EQ
    // operator is implicit and we need to add it if there isn't one.
    // Take 
    //     @[ @{"field1": @"mike"}, ... ] 
    // and make
    //     @[ @{"field1": @{ @"$eq": @"mike"} }, ... } ]
    NSString *compoundOperator = [query allKeys][0];
    NSArray *predicates = query[compoundOperator];
    if ([predicates isKindOfClass:[NSArray class]]) {
        predicates = [CDTQQuerySqlTranslator addImplicitEq:predicates];
    }
    
    return @{compoundOperator: predicates};
}

+ (NSDictionary*)addImplicitAnd:(NSDictionary*)query
{
    // query is:
    //  either @{ @"field1": @"value1", ... } -- we need to add $and
    //  or     @{ @"$and": @[ ... ] } -- we don't
    //  or     @{ @"$or": @[ ... ] } -- we don't
    
    if (query.count == 1 && (query[AND] || query[OR])) {
        return query;
    } else {
        
        // Take 
        //     @{"field1": @"mike", ...} 
        //     @{"field1": @[ @"mike", @"bob" ], ...} 
        // and make
        //     @[ @{"field1": @"mike"}, ... ]
        //     @[ @{"field1": @[ @"mike", @"bob" ]}, ... ]
        
        NSMutableArray *andClause = [NSMutableArray array];
        for (NSString *k in query) {
            NSObject *predicate = query[k];
            [andClause addObject:@{k: predicate}];
        }
        return @{AND: [NSArray arrayWithArray:andClause]};
        
    }
    
}

+ (NSArray*)addImplicitEq:(NSArray*)andClause
{
    NSMutableArray *accumulator = [NSMutableArray array];
    
    for (NSDictionary *fieldClause in andClause) { 
        
        // fieldClause is:
        //  either @{ @"field1": @"mike"} -- we need to add the $eq operator
        //  or     @{ @"field1": @{ @"$operator": @"value" } -- we don't
        //  or     @{ @"$and": @[ ... ] } -- we don't        
        //  or     @{ @"$or": @[ ... ] } -- we don't
        NSObject *predicate = nil;
        NSString *fieldName = nil;
        //if this isn't a dictionary, we don't know what to do so pass it back
        if ([fieldClause isKindOfClass:[NSDictionary class]] && [fieldClause count] != 0){
            fieldName = fieldClause.allKeys[0];
            predicate = fieldClause[fieldName];
        } else {
            [accumulator addObject:fieldClause];
            continue;
        }
        
        // If the clause isn't a special clause (the field name starts with
        // $, e.g., $and), we need to check whether the clause already
        // has an operator. If not, we need to add the implicit $eq.
        if (![fieldName hasPrefix:@"$"]) {
            if (![predicate isKindOfClass:[NSDictionary class]]) {
                predicate = @{EQ: predicate};
            }
        }
        
        [accumulator addObject:@{fieldName: predicate}]; //can't put nil in this
    }
    
    return [NSArray arrayWithArray:accumulator];
}

#pragma mark Process single AND clause with no sub-clauses

+ (NSArray*)fieldsForAndClause:(NSArray*)clause 
{
    NSMutableArray *fieldNames = [NSMutableArray array];
    for (NSDictionary* term in clause) {
        if (term.count == 1) {
            [fieldNames addObject:term.allKeys[0]];
        }
    }
    return [NSArray arrayWithArray:fieldNames];
}

+ (NSString*)chooseIndexForAndClause:(NSArray*)clause fromIndexes:(NSDictionary*)indexes
{
    NSSet *neededFields = [NSSet setWithArray:[self fieldsForAndClause:clause]];
    
    if (neededFields.count == 0) {
        LogError(@"Invalid clauses in $and clause %@", clause);
        return nil;  // no point in querying empty set of fields
    }
    
    NSString *chosenIndex = nil;
    for (NSString *indexName in indexes) {
        NSSet *providedFields = [NSSet setWithArray:indexes[indexName][@"fields"]];
        if ([neededFields isSubsetOfSet:providedFields]) {
            chosenIndex = indexName;
            break;
        }
    }
    
    return chosenIndex;
}

+ (CDTQSqlParts*)wherePartsForAndClause:(NSArray*)clause
{
    if (clause.count == 0) {
        return nil;  // no point in querying empty set of fields
    }
    
    // @[@{@"fieldName": @"mike"}, ...]
    
    NSMutableArray *sqlClauses = [NSMutableArray array];
    NSMutableArray *sqlParameters = [NSMutableArray array];
    NSDictionary *operatorMap = @{@"$eq": @"=",
                                  @"$gt": @">",
                                  @"$gte": @">=",
                                  @"$lt": @"<",
                                  @"$lte": @"<=",
                                  @"$ne": @"!="
                                  };
    
    // We apply these if the clause is negated, along with the NULL clause
    NSDictionary *notOperatorMap = @{@"$eq": @"!=",
                                     @"$gt": @"<=",
                                     @"$gte": @"<",
                                     @"$lt": @">=",
                                     @"$lte": @">",
                                     @"$ne": @"="
                                     };
    for (NSDictionary *component in clause) {
        if (component.count != 1) {
            LogError(@"Expected single predicate per clause dictionary, got %@", component);
            return nil;
        }
        
        NSString *fieldName = component.allKeys[0];
        NSDictionary *predicate = component[fieldName];
        
        if (predicate.count != 1) {
            LogError(@"Expected single operator per predicate dictionary, got %@", component);
            return nil;
        }
        
        NSString *operator = predicate.allKeys[0];
        
        // $not specifies the opposite operator OR NULL documents be returned
        if ([operator isEqualToString:@"$not"]) {
            NSDictionary *negatedPredicate = predicate[@"$not"];
            
            if (negatedPredicate.count != 1) {
                LogError(@"Expected single operator per predicate dictionary, got %@", component);
                return nil;
            }
            
            NSString *operator = negatedPredicate.allKeys[0];
            NSString *sqlOperator = notOperatorMap[operator];
            
            if (!sqlOperator) {
                LogError(@"Unsupported comparison operator %@", operator);
                return nil;
            }
            
            NSString *sqlClause = [NSString stringWithFormat:@"(\"%@\" %@ ? OR \"%@\" IS NULL)", 
                                   fieldName, sqlOperator, fieldName];
            [sqlClauses addObject:sqlClause];
            NSObject * predicateValue = [negatedPredicate objectForKey:operator];
            
            if([self validatePredicateValue:predicateValue]){
                [sqlParameters addObject:predicateValue];
            } else {
                return nil;
            }
        } else if ([operator isEqualToString:@"$exists"]){
            
            if([predicate[operator] isKindOfClass:[NSNumber class]]){
                
                if( [predicate[operator] boolValue]){
                    //so this field needs to exist
                    NSString *sqlClause = [NSString stringWithFormat:@"(\"%@\" IS NOT NULL)",
                                           fieldName];
                    [sqlClauses addObject:sqlClause];
                    [sqlParameters addObject:[predicate objectForKey:operator]];
                } else {
                    //must not exist
                    NSString *sqlClause = [NSString stringWithFormat:@"(\"%@\" IS NULL)",
                                           fieldName];
                    [sqlClauses addObject:sqlClause];
                    [sqlParameters addObject:[predicate objectForKey:operator]];
                }
                
            } else {
                LogError(@"$exists operator expects YES or NO. Query: %@",clause);
                return nil;
            }
        } else {
            NSString *sqlOperator = operatorMap[operator];
            
            if (!sqlOperator) {
                LogError(@"Unsupported comparison operator %@", operator);
                return nil;
            }
            
            NSString *sqlClause = [NSString stringWithFormat:@"\"%@\" %@ ?", 
                                   fieldName, sqlOperator];
            [sqlClauses addObject:sqlClause];
            NSObject * predicateValue = [predicate objectForKey:operator];
            if([self validatePredicateValue:predicateValue]){
                            [sqlParameters addObject: predicateValue];
            } else {
                return nil;
            }

        }
        

    }
    
    return [CDTQSqlParts partsForSql:[sqlClauses componentsJoinedByString:@" AND "]
                          parameters:sqlParameters];
    
}

+ (BOOL) validatePredicateValue:(NSObject *)predicateValue
{
    return (([predicateValue isKindOfClass:[NSString class]] ||
              [predicateValue isKindOfClass:[NSNumber class]])
            );
}

+ (CDTQSqlParts*)selectStatementForAndClause:(NSArray*)clause usingIndex:(NSString*)indexName
{
    if (clause.count == 0) {
        return nil;  // no query here
    }
    
    if (!indexName) {
        return nil;
    }
    
    CDTQSqlParts *where = [CDTQQuerySqlTranslator wherePartsForAndClause:clause];
    
    if (!where) {
        return nil;
    }
    
    NSString *tableName = [CDTQIndexManager tableNameForIndex:indexName];
    
    NSString *sql = @"SELECT _id FROM %@ WHERE %@;";
    sql = [NSString stringWithFormat:sql, tableName, where.sqlWithPlaceholders];
    
    CDTQSqlParts *parts = [CDTQSqlParts partsForSql:sql
                                         parameters:where.placeholderValues];
    return parts;
}

@end
