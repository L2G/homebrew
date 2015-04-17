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

Translations are managed in a public project [hosted by Locale][].  If you can
add or improve translations for any language, please join the project and
contribute!

More information
----------------

For more information on how the i18n gem works, read the Rails guide ["Rails
Internationalization (I18n) API"](http://guides.rubyonrails.org/i18n.html).

----
[i18n]: https://rubygems.org/gems/i18n
[hosted by Locale]: https://www.localeapp.com/projects/7650
