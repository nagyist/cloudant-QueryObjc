//
//  CDTQQuerySqlTranslator.m
//  Pods
//
//  Created by Michael Rhodes on 03/10/2014.
//
//

#import "CDTQQuerySqlTranslator.h"

#import "CDTQQueryExecutor.h"
#import "CDTQIndexManager.h"

@implementation CDTQQueryNode

@end

@implementation CDTQAndQueryNode

- (instancetype)init
{
    self = [super init];
    if (self) {
        _children = [NSMutableArray array];
    }
    return self;
}

@end

@implementation CDTQOrQueryNode

- (instancetype)init
{
    self = [super init];
    if (self) {
        _children = [NSMutableArray array];
    }
    return self;
}

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
    
    // For now, assume it's AND
    NSArray *clauses = query[AND];
    
    // First handle the simple @"field": @{ @"$operator": @"value" } bits,
    // which can be formed into a single SQL query, presuming we've a
    // suitable index.
    NSIndexSet *basicIdx = [clauses indexesOfObjectsPassingTest:
                            ^BOOL(id obj, NSUInteger idx, BOOL *stop) {
        NSDictionary *clause = (NSDictionary*)obj;
        NSString *field = clause.allKeys[0];
        return ![field hasPrefix:@"$"];
    }];
    
    // Form the clause with the basic predicates
    NSMutableArray *basicClauses = [NSMutableArray array];
    [basicIdx enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) {
        [basicClauses addObject:clauses[i]];
    }];
    
    NSString *chosenIndex = [CDTQQuerySqlTranslator chooseIndexForAndClause:basicClauses
                                                                fromIndexes:indexes];
    if (!chosenIndex) {
        return nil;
    }
    
    // Execute SQL on that index with appropriate values
    CDTQSqlParts *select = [CDTQQuerySqlTranslator selectStatementForAndClause:basicClauses
                                                                    usingIndex:chosenIndex];
    
    if (!select) {
        return nil;
    }
    
    CDTQSqlQueryNode *sql = [[CDTQSqlQueryNode alloc] init];
    sql.sql = select;
    
    CDTQAndQueryNode *root = [[CDTQAndQueryNode alloc] init];
    [root.children addObject:sql];
    
    // Add subclauses that are themselves AND
    NSIndexSet *andIdx = [clauses indexesOfObjectsPassingTest:
                            ^BOOL(id obj, NSUInteger idx, BOOL *stop) {
                                NSDictionary *clause = (NSDictionary*)obj;
                                NSString *field = clause.allKeys[0];
                                return [field hasPrefix:@"$and"];
                            }];
    
    // Form the clause with the basic predicates
    [andIdx enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) {
        CDTQQueryNode *andNode = [CDTQQuerySqlTranslator translateQuery:clauses[i]
                                                           toUseIndexes:indexes];
        [root.children addObject:andNode];
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
    NSArray *expandedPredicates = [CDTQQuerySqlTranslator addImplicitEq:predicates];
    
    return @{compoundOperator: expandedPredicates};
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
        
        NSString *fieldName = fieldClause.allKeys[0];
        NSObject *predicate = fieldClause[fieldName];
        
        // If the clause isn't a special clause (the field name starts with
        // $, e.g., $and), we need to check whether the clause already
        // has an operator. If not, we need to add the implicit $eq.
        if (![fieldName hasPrefix:@"$"]) {
            if (![predicate isKindOfClass:[NSDictionary class]]) {
                predicate = @{EQ: predicate};
            }
        }
        
        [accumulator addObject:@{fieldName: predicate}];
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
                                  };
    for (NSDictionary *component in clause) {
        if (component.count != 1) {
            return nil;
        }
        
        NSString *fieldName = component.allKeys[0];
        NSDictionary *predicate = component[fieldName];
        
        if (predicate.count != 1) {
            return nil;
        }
        
        NSString *operator = predicate.allKeys[0];
        NSString *sqlOperator = operatorMap[operator];
        
        if (!sqlOperator) {
            return nil;
        }
        
        NSString *sqlClause = [NSString stringWithFormat:@"\"%@\" %@ ?", 
                               fieldName, sqlOperator];
        [sqlClauses addObject:sqlClause];
        
        [sqlParameters addObject:[predicate objectForKey:operator]];

    }
    
    return [CDTQSqlParts partsForSql:[sqlClauses componentsJoinedByString:@" AND "]
                          parameters:sqlParameters];
    
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
    
    NSString *sql = @"SELECT docid FROM %@ WHERE %@;";
    sql = [NSString stringWithFormat:sql, tableName, where.sqlWithPlaceholders];
    
    CDTQSqlParts *parts = [CDTQSqlParts partsForSql:sql
                                         parameters:where.placeholderValues];
    return parts;
}

@end
