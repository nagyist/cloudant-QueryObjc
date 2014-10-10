Logging 
==============

Logging in CloudantQueryObjc uses CocoaLumberJack.


##Logging Context

CloudantQueryObjc uses the context 17. This follows on directly from the contexts used in CDTDatastore (TBD). If your application uses CocoaLumberJack you should avoid using CDTDatastore Contexts and CLoudantQueryObjc Context.

##Logging Macros

The logging macros are based on the macros used in CDTDatastore. However since there is only one log context for CloudantQuery, the context argument is omitted. The logging macros look like:

```objc
LogError(@"Log message %@",@"here");
```
Each log level has a macro associated with it, these are just the level prefixed with Log.

There are 5 levels of logging in CloudantQuery. These are:

- Error
- Warn
- Info
- Debug
- Verbose

The default level of logging is Warn. To change the log level, use the macro `CDTQChangeLogLevel`. __DO__ __NOT__ directly use the `cDTQLogLevel` variable. By default there are no loggers attached the CocoaLumberJack framework and CloudantSync by default does not add any loggers. 

It is advised that code is incorporated into your application to add a remove loggers without recompiling the code. A logger is added to CocoaLumberJack by calling `[DDLog addLogger:logger]`.

##Adding New Log statements

To add log statements to CDTQ classes, the header `CDTQLogging.h` needs to be imported. Each macro is compatible with NSLog and DDLog respectively.

