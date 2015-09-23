def blacklisted?(name)
  case name.downcase
  when "gem", /^rubygems?$/
    t("blacklist.gem_via_ruby_formula")
  when "tex", "tex-live", "texlive", "latex"
    t("blacklist.tex")
  when "pip"
    t("blacklist.pip")
  when "pil"
    t("blacklist.pil")
  when "macruby"
    t("blacklist.macruby")
  when /(lib)?lzma/
    t("blacklist.lzma")
  when "xcode"
    if MacOS.version >= :lion
      t("blacklist.xcode_app_store")
    else
      t("blacklist.xcode_download")
    end
  when "gtest", "googletest", "google-test"
    t("blacklist.google_tool", :name => "gtest")
  when "gmock", "googlemock", "google-mock"
    t("blacklist.google_tool", :name => "gmock")
  when "sshpass"
    t("blacklist.sshpass")
  when "gsutil"
    t("blacklist.gsutil")
  when "clojure"
    t("blacklist.clojure")
  when "osmium"
    t("blacklist.osmium")
  when "gfortran"
    t("blacklist.gfortran")
  when "play"
    t("blacklist.play")
  when "haskell-platform"
    t("blacklist.haskell_platform")
  end
end
