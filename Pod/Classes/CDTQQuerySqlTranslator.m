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

@end

@implementation CDTQSqlQueryNode

@end

@implementation CDTQQuerySqlTranslator

static NSString *const AND = @"$and";

+ (CDTQQueryNode*)translateQuery:(NSDictionary*)query toUseIndexes:(NSDictionary*)indexes
{
    query = [CDTQQuerySqlTranslator normaliseQuery:query];
    
    NSString *chosenIndex = [CDTQQuerySqlTranslator chooseIndexForAndClause:query[AND]
                                                                fromIndexes:indexes];
    if (!chosenIndex) {
        return nil;
    }
    
    // Execute SQL on that index with appropriate values
    CDTQSqlParts *select = [CDTQQuerySqlTranslator selectStatementForAndClause:query[AND]
                                                                    usingIndex:chosenIndex];
    
    if (!select) {
        return nil;
    }
    
    CDTQSqlQueryNode *sql = [[CDTQSqlQueryNode alloc] init];
    sql.sql = select;
    
    CDTQAndQueryNode *root = [[CDTQAndQueryNode alloc] init];
    [root.children addObject:sql];
    
    return root;
}

#pragma mark Pre-process query

+ (NSDictionary*)normaliseQuery:(NSDictionary*)query
{
    if (query.count == 1 && query[AND]) {
        return query;
    }
    
    NSMutableArray *andClause = [NSMutableArray array];
    for (NSString *k in query) {
        [andClause addObject:@{k: query[k]}];
    }
    
    return @{AND: [NSArray arrayWithArray:andClause]};
}

#pragma mark Process single AND clause with no sub-clauses

+ (NSArray*)fieldsForAndClause:(NSArray*)clause 
{
    NSMutableArray *fieldNames = [NSMutableArray array];
    for (NSDictionary* term in clause) {
        if (term.count == 1) {
            [fieldNames addObject:[term allKeys][0]];
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
