Homebrew internationalization
=============================

This fork of Homebrew ("i18nbrew") uses the [i18n][] gem, which is vendored in
`Library/Homebrew/vendor`.

It is loaded and initialized in `Library/Homebrew/i18n.rb`, thus making the `t`
(translation) and `l` (localization) methods available globally.

Translated messages
-------------------

The translation files are in `Library/Homebrew/i18n/*.yml`.  Each language is in
a separate file.

Strings are quoted like any YAML string. For ease of maintenance, try to keep to
the following two styles:

 * For single-line strings, enclose the string in double quotes on the same line
   as the key.
 * For multi-line strings, put a pipe (`|`) on the same line as the key, then
   put each line below it. Indent the lines two spaces farther than the key. The
   lines will be stripped automatically, obviating the need for Homebrew's
   `undent` utility method.

----
[i18n]: https://rubygems.org/gems/i18n
