# CloudantQueryObjc

This code base has been merged into the [CDTDatastore][1] repository which is now the default location for this code.  Therefore, this repository (CloudantQueryObjc) should no longer be used.

[1]: https://github.com/cloudant/CDTDatastore

## Migrating

If you used the CloudantQueryObjc project before migration should be simple.

1. Remove `pod "CloudantQueryObjc"` from your Podfile.
2. Update the version of CDTDatastore required in your Podfile if needed to `0.16` or above.
3. Run `pod update`. You should get CDTDatastore `0.16` or above.
4. All imports are included in `CloudantSync.h`, so remove and replace any CloudantQueryObjc imports, probably:
   
   ```
   #import <CloudantQueryObjc/CDTDatastore+Query.h>
   #import <CloudantQueryObjc/CDTQResultSet.h>
   ```