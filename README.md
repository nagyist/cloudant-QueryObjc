# CloudantQueryObjc

[![CI Status](https://img.shields.io/travis/cloudant/CloudantQueryObjc.svg?style=flat)](https://travis-ci.org/cloudant/CloudantQueryObjc)
[![Version](https://img.shields.io/cocoapods/v/CloudantQueryObjc.svg?style=flat)](http://cocoadocs.org/docsets/CloudantQueryObjc)
[![License](https://img.shields.io/cocoapods/l/CloudantQueryObjc.svg?style=flat)](http://cocoadocs.org/docsets/CloudantQueryObjc)
[![Platform](https://img.shields.io/cocoapods/p/CloudantQueryObjc.svg?style=flat)](http://cocoadocs.org/docsets/CloudantQueryObjc)

Cloudant Query Objective C is an Objective C implementation of [Cloudant Query][1] for iOS and
OS X. It works in concert with [CDTDatastore][2], it's not a standalone querying engine.

Cloudant Query is inspired by MongoDB's query implementation, so users of MongoDB should feel
at home using Cloudant Query in their mobile applications.

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

For the following examples, assume these documents are in the datastore:

```objc
@{ @"name": @"mike", 
   @"age": @12, 
   @"pet": @{@"species": @"cat"} };

@{ @"name": @"mike", 
   @"age": @34, 
   @"pet": @{@"species": @"dog"} };

@{ @"name": @"fred", 
   @"age": @23, 
   @"pet": @{@"species": @"cat"} };
```

### Headers

You need to include `CDTQIndexManager.h`:

```objc
#import "CDTQIndexManager.h"
```

### The index manager

The `CDTQIndexManager` object is used to manage and query the indexes on a single
`CDTDatastore` object. To create one, pass a datastore to its convenience constructor:

```objc
CDTDatastore *ds = //... see CDTDatastore documentation ...
CDTQIndexManager *im;
im = [CDTQIndexManager managerUsingDatastore:ds error:nil];

// Note CDTQ prefix!
```

### Creating indexes

In order to query documents, indexes need to be created over
the fields to be queried against.

Use `-ensureIndexed:withName:` to create indexes. These indexes are persistent
across application restarts as they are saved to disk. They are kept up to date
documents change; there's no need to call `-ensureIndexed:withName:` each
time your applications starts, though there is no harm in doing so.

The first argument to `-ensureIndexed:withName:` is a list of fields to
put into this index. The second argument is a name for the index. This is used
to delete indexes at a later stage and appears when you list the indexes
in the database.

A field can appear in more than one index. The query engine will select an
appropriate index to use for a given query. However, the more indexes you have,
the more disk space they will use and the greater overhead in keeping them
up to date.

To index values in sub-documents, use _dotted notation_. This notation puts
the field names in the path to a particular value into a single string,
separated by dots. Therefore, to index the `species`
field of the `pet` sub-document in the examples above, use `pet.species`.

```objc
// Create an index over the name and age fields.
NSString *name = [im ensureIndexed:@[@"name", @"age", @"pet.species"] 
                          withName:@"basic"]
if (!name) {
    // there was an error creating the index
}
```

`-ensureIndexed:withName:` returns the name of the index if it is successful,
otherwise it returns `nil`.

If an index needs to be changed, first delete the existing index, then call 
`-ensureIndexed:withName:` with the new definition.

#### Indexing document metadata (_id and _rev)

The document ID and revision ID are automatically indexed under `_id` and `_rev` 
respectively. If you need to query on document ID or document revision ID,
use these field names.

#### Indexing array fields

Indexing of array fields is supported. See "Array fields" below for the indexing and
querying semantics.

### Querying syntax

Query documents using `NSDictionary` objects. These use the [Cloudant Query `selector`][sel]
syntax. Several features of Cloudant Query are not yet supported in this implementation.
See below for more details.

[sel]: https://docs.cloudant.com/api/cloudant-query.html#selector-syntax

#### Equality and comparions

To query for all documents where `pet.species` is `cat`:

```objc
@{ @"pet.species": @"cat" };
```

If you don't specify a condition for the clause, equality (`$eq`) is used. To use
other conditions, supply them explicitly in the clause.

To query for documents where `age` is greater than twelve use the `$gt` condition:

```objc
@{ @"age": @{ @"$gt": @12 } };
```

See below for supported operators (Selections -> Conditions).

#### Compound queries

Compound queries allow selection of documents based on more than one critera.
If you specify several clauses, they are implicitly joined by AND.

To find all people named `fred` with a `cat` use:

```objc
@{ @"name": @"fred", @"pet.species": @"cat" };
```

##### Using OR to join clauses

Use `$or` to find documents where just one of the clauses match.

To find all people with a `dog` who are under thirty:

```objc
@{ @"$or": @[ @{ @"pet.species": @{ @"$eq": @"dog" } }, 
              @{ @"age": @{ @"$lt": @30 } }
            ]};
```

#### Using AND and OR in queries

Using a combination of AND and OR allows the specification of complex queries.

This selects documents where _either_ the person has a pet `dog` _or_ they are
both over thirty _and_ named `mike`:

```objc
@{ @"$or": @[ @{ @"pet.species": @{ @"$eq": @"dog" } }, 
              @{ @"$and": @[ @{ @"age": @{ @"$gt": @30 } },
                             @{ @"name": @{ @"$eq": @"mike" } }
                          ] }
            ]};
```

### Executing queries

To find documents matching a query, use the `CDTQIndexManager` objects `-find:`
function. This returns an object that can be used in `for..in` loops to
enumerate over the results.

```objc
CDTQResultSet *result = [im find:query];
for (CDTDocumentRevision *rev in result) {
    // The returned revision object contains all fields for
    // the object. You cannot project certain fields in the
    // current implementation.
}
```

### Array fields

Indexing and querying over array fields is supported in Cloudant Query Objective C, with some
caveats.

Take this document as an example:

```
{
  _id: mike32
  pet: [ cat, dog, parrot ],
  name: mike,
  age: 32
}
```

You can create an index over the `pet` field:

```objc
NSString *name = [im ensureIndexed:@[@"name", @"age", @"pet"] 
                          withName:@"basic"]
```

Each value of the array is treated as a separate entry in the index. This means that
a query such as:

```
{ pet: { $eq: cat } }
```

Will return the document `mike32`. Negation may be slightly confusing:

```
{ pet: { $not: { $eq: cat } } }
```

Will also return `mike32` because there are values in the array that are not `cat`.

#### Restrictions

Only one field in a given index may be an array. This is because each entry in each array
requires an entry in the index, causing a Cartesian explosion in index size. Taking the
above example, this document wouldn't be indexed because the `name` and `pet` fields are
both indexed in a single index:


```
{
  _id: mike32
  pet: [ cat, dog, parrot ],
  name: [ mike, rhodes ],
  age: 32
}
```

If this happens, an error will be emitted into the log but the indexing process will be
successful.

However, if there was one index with `pet` in and another with `name` in, like this:

```objc
NSString *name = [im ensureIndexed:@[@"name", @"age"] 
                          withName:@"basic"];
NSString *name = [im ensureIndexed:@[@"age", @"pet"] 
                          withName:@"basic"]
```

The document _would_ be indexed in both of these indexes: each index only contains one of
the array fields.

Also see "Unsupported features", below.


### Errors

Error reporting is terrible right now. The only indication something went wrong is a
`nil` return value from `-find:` or `-ensureIndexed:withName:`. We're working on
adding logging.

## Supported Cloudant Query features

Right now the list of supported features is small:

- Create compound indexes using dotted notation that index JSON fields
- Delete index by name
- Execute nested queries:
    - all fields in an $and clause of a query must be in a single compound index.
      That is, for `{"$and": @["name": "mike", "age": 20]}`, both `name` and `age`
      must be in an index defined in a single `-ensureIndexed:withName:` call.
- Limiting returned results.
- Skipping results.
      
Selectors -> combination

- `$and`
- `$or`

Selectors -> Conditions -> Equalitites

- `$lt`
- `$lte`
- `$eq`
- `$gte`
- `$gt`
- `$ne`

Selectors -> combination

- `$not`

Implicit operators

- Implicit `$and`.
- Implicit `$eq`.

Arrays

- Indexing individual values in an array.
- Querying for individual values in an array.

## Unsupported Cloudant Query features

As this is an early version of Query on this platform, some features are
not supported yet. We're actively working to support features -- check
the commit log :)

### Query

Overall restrictions:

- Cannot use more than one index per AND clause in a query.
- Cannot querying using unindexed fields.
- Cannot use covering indexes with projection (`fields`) to avoid loading 
  documents from the datastore.

#### Query syntax

- Sorting results #7.
- Field projection #8.
- Using non-dotted notation to query sub-documents.
    - That is, `{"pet": { "species": {"$eq": "cat"} } }` is unsupported,
      you must use `{"pet.species": {"$eq": "cat"}}`.
- Cannot use multiple conditions in a single clause, `{ field: { $gt: 7, $lt: 14 } }`.

Selectors -> combination

- `$nor` #10
- `$all` (unplanned)
- `$elemMatch` (unplanned, waiting on arrays support for query)

Selectors -> Condition -> Objects

- `$exists` #11
- `$type` (unplanned)

Selectors -> Condition -> Array

- `$in` (waiting on arrays support)
- `$nin` (waiting on arrays support)
- `$size` (waiting on arrays support)

Selectors -> Condition -> Misc

- `$mod` (unplanned, waiting on filtering)
- `$regex` (unplanned, waiting on filtering)


Arrays

- Dotted notation to index or query sub-documents in arrays.
- Querying for exact array match, `{ field: [ 1, 3, 7 ] }`.
- Querying to match a specific array element using dotted notation, `{ field.0: 1 }`.
- Querying using `$all`.
- Querying using `$elemMatch`.


## Running the example project

To run the example project, clone the repo, and run `pod install` from the Example directory first.

## Requirements

This package requires:

- [CDTDatastore](https://github.com/cloudant/cdtdatastore)
- [FMDB](https://github.com/ccgus/fmdb)

## License

CloudantQueryObjc is available under the Apache V2 license. See the LICENSE file for more info.

