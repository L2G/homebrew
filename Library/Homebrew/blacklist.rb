def blacklisted? name
  case name.downcase
  when 'screen', /^rubygems?$/
    t('blacklist.distributed_with_os_x', :name => name, :path => '/usr/bin')
  when 'libpcap'
    t('blacklist.distributed_with_os_x', :name => name, :path => '/usr/lib')
  when 'libiconv'
    t('blacklist.libiconv', :name => name)
  when 'tex', 'tex-live', 'texlive', 'latex'
    t('blacklist.tex')
  when 'pip'
    t('blacklist.pip')
  when 'pil'
    t('blacklist.pil')
  when 'macruby'
    t('blacklist.macruby')
  when /(lib)?lzma/
    t('blacklist.lzma')
  when 'xcode'
    if MacOS.version >= :lion
      t('blacklist.xcode_app_store')
    else
      t('blacklist.xcode_download')
    end
  when 'gtest', 'googletest', 'google-test'
    t('blacklist.google_tool', :name => 'gtest')
  when 'gmock', 'googlemock', 'google-mock'
    t('blacklist.google_tool', :name => 'gmock')
  when 'sshpass'
    t('blacklist.sshpass')
  when 'gsutil'
    t('blacklist.gsutil')
  when 'clojure'
    t('blacklist.clojure')
  when 'osmium'
    t('blacklist.osmium')
  when 'gfortran'
    t('blacklist.gfortran')
  when 'play'
    t('blacklist.play')
  when 'haskell-platform'
    t('blacklist.haskell_platform')
  end
end
