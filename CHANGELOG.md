# CloudantQueryObjc CHANGELOG

## 2.0.0 (2015-04-09)

- Remove all code as codebase has been moved into CDTDatastore,
  https://github.com/cloudant/CDTDatastore.

## 1.0.3 (2015-03-24)

- [NEW] Add support for `$in` query operator.
- [NEW] Add support for `$nin` query operator.
- [FIX] A bug that over-restricted `$or` query results is now fixed.  Now when
  multiple clauses in a query are OR-ed and at least one clause is not
  satisifed by an index then the post hoc matcher engine provides the query
  results for the entire query and no longer uses any one clause as the
  limiting agent for the final query result set.
- [FIX] Using MongoDB query as the "gold" standard, query support for `NOT`
  has been fixed to return result sets correctly (as in MongoDB query).
  Previously, the result set from a query like
  `{ "pet": { "$not" { "$eq": "dog" } } }` would include a document
  like `{ "pet" : [ "cat", "dog" ], ... }` because the array contains an
  object that isn't `dog`.  The new behavior is that `$not` now inverts the
  result set, so this document will no longer be included because it has an
  array element that matches `dog`.
- [NOTE] Correct documentation for enumerating query results.
- [NOTE] Bump CocoaLumberjack to 2.0.0.
- [NOTE] Reduce memory usage during indexing process by adding autorelease
  blocks to code paths.

## 1.0.2 (2015-01-23)

- [NOTE] Bump CocoaLumberjack to 2.0.0-rc.

## 1.0.1 (2014-12-01)

- Correct README's Podfile instructions.

## 1.0 (2014-11-21)

Initial release of CloudantQueryObjc.
