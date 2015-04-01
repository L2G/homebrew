$LOAD_PATH << File.expand_path('vendor/i18n/lib', File.dirname(__FILE__))

require 'i18n'
I18n.load_path << Dir[File.expand_path('i18n/*.yml', File.dirname(__FILE__))]
def t(*args); I18n.t(*args); end
def l(*args); I18n.l(*args); end
