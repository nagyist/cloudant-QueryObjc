//
//  CDTQQueryValidator.m
//  Pods
//
//  Created by Rhys Short on 06/11/2014.
//
//

#import "CDTQQueryValidator.h"
#import "CDTQLogging.h"

@implementation CDTQQueryValidator

static NSString *const AND = @"$and";
static NSString *const OR = @"$or";
static NSString *const EQ = @"$eq";
static NSString *const NOT = @"$not";
static NSString *const NE = @"$ne";
static NSString *const IN = @"$in";

// notOperators dictionary is used for operator shorthand processing.
// Presently only $ne is supported.  More to come soon...
+ (NSDictionary *)getNotOperators
{
    static NSDictionary *notOperators = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        notOperators = @{ NE : EQ };
    });
    return notOperators;
}

+ (NSDictionary *)normaliseAndValidateQuery:(NSDictionary *)query
{
    bool isWildCard = [query count] == 0;

    // First expand the query to include a leading compound predicate
    // if there isn't one already.
    query = [CDTQQueryValidator addImplicitAnd:query];

    // At this point we will have a single entry dict, key AND or OR,
    // forming the compound predicate.
    // Next make sure all the predicates have an operator -- the EQ
    // operator is implicit and we need to add it if there isn't one.
    // Take
    //     @[ @{"field1": @"mike"}, ... ]
    // and make
    //     @[ @{"field1": @{ @"$eq": @"mike"} }, ... ]
    //
    // Then if possible, simplify and clarify the query.  In the
    // event that extraneous $not operators and/or shorthand operators like
    // $ne have been used then these operators must be dealt with appropriately.
    // Take
    //     [ { "field1": { "$not" : { $"not" : { "$ne": "mike"} } } }, ... ]
    // and make
    //     [ { "field1": { "$not" : { "$eq": "mike"} } }, ... ]
    NSString *compoundOperator = [query allKeys][0];
    NSArray *predicates = query[compoundOperator];
    if ([predicates isKindOfClass:[NSArray class]]) {
        predicates = [CDTQQueryValidator addImplicitEq:predicates];
        
        predicates = [CDTQQueryValidator compressMultipleNotOperators:predicates];
    }

    NSDictionary *selector = @{compoundOperator : predicates};
    if (isWildCard) {
        return selector;
    } else if ([CDTQQueryValidator validateSelector:selector]) {
        return selector;
    }

    return nil;
}

#pragma mark Normalization methods
+ (NSDictionary *)addImplicitAnd:(NSDictionary *)query
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
            [andClause addObject:@{k : predicate}];
        }
        return @{AND : [NSArray arrayWithArray:andClause]};
    }
}

+ (NSArray *)addImplicitEq:(NSArray *)andClause
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
        // if this isn't a dictionary, we don't know what to do so add the clause
        // to the accumulator to be dealt with later as part of the final selector
        // validation.
        if ([fieldClause isKindOfClass:[NSDictionary class]] && [fieldClause count] != 0) {
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
                predicate = @{EQ : predicate};
            }
        } else if ([predicate isKindOfClass:[NSArray class]]) {
            predicate = [CDTQQueryValidator addImplicitEq:(NSArray *)predicate];
        }

        [accumulator addObject:@{fieldName : predicate}];  // can't put nil in this
    }

    return [NSArray arrayWithArray:accumulator];
}

+ (NSArray *)compressMultipleNotOperators:(NSArray *)clause
{
    NSMutableArray *accumulator = [NSMutableArray array];
    
    for (NSDictionary *fieldClause in clause) {
        NSObject *predicate = nil;
        NSString *fieldName = nil;
        // if this isn't a dictionary, we don't know what to do so add the clause
        // to the accumulator to be dealt with later as part of the final selector
        // validation.
        if ([fieldClause isKindOfClass:[NSDictionary class]] && [fieldClause count] != 0) {
            fieldName = fieldClause.allKeys[0];
            predicate = fieldClause[fieldName];
        } else {
            [accumulator addObject:fieldClause];
            continue;
        }
        
        if ([fieldName hasPrefix:@"$"] && [predicate isKindOfClass:[NSArray class]]) {
            predicate = [CDTQQueryValidator compressMultipleNotOperators:(NSArray *) predicate];
        } else {
            NSObject *operatorPredicate = nil;
            NSString *operator = nil;
            // if this isn't a dictionary, we don't know what to do so add the clause
            // to the accumulator to be dealt with later as part of the final selector
            // validation.
            if ([predicate isKindOfClass:[NSDictionary class]] &&
                [(NSDictionary *)predicate count] != 0) {
                operator = ((NSDictionary *)predicate).allKeys[0];
                operatorPredicate = ((NSDictionary *)predicate)[operator];
            } else {
                [accumulator addObject:fieldClause];
                continue;
            }
            if ([CDTQQueryValidator getNotOperators][operator]) {
                predicate = [CDTQQueryValidator replaceNotShortHandOperators:
                             (NSDictionary *)predicate];
            } else if ([operator isEqualToString:NOT]) {
                BOOL notOpFound = YES;
                BOOL invert = NO;
                NSObject *originalOperatorPredicate = operatorPredicate;
                while (notOpFound) {
                    if ([operatorPredicate isKindOfClass:[NSDictionary class]]) {
                        NSDictionary *notClause = (NSDictionary *)operatorPredicate;
                        NSString *nextOperator = notClause.allKeys[0];
                        if ([nextOperator isEqualToString:NOT]) {
                            invert = !invert;
                            operatorPredicate = notClause[nextOperator];
                        } else {
                            notOpFound = NO;
                        }
                    } else {
                        // unexpected condition - revert back to original
                        operatorPredicate = originalOperatorPredicate;
                        invert = NO;
                        notOpFound = NO;
                    }
                }
                if (invert) {
                    NSDictionary *operatorPredicateDict = (NSDictionary *)operatorPredicate;
                    operator = operatorPredicateDict.allKeys[0];
                    operatorPredicate = operatorPredicateDict[operator];
                }
                
                predicate = [CDTQQueryValidator replaceNotShortHandOperators:
                             @{operator : operatorPredicate}];
            }
        }
        
        [accumulator addObject:@{fieldName : predicate}];  // can't put nil in this
    }
    
    return [NSArray arrayWithArray:accumulator];
}

/**
 * This method take a predicate and checks it for NOT shorthand operators.
 * If found the predicate is normalized to the appropriate longhand
 * operator(s).
 */
+ (NSDictionary *)replaceNotShortHandOperators:(NSDictionary *)predicate
{
    NSString *operator = predicate.allKeys[0];
    if ([CDTQQueryValidator getNotOperators][operator]) {
        predicate =
            @{ NOT : @{ [CDTQQueryValidator getNotOperators][operator] : predicate[operator] } };
    } else if ([operator isEqualToString:NOT]) {
        NSObject *rawClause = predicate[operator];
        if ([rawClause isKindOfClass:[NSDictionary class]]) {
            NSDictionary *clause = (NSDictionary *)rawClause;
            NSString *subOperator = clause.allKeys[0];
            if ([CDTQQueryValidator getNotOperators][subOperator]) {
                predicate =
                    @{ [CDTQQueryValidator getNotOperators][subOperator] : clause[subOperator] };
            }
        }
    }
    return predicate;
}

#pragma validation class methods

+ (BOOL)validateCompoundOperatorClauses:(NSArray *)clauses
{
    BOOL valid = NO;

    for (id obj in clauses) {
        valid = NO;
        if (![obj isKindOfClass:[NSDictionary class]]) {
            LogError(@"Operator argument must be a dictionary %@", [clauses description]);
            break;
        }
        NSDictionary *clause = (NSDictionary *)obj;
        if ([clause count] != 1) {
            LogError(@"Operator argument clause should only have one key value pair: %@",
                     [clauses description]);
            break;
        }

        NSString *key = [obj allKeys][0];
        if ([@[ OR, NOT, AND ] containsObject:key]) {
            // this should have an array as top level type
            id compoundClauses = [obj objectForKey:key];
            if ([CDTQQueryValidator validateCompoundOperatorOperand:compoundClauses]) {
                // validate array
                valid = [CDTQQueryValidator validateCompoundOperatorClauses:compoundClauses];
            }
        } else if (![key hasPrefix:@"$"]) {
            // this should have a dict
            // send this for validation
            valid = [CDTQQueryValidator validateClause:[obj objectForKey:key]];
        } else {
            LogError(@"%@ operator cannot be a top level operator", key);
            break;
        }

        if (!valid) {
            break;  // if we have gotten here with valid being no, we should abort
        }
    }

    return valid;
}

+ (BOOL)validateClause:(NSDictionary *)clause
{
    //$exits lt

    NSArray *validOperators =
        @[ @"$eq", @"$lt", @"$gt", @"$exists", @"$not", @"$gte", @"$lte", @"$in" ];

    if ([clause count] == 1) {
        NSString *operator= [clause allKeys][0];

        if ([validOperators containsObject:operator]) {
            // contains correct operator
            id clauseOperand = [clause objectForKey:[clause allKeys][0]];
            // handle special case, $notis the only op that expects a dict
            if ([operator isEqualToString:NOT]) {
                return [clauseOperand isKindOfClass:[NSDictionary class]] &&
                       [CDTQQueryValidator validateClause:clauseOperand];

            } else if ([operator isEqualToString:IN]) {
                return [clauseOperand isKindOfClass:[NSArray class]] &&
                       [CDTQQueryValidator validateInListValues:clauseOperand];
            } else {
                return [CDTQQueryValidator validatePredicateValue:clauseOperand
                                                      forOperator:operator];
            }
        }
    }

    return NO;
}

+ (BOOL)validateInListValues:(NSArray *)inListValues
{
    BOOL valid = YES;
    
    for (NSObject *value in inListValues) {
        if (![CDTQQueryValidator validatePredicateValue:value forOperator:IN]) {
            valid = NO;
            break;
        }
    }
    
    return valid;
}

+ (BOOL)validatePredicateValue:(NSObject *)predicateValue forOperator:(NSString *) operator
{
    if([operator isEqualToString:@"$exists"]){
        return [CDTQQueryValidator validateExistsArgument:predicateValue];
    } else {
        return (([predicateValue isKindOfClass:[NSString class]] ||
                 [predicateValue isKindOfClass:[NSNumber class]]));
    }
}

+ (BOOL)validateExistsArgument:(NSObject *)exists
{
    BOOL valid = YES;

    if (![exists isKindOfClass:[NSNumber class]]) {
        valid = NO;
        LogError(@"$exists operator expects YES or NO");
    }

    return valid;
}

+ (BOOL)validateCompoundOperatorOperand:(NSObject *)operand
{
    if (![operand isKindOfClass:[NSArray class]]) {
        LogError(@"Arugment to compound operator is not an NSArray: %@", [operand description]);
        return NO;
    }
    return YES;
}

// we are going to need to walk the query tree to validate it before executing it
// this isn't going to be fun :'(

+ (BOOL)validateSelector:(NSDictionary *)selector
{
    // after normalising we should have a few top level selectors

    NSString *topLevelOp = [selector allKeys][0];

    // top level op can only be $and after normalisation

    if ([@[ @"$and", @"$or" ] containsObject:topLevelOp]) {
        // top level should be $and or $or they should have arrays
        id topLevelArg = [selector objectForKey:topLevelOp];

        if ([topLevelArg isKindOfClass:[NSArray class]]) {
            // safe we know its an NSArray
            return [CDTQQueryValidator validateCompoundOperatorClauses:topLevelArg];
        }
    }
    return NO;
}

@end
