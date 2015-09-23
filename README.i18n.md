Homebrew internationalization
=============================

This fork of Homebrew ("i18nbrew") uses the [i18n][] gem, which is vendored in
`Library/Homebrew/vendor`.

It is loaded and initialized in `Library/Homebrew/i18n.rb`, thus making the `t`
(translation) and `l` (localization) methods available globally.

In the long term, the i18n gem should be replaced by a lighter-weight solution
-- probably a workalike written expressly for Homebrew, but one that could be
used in other Ruby projects.

Translated messages
-------------------

The translation files are in `Library/Homebrew/locales/*.yml`.  Each language is
in a separate file.

Translations are managed in a public project [hosted by Locale][].  If you can
add or improve translations for any language, please join the project and
contribute!

The [i18n-tasks][] gem is recommended for additional maintenance of the
translation files.

More information
----------------

For more information on how the i18n gem works, read the Rails guide ["Rails
Internationalization (I18n) API"](http://guides.rubyonrails.org/i18n.html).

----
[i18n]: https://rubygems.org/gems/i18n
[hosted by Locale]: https://www.localeapp.com/projects/7650
[i18n-tasks]: https://rubygems.org/gems/i18n-tasks
