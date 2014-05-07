Homebrew internationalization
=============================

This fork of Homebrew ("i18nbrew") uses the [r18n-core][] and [r18n-desktop][]
gems, which are vendored in `Library/Homebrew/vendor`.

They are loaded and initialized in `Library/Homebrew/i18n.rb`.  The
`R18n::Helpers` class is included, which makes the `t` (translation) and `l`
(localization) methods available globally.

The translation files are in `Library/Homebrew/i18n/*.yml`.

----
[r18n-core]:     https://rubygems.org/gems/r18n-core
[r18n-desktop]:  https://rubygems.org/gems/r18n-desktop
