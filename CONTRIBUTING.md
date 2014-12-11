Contributing
---

## Getting going

The code is developed in a workspace containing the example application.

Prerequisites:

- Xcode
- [Cocoapods](http://cocoapods.org/)
- [xcpretty](https://github.com/supermarin/xcpretty) (optional)

It should be as easy as:

    $ git clone git@github.com:cloudant/CloudantQueryObjc.git
    $ cd CloudantQueryObjc/Example
    $ pod install
    $ open Example/CloudantQueryObjc.xcworkspace

### Running tests

From the root of your cloned repository:

    xcodebuild -workspace Example/CloudantQueryObjc.xcworkspace -scheme 'CloudantQueryObjc' \
        -destination 'platform=iOS Simulator,OS=8.1,name=iPhone 4s' build test | xcpretty -c

Unfortunately you need to run on the 4S right now, because of ordering differences when iterating
through `NSDictionary` between the 4S and later devices. Yes, I know, we'll fix it sometime!

## Code Style

Code style for CloudantQueryObjc is defined with a clang format file (.clang-format) in the root of the project. All code should be formatted using the clang-format tool. 

####Installing clang-format into Xcode

Clang-format should be installed into xcode using the [ClangFormat-Xcode](https://github.com/travisjeffery/ClangFormat-Xcode) plug-in, the easiest way to do this is via [Alcatraz](https://github.com/mneorr/Alcatraz). You can also install the plugin from source using the instractions at [ClangFormat-Xcode](https://github.com/travisjeffery/ClangFormat-Xcode).

#####Setting up Xcode

We suggest Xcode should be set up to use clang-format to format code on save, and map the format command to `ctrl-i`

- Setting clang-format to run on save 


    In the menu, open Edit > Clang Format > Click Format on save (a checkmark appears in this menu item indicicating that the feature is active.)

- Assign keyboard shortcut

    - Open the System Preferences > Keyboard > Shortcuts > App Shortcuts > Click `+`
    - Set the application to be Xcode
    - Set the menu title to "Format File in Focus"
    - Set your shortcut to `ctrl-i`et your shortcut to `ctrl-i`

## Avoid committing focused tests

Specta allows you to focus a set of tests using `fit`/`fdescribe`/`fcontext`. This prevents the
other tests from running. Very useful when developing, very un-useful in CI situations.

The easiest way to prevent committing this is a git hook:

```bash
$ cd .git/hooks
$ vim pre-commit
# See below for content
$ chmod +x pre-commit
$ cd ../..
```

The `pre-commit` file should contain:

```bash
#!/bin/bash

! find Example/Tests -name "*.m" | xargs grep -I -E "(fit|fdescribe|fcontext)"
```

If you try to `git commit` when there are one or more focused tests, you'll get a listing of them:

```
$ git commit
Example/Tests/CDTQQueryExecutorTests.m:        fit(@"query without index", ^{
```
