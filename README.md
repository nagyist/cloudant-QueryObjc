# CloudantQueryObjc

[![Build Status](https://magnum.travis-ci.com/cloudant/CloudantQueryObjc.svg?token=YYmxubNGds1Kt16kQ9v7&branch=master)](https://magnum.travis-ci.com/cloudant/CloudantQueryObjc)
[![Version](https://img.shields.io/cocoapods/v/CloudantQueryObjc.svg?style=flat)](http://cocoadocs.org/docsets/CloudantQueryObjc)
[![License](https://img.shields.io/cocoapods/l/CloudantQueryObjc.svg?style=flat)](http://cocoadocs.org/docsets/CloudantQueryObjc)
[![Platform](https://img.shields.io/cocoapods/p/CloudantQueryObjc.svg?style=flat)](http://cocoadocs.org/docsets/CloudantQueryObjc)

Cloudant Query Objective C is an Objective C implementation of [Cloudant Query][1] for iOS and
OS X. It works in concert with [CDTDatastore][2], it's not a standalone querying engine.

Cloudant Query is based on MongoDB's query implementation, so users of MongoDB should feel
at home using Cloudant Query in their mobile applications. Where behaviours differ, the Mobile
version of Cloudant Query tries to stick to what Cloudant Query does in the Cloudant Service
rather than MongoDB's behavior.

The aim is that the query you use on our cloud-based database works for your mobile application.

**Note**: this is a very early version, and it probably won't work as you expect yet! In
particular, there's very little information to help debugging when errors happen, leaving you
in the debugger. There is also little error checking, so things might explode without warning.
  

[1]: https://docs.cloudant.com/api/cloudant-query.html
[2]: https://github.com/cloudant/cdtdatastore

## Adding to your project

CloudantQueryObjc is available through [CocoaPods](http://cocoapods.org). To install 
it, add the following line to your Podfile:

    pod "CloudantQueryObjc"

## Usage

These notes assume familiarity with CDTDatastore.

Cloudant Query uses indexes explicitly defined over the fields in the document. Multiple
indexes can be created for use in different queries, the same field may end up indexed in
more than one index.

Querying is carried out by supplying a query in the form of a dictionary which describes the
query.

Set up some documents first:

```objc
CDTDatastore *ds;
        
// Create our datastore
ds = [factory datastoreNamed:@"test" error:nil];

// Create some documents
CDTMutableDocumentRevision *rev = [CDTMutableDocumentRevision revision];
            
rev.docId = @"mike12";
rev.body = @{ @"name": @"mike", @"age": @12, @"pet": @{@"species": @"cat"} };
[ds createDocumentFromRevision:rev error:nil];

rev.docId = @"mike34";
rev.body = @{ @"name": @"mike", @"age": @34, @"pet": @{@"species": @"dog"} };
[ds createDocumentFromRevision:rev error:nil];

rev.docId = @"mike72";
rev.body = @{ @"name": @"mike", @"age": @34, @"pet": @{@"species": @"cat"} };
[ds createDocumentFromRevision:rev error:nil];
```

Next, create a `CDTQIndexManager` object:

```objc
CDTQIndexManager *im;
im = [CDTQIndexManager managerUsingDatastore:ds error:nil];

// Note CDTQ prefix!
```

Call `-ensureIndexed:withName:` to create indexes. These indexes are persistent across restarts,
but `-ensureIndexed:withName:` can be called many times as long as the same indexed fields are
used for the same name.

If an index needs to be changed, first delete the existing index, then call 
`-ensureIndexed:withName:` with the new definition.

```objc
// Create an index over the name and age fields.
if (![im ensureIndexed:@[@"name", @"age"] withName:@"basic"]) {
    // there was an error creating the index
}

// Use dotted notation to index sub-document fields
if (![im ensureIndexed:@[@"pet.species"] withName:@"species"]) {
    // there was an error
}
```

Query documents using `NSDictionary` objects. These use the [Cloudant Query `selector`][sel]
syntax. Further query options will be added soon. 

Note the restrictions in Unsupported features section!

[sel]: https://docs.cloudant.com/api/cloudant-query.html#selector-syntax

```objc
// Query some documents
// The set of fields in a query MUST be in a single index right now
NSDictionary *query = @{@"name": @{@"$eq": @"mike"}, 
                        @"age": @{@"$eq": @12}};
CDTQResultSet *result = [im find:query];
for (CDTDocumentRevision *rev in result) {
    // do something
}

NSDictionary *query = @{@"pet.species": @{@"$eq": @"cat"}};
CDTQResultSet *result = [im find:query];

// THIS WILL FAIL because there isn't an index for all the used fields
NSDictionary *query = @{@"pet.species": @{@"$eq": @"cat"}, 
                        @"age": @{@"$eq": @12}};
CDTQResultSet *result = [im find:query];
// `result` will return nil because query couldn't be executed.
// If there are no results, there will still be a result set returned.
```

At the moment only a (small) subset of Cloudant Query features are supported. See below for
the list of supported features. Over time this will increase.

Error reporting is also terrible right now, the only indication something went wrong is a
`nil` return value from `-find:` or `-ensureIndexed:withName:`.

## Supported features

Right now the list of supported features is small:

- Create compound indexes using dotted notation that index JSON fields
- Delete index by name
- Execute nested queries:
    - all fields in an $and clause of a query must be in a single compound index.
      That is, for `{"$and": @["name": "mike", "age": 20]}`, both `name` and `age`
      must be in an index defined in a single `-ensureIndexed:withName:` call.
      
Selectors -> combination

- `$and`
- `$or`

Selectors -> Conditions -> Equalitites

- `$lt`
- `$lte`
- `$eq`
- `$gte`
- `$gt`

Implicit operators

- Implicit `$and`.
- Implicit `$eq`.

## Unsupported features

### Query

Overall restrictions:

- Cannot use more than one index per AND clause in a query.
- Cannot querying using unindexed fields.
- Cannot use covering indexes with projection (`fields`) to avoid loading 
  documents from the datastore.

#### Query syntax

- Limiting returned results.
- Skipping results.
- Sorting results.
- Field projection.
- Using non-dotted notation to query sub-documents.
    - That is, `{"pet": { "species": {"$eq": "cat"} } }` is unsupported,
      you must use `{"pet.species": {"$eq": "cat"}}`.

Selectors -> combination

- `$not`
- `$nor`
- `$all`
- `$elemMatch`

Selectors -> Conditions -> Equalitites

- `$ne`

Selectors -> Condition -> Objects

- `$exists`
- `$type`

Selectors -> Condition -> Array

- `$in`
- `$nin`
- `$size`

Selectors -> Condition -> Misc

- `$mod`
- `$regex`

### Indexing

- We don't support indexing array fields.



## Running the example project

To run the example project, clone the repo, and run `pod install` from the Example directory first.

## Requirements

This package requires:

- [CDTDatastore](https://github.com/cloudant/cdtdatastore)
- [FMDB](https://github.com/ccgus/fmdb)

## License

CloudantQueryObjc is available under the Apache V2 license. See the LICENSE file for more info.

