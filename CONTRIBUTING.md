Contributing
---

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