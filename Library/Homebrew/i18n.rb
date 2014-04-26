$LOAD_PATH << File.expand_path('vendor/r18n-core/lib',    File.dirname(__FILE__))
$LOAD_PATH << File.expand_path('vendor/r18n-desktop/lib', File.dirname(__FILE__))

require 'r18n-desktop'

# Locale info is in Library/Homebrew/i18n
R18n.from_env(File.expand_path('i18n', File.dirname(__FILE__)))
