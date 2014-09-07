require "cmd/missing"
require "formula"
require "keg"
require "version"

class Volumes
  def initialize
    @volumes = get_mounts
  end

  def which path
    vols = get_mounts path

    # no volume found
    if vols.empty?
      return -1
    end

    vol_index = @volumes.index(vols[0])
    # volume not found in volume list
    if vol_index.nil?
      return -1
    end
    return vol_index
  end

  def get_mounts path=nil
    vols = []
    # get the volume of path, if path is nil returns all volumes

    args = %w[/bin/df -P]
    args << path if path

    Utils.popen_read(*args) do |io|
      io.each_line do |line|
        case line.chomp
          # regex matches: /dev/disk0s2   489562928 440803616  48247312    91%    /
        when /^.+\s+[0-9]+\s+[0-9]+\s+[0-9]+\s+[0-9]{1,3}%\s+(.+)/
          vols << $1
        end
      end
    end
    return vols
  end
end


class Checks

############# HELPERS
  # Finds files in HOMEBREW_PREFIX *and* /usr/local.
  # Specify paths relative to a prefix eg. "include/foo.h".
  # Sets @found for your convenience.
  def find_relative_paths *relative_paths
    @found = %W[#{HOMEBREW_PREFIX} /usr/local].uniq.inject([]) do |found, prefix|
      found + relative_paths.map{|f| File.join(prefix, f) }.select{|f| File.exist? f }
    end
  end

  def inject_file_list(list, str)
    list.inject(str) { |s, f| s << "    #{f}\n" }
  end

  # Git will always be on PATH because of the wrapper script in
  # Library/Contributions/cmd, so we check if there is a *real*
  # git here to avoid multiple warnings.
  def git?
    return @git if instance_variable_defined?(:@git)
    @git = system "git --version >/dev/null 2>&1"
  end
############# END HELPERS

# Sorry for the lack of an indent here, the diff would have been unreadable.
# See https://github.com/Homebrew/homebrew/pull/9986
def check_path_for_trailing_slashes
  bad_paths = ENV['PATH'].split(File::PATH_SEPARATOR).select { |p| p[-1..-1] == '/' }
  return if bad_paths.empty?
  s = t.cmd.doctor.trailing_slashes
  bad_paths.each{|p| s << "    #{p}"}
  s
end

# Installing MacGPG2 interferes with Homebrew in a big way
# http://sourceforge.net/projects/macgpg2/files/
def check_for_macgpg2
  return if File.exist? '/usr/local/MacGPG2/share/gnupg/VERSION'

  suspects = %w{
    /Applications/start-gpg-agent.app
    /Library/Receipts/libiconv1.pkg
    /usr/local/MacGPG2
  }

  if suspects.any? { |f| File.exist? f }
    t.cmd.doctor.macgpg2
  end
end

def __check_stray_files(pattern, white_list, message)
  files = Dir[pattern].select { |f| File.file? f and not File.symlink? f }
  bad = files.reject {|d| white_list.key? File.basename(d) }
  inject_file_list(bad, message) unless bad.empty?
end

def check_for_stray_dylibs
  # Dylibs which are generally OK should be added to this list,
  # with a short description of the software they come with.
  white_list = {
    "libfuse.2.dylib" => t.cmd.doctor.name.macfuse,
    "libfuse_ino64.2.dylib" => t.cmd.doctor.name.macfuse
  }

  __check_stray_files '/usr/local/lib/*.dylib', white_list, t.cmd.doctor.stray_dylibs
end

def check_for_stray_static_libs
  # Static libs which are generally OK should be added to this list,
  # with a short description of the software they come with.
  white_list = {
    "libsecurity_agent_client.a" => t.cmd.doctor.name.os_x_10_8_2_supplemental,
    "libsecurity_agent_server.a" => t.cmd.doctor.name.os_x_10_8_2_supplemental
  }

  __check_stray_files '/usr/local/lib/*.a', white_list, t.cmd.doctor.stray_static_libs
end

def check_for_stray_pcs
  # Package-config files which are generally OK should be added to this list,
  # with a short description of the software they come with.
  white_list = {}

  __check_stray_files '/usr/local/lib/pkgconfig/*.pc', white_list, t.cmd.doctor.stray_pcs
end

def check_for_stray_las
  white_list = {
    "libfuse.la" => t.cmd.doctor.name.macfuse,
    "libfuse_ino64.la" => t.cmd.doctor.name.macfuse,
  }

  __check_stray_files '/usr/local/lib/*.la', white_list, t.cmd.doctor.stray_las
end

def check_for_other_package_managers
  ponk = MacOS.macports_or_fink
  unless ponk.empty?
    t.cmd.doctor.macports_or_fink(ponk.join(", "))
  end
end

def check_for_broken_symlinks
  broken_symlinks = []

  Keg::PRUNEABLE_DIRECTORIES.select(&:directory?).each do |d|
    d.find do |path|
      if path.symlink? && !path.resolved_path_exists?
        broken_symlinks << path
      end
    end
  end
  unless broken_symlinks.empty?
    t.cmd.doctor.broken_symlinks(broken_symlinks * "\n      ")
  end
end

if MacOS.version >= "10.9"
  def check_for_installed_developer_tools
    unless MacOS::Xcode.installed? || MacOS::CLT.installed?
      t.cmd.doctor.install_clt
    end
  end

  def check_xcode_up_to_date
    if MacOS::Xcode.installed? && MacOS::Xcode.outdated?
      t.cmd.doctor.xcode_outdated_app_store(MacOS::Xcode.version,
                                            MacOS::Xcode.latest_version)
    end
  end

  def check_clt_up_to_date
    if MacOS::CLT.installed? && MacOS::CLT.outdated?
      t.cmd.doctor.xcode_clt_update_from_app_store
    end
  end
elsif MacOS.version == "10.8" || MacOS.version == "10.7"
  def check_for_installed_developer_tools
    unless MacOS::Xcode.installed? || MacOS::CLT.installed?
      t.cmd.doctor.xcode_clt_install_from_web
    end
  end

  def check_xcode_up_to_date
    if MacOS::Xcode.installed? && MacOS::Xcode.outdated?
      t.cmd.doctor.xcode_outdated_download(MacOS::Xcode.version,
                                           MacOS::Xcode.latest_version)
    end
  end

  def check_clt_up_to_date
    if MacOS::CLT.installed? && MacOS::CLT.outdated?
      t.cmd.doctor.xcode_clt_update_from_web
    end
  end
else
  def check_for_installed_developer_tools
    unless MacOS::Xcode.installed?
      t.cmd.doctor.xcode_not_installed
    end
  end

  def check_xcode_up_to_date
    if MacOS::Xcode.installed? && MacOS::Xcode.outdated?
      t.cmd.doctor.xcode_outdated_download(MacOS::Xcode.version,
                                           MacOS::Xcode.latest_version)
    end
  end
end

def check_for_osx_gcc_installer
  if (MacOS.version < "10.7" || MacOS::Xcode.version > "4.1") && \
      MacOS.clang_version == "2.1"
    message = t.cmd.doctor.osx_gcc_installer
    if MacOS.version >= :mavericks
      message += t.cmd.doctor.osx_gcc_installer_advice.mavericks
    elsif MacOS.version >= :lion
      message += t.cmd.doctor.osx_gcc_installer_advice.lion(MacOS::Xcode.latest_version)
    else
      message += t.cmd.doctor.osx_gcc_installer_advice.other(MacOS::Xcode.latest_version)
    end
  end
end

def check_for_stray_developer_directory
  # if the uninstaller script isn't there, it's a good guess neither are
  # any troublesome leftover Xcode files
  uninstaller = Pathname.new("/Developer/Library/uninstall-developer-folder")
  if MacOS::Xcode.version >= "4.3" && uninstaller.exist?
    t.cmd.doctor.stray_dev_dir(uninstaller)
  end
end

def check_for_bad_install_name_tool
  return if MacOS.version < "10.9"

  libs = `otool -L /usr/bin/install_name_tool`
  unless libs.include? "/usr/lib/libxcselect.dylib" then <<-EOS.undent
    You have an outdated version of /usr/bin/install_name_tool installed.
    This will cause binary package installations to fail.
    This can happen if you install osx-gcc-installer or RailsInstaller.
    To restore it, you must reinstall OS X or restore the binary from
    the OS packages.
    EOS
  end
end

def __check_subdir_access base
  target = HOMEBREW_PREFIX+base
  return unless target.exist?

  cant_read = []

  target.find do |d|
    next unless d.directory?
    cant_read << d unless d.writable_real?
  end

  cant_read.sort!
  if cant_read.length > 0 then
    s = t.cmd.doctor.unwritable_directories(target)
    cant_read.each{ |f| s << "    #{f}\n" }
    s
  end
end

def check_access_share_locale
  __check_subdir_access 'share/locale'
end

def check_access_share_man
  __check_subdir_access 'share/man'
end

def check_access_usr_local
  return unless HOMEBREW_PREFIX.to_s == '/usr/local'

  unless File.writable_real?("/usr/local")
    t.cmd.doctor.unwritable_usr_local
  end
end

%w{include etc lib lib/pkgconfig share}.each do |d|
  define_method("check_access_#{d.sub("/", "_")}") do
    dir = HOMEBREW_PREFIX.join(d)
    if dir.exist? && !dir.writable_real?
      t.cmd.doctor.unwritable_directory(dir)
    end
  end
end

def check_access_logs
  if HOMEBREW_LOGS.exist? and not HOMEBREW_LOGS.writable_real?
    t.cmd.doctor.unwritable_access_logs(HOMEBREW_LOGS)
  end
end

def check_ruby_version
  ruby_version = MacOS.version >= "10.9" ? "2.0" : "1.8"
  if RUBY_VERSION[/\d\.\d/] != ruby_version
    t.cmd.doctor.unsupported_ruby(RUBY_VERSION, MacOS.version, ruby_version)
  end
end

def check_homebrew_prefix
  unless HOMEBREW_PREFIX.to_s == '/usr/local'
    t.cmd.doctor.homebrew_not_in_usr_local
  end
end

def check_xcode_prefix
  prefix = MacOS::Xcode.prefix
  return if prefix.nil?
  if prefix.to_s.match(' ')
    t.cmd.doctor.xcode_prefix_has_space
  end
end

def check_xcode_prefix_exists
  prefix = MacOS::Xcode.prefix
  return if prefix.nil?
  unless prefix.exist?
    t.cmd.doctor.xcode_prefix_nonexistent(prefix)
  end
end

def check_xcode_select_path
  if not MacOS::CLT.installed? and not File.file? "#{MacOS.active_developer_dir}/usr/bin/xcodebuild"
    path = MacOS::Xcode.bundle_path
    path = '/Developer' if path.nil? or not path.directory?
    t.cmd.doctor.xcode_select_path_invalid(path)
  end
end

def check_user_path_1
  $seen_prefix_bin = false
  $seen_prefix_sbin = false

  out = nil

  paths.each do |p|
    case p
    when '/usr/bin'
      unless $seen_prefix_bin
        # only show the doctor message if there are any conflicts
        # rationale: a default install should not trigger any brew doctor messages
        conflicts = Dir["#{HOMEBREW_PREFIX}/bin/*"].
            map{ |fn| File.basename fn }.
            select{ |bn| File.exist? "/usr/bin/#{bn}" }

        if conflicts.size > 0
          out = t.cmd.doctor.user_path_out_of_order("#{HOMEBREW_PREFIX}/bin",
                                                    conflicts * "\n                ")
        end
      end
    when "#{HOMEBREW_PREFIX}/bin"
      $seen_prefix_bin = true
    when "#{HOMEBREW_PREFIX}/sbin"
      $seen_prefix_sbin = true
    end
  end
  out
end

def check_user_path_2
  unless $seen_prefix_bin
    t.cmd.doctor.user_path_has_no_homebrew_bin("#{HOMEBREW_PREFIX}/bin")
  end
end

def check_user_path_3
  # Don't complain about sbin not being in the path if it doesn't exist
  sbin = (HOMEBREW_PREFIX+'sbin')
  if sbin.directory? and sbin.children.length > 0
    unless $seen_prefix_sbin
      t.cmd.doctor.user_path_has_no_homebrew_sbin("#{HOMEBREW_PREFIX}/sbin")
    end
  end
end

def check_user_curlrc
  if %w[CURL_HOME HOME].any?{|key| ENV[key] and File.exist? "#{ENV[key]}/.curlrc" }
    t.cmd.doctor.user_curlrc_exists
  end
end

def check_which_pkg_config
  binary = which 'pkg-config'
  return if binary.nil?

  mono_config = Pathname.new("/usr/bin/pkg-config")
  if mono_config.exist? && mono_config.realpath.to_s.include?("Mono.framework")
    t.cmd.doctor.non_homebrew_pkgconfig_mono(mono_config.realpath)
  elsif binary.to_s != "#{HOMEBREW_PREFIX}/bin/pkg-config"
    t.cmd.doctor.non_homebrew_pkgconfig(binary)
  end
end

def check_for_gettext
  find_relative_paths("lib/libgettextlib.dylib",
                      "lib/libintl.dylib",
                      "include/libintl.h")

  return if @found.empty?

  # Our gettext formula will be caught by check_linked_keg_only_brews
  f = Formulary.factory("gettext") rescue nil
  return if f and f.linked_keg.directory? and @found.all? do |path|
    Pathname.new(path).realpath.to_s.start_with? "#{HOMEBREW_CELLAR}/gettext"
  end

  s = t.cmd.doctor.non_homebrew_gettext
  inject_file_list(@found, s)
end

def check_for_iconv
  unless find_relative_paths("lib/libiconv.dylib", "include/iconv.h").empty?
    if (f = Formulary.factory("libiconv") rescue nil) and f.linked_keg.directory?
      if not f.keg_only?
        t.cmd.doctor.libiconv_formula_linked
      else
        # NOOP because: check_for_linked_keg_only_brews
      end
    else
      s = t.cmd.doctor.libiconv_not_in_usr
      inject_file_list(@found, s)
    end
  end
end

def check_for_config_scripts
  return unless HOMEBREW_CELLAR.exist?
  real_cellar = HOMEBREW_CELLAR.realpath

  config_scripts = []

  whitelist = %W[/usr/bin /usr/sbin /usr/X11/bin /usr/X11R6/bin /opt/X11/bin #{HOMEBREW_PREFIX}/bin #{HOMEBREW_PREFIX}/sbin]
  whitelist.map! { |d| d.downcase }

  paths.each do |p|
    next if whitelist.include? p.downcase
    next if p =~ %r[^(#{real_cellar.to_s}|#{HOMEBREW_CELLAR.to_s})] if real_cellar

    configs = Dir["#{p}/*-config"]
    # puts "#{p}\n    #{configs * ' '}" unless configs.empty?
    config_scripts << [p, configs.map { |c| File.basename(c) }] unless configs.empty?
  end

  unless config_scripts.empty?
    s = t.cmd.doctor.stray_config_scripts
    config_scripts.each do |dir, files|
      files.each { |fn| s << "    #{dir}/#{fn}\n" }
    end
    s
  end
end

def check_DYLD_vars
  found = ENV.keys.grep(/^DYLD_/)
  unless found.empty?
    s = t.cmd.doctor.dyld_vars_are_set
    s << found.map { |e| t.cmd.doctor.dyld_vars_are_set_2(e, ENV.fetch(e)) }.join
    if found.include? 'DYLD_INSERT_LIBRARIES'
      s += t.cmd.doctor.dyld_vars_have_go_conflict
    end
    s
  end
end

def check_for_symlinked_cellar
  return unless HOMEBREW_CELLAR.exist?
  if HOMEBREW_CELLAR.symlink?
    t.cmd.doctor.symlinked_cellar_found(HOMEBREW_CELLAR, HOMEBREW_CELLAR.realpath)
  end
end

def check_for_multiple_volumes
  return unless HOMEBREW_CELLAR.exist?
  volumes = Volumes.new

  # Find the volumes for the TMP folder & HOMEBREW_CELLAR
  real_cellar = HOMEBREW_CELLAR.realpath

  tmp = Pathname.new with_system_path { `mktemp -d #{HOMEBREW_TEMP}/homebrew-brew-doctor-XXXXXX` }.strip
  real_temp = tmp.realpath.parent

  where_cellar = volumes.which real_cellar
  where_temp = volumes.which real_temp

  Dir.delete tmp

  unless where_cellar == where_temp
    t.cmd.doctor.cellar_and_temp_not_same_vol
  end
end

def check_filesystem_case_sensitive
  volumes = Volumes.new
  case_sensitive_vols = [HOMEBREW_PREFIX, HOMEBREW_REPOSITORY, HOMEBREW_CELLAR, HOMEBREW_TEMP].select do |dir|
    # We select the dir as being case-sensitive if either the UPCASED or the
    # downcased variant is missing.
    # Of course, on a case-insensitive fs, both exist because the os reports so.
    # In the rare situation when the user has indeed a downcased and an upcased
    # dir (e.g. /TMP and /tmp) this check falsely thinks it is case-insensitive
    # but we don't care beacuse: 1. there is more than one dir checked, 2. the
    # check is not vital and 3. we would have to touch files otherwise.
    upcased = Pathname.new(dir.to_s.upcase)
    downcased = Pathname.new(dir.to_s.downcase)
    dir.exist? && !(upcased.exist? && downcased.exist?)
  end.map { |case_sensitive_dir| volumes.get_mounts(case_sensitive_dir) }.uniq
  return if case_sensitive_vols.empty?
  t.cmd.doctor.filesystem_case_sensitive(case_sensitive_vols.join(","))
end

def __check_git_version
  # https://help.github.com/articles/https-cloning-errors
  `git --version`.chomp =~ /git version ((?:\d+\.?)+)/

  if $1 and Version.new($1) < Version.new("1.7.10")
    t.cmd.doctor.git_outdated
  end
end

def check_for_git
  if git?
    __check_git_version
  else
    t.cmd.doctor.git_not_found
  end
end

def check_git_newline_settings
  return unless git?

  autocrlf = `git config --get core.autocrlf`.chomp

  if autocrlf == 'true'
    t.cmd.doctor.git_autocrlf_settings(autocrlf)
  end
end

def check_git_origin
  return unless git? && (HOMEBREW_REPOSITORY/'.git').exist?

  HOMEBREW_REPOSITORY.cd do
    origin = `git config --get remote.origin.url`.strip

    if origin.empty?
      t.cmd.doctor.git_remote_no_origin(HOMEBREW_REPOSITORY)
    elsif origin !~ /(mxcl|Homebrew)\/homebrew(\.git)?$/
      t.cmd.doctor.git_remote_origin_suspect(origin)
    end
  end
end

def check_for_autoconf
  return unless MacOS::Xcode.provides_autotools?

  autoconf = which('autoconf')
  safe_autoconfs = %w[/usr/bin/autoconf /Developer/usr/bin/autoconf]
  unless autoconf.nil? or safe_autoconfs.include? autoconf.to_s
    t.cmd.doctor.autoconf_xcode(autoconf)
  end
end

def __check_linked_brew f
  links_found = []

  prefix = f.prefix

  prefix.find do |src|
    next if src == prefix
    dst = HOMEBREW_PREFIX + src.relative_path_from(prefix)

    next if !dst.symlink? || !dst.exist? || src != dst.resolved_path

    if src.directory?
      Find.prune
    else
      links_found << dst
    end
  end

  return links_found
end

def check_for_linked_keg_only_brews
  return unless HOMEBREW_CELLAR.exist?

  warnings = Hash.new

  Formula.each do |f|
    next unless f.keg_only? and f.installed?
    links = __check_linked_brew f
    warnings[f.name] = links unless links.empty?
  end

  unless warnings.empty?
    s = t.cmd.doctor.keg_only_formula_linked
    warnings.each_key { |f| s << "    #{f}\n" }
    s
  end
end

def check_for_other_frameworks
  # Other frameworks that are known to cause problems when present
  %w{expat.framework libexpat.framework}.
    map{ |frmwrk| "/Library/Frameworks/#{frmwrk}" }.
    select{ |frmwrk| File.exist? frmwrk }.
    map { |frmwrk| t.cmd.doctor.other_framework_detected(frmwrk) }.join
end

def check_tmpdir
  tmpdir = ENV['TMPDIR']
  t.cmd.doctor.tmpdir_doesnt_exist(tmpdir.inspect) unless tmpdir.nil? or File.directory? tmpdir
end

def check_missing_deps
  return unless HOMEBREW_CELLAR.exist?
  missing = Set.new
  Homebrew.missing_deps(Formula.installed).each_value do |deps|
    missing.merge(deps)
  end

  if missing.any?
    t.cmd.doctor.missing_deps(missing.sort_by(&:name) * " ")
  end
end

def check_git_status
  return unless git?
  HOMEBREW_REPOSITORY.cd do
    unless `git status --untracked-files=all --porcelain -- Library/Homebrew/ 2>/dev/null`.chomp.empty?
      t.cmd.doctor.uncommitted_mods(HOMEBREW_LIBRARY)
    end
  end
end

def check_git_ssl_verify
  if MacOS.version <= :leopard && !ENV['GIT_SSL_NO_VERIFY']
    t.cmd.doctor.osx_libcurl_outdated(MacOS.version)
  end
end

def check_for_enthought_python
  if which "enpkg"
    t.cmd.doctor.enthought_python_in_path
  end
end

def check_for_library_python
  if File.exist?("/Library/Frameworks/Python.framework")
    t.cmd.doctor.python_in_library_frameworks
  end
end

def check_for_old_homebrew_share_python_in_path
  s = ''
  ['', '3'].map do |suffix|
    if paths.include?((HOMEBREW_PREFIX/"share/python#{suffix}").to_s)
      s += t.cmd.doctor.old_share_python_in_path(HOMEBREW_PREFIX, suffix)
    end
  end
  unless s.empty?
    s += t.cmd.doctor.old_share_python_in_path_more(HOMEBREW_PREFIX)
  end
end

def check_for_bad_python_symlink
  return unless which "python"
  `python -V 2>&1` =~ /Python (\d+)\./
  # This won't be the right warning if we matched nothing at all
  return if $1.nil?
  unless $1 == "2"
    t.cmd.doctor.python_bad_symlink("python#$1")
  end
end

def check_for_non_prefixed_coreutils
  gnubin = "#{Formulary.factory('coreutils').prefix}/libexec/gnubin"
  if paths.include? gnubin
    t.cmd.doctor.non_prefixed_coreutils if paths.include? gnubin
  end
end

def check_for_non_prefixed_findutils
  default_names = Tab.for_name('findutils').include? 'default-names'
  t.cmd.doctor.non_prefixed_findutils if default_names
end

def check_for_pydistutils_cfg_in_home
  if File.exist? "#{ENV['HOME']}/.pydistutils.cfg"
    t.cmd.doctor.pydistutils_cfg_in_home
  end
end

def check_for_outdated_homebrew
  return unless git?
  HOMEBREW_REPOSITORY.cd do
    if File.directory? ".git"
      local = `git rev-parse -q --verify refs/remotes/origin/master`.chomp
      remote = /^([a-f0-9]{40})/.match(`git ls-remote origin refs/heads/master 2>/dev/null`)
      if remote.nil? || local == remote[0]
        return
      end
    end

    timestamp = if File.directory? ".git"
      `git log -1 --format="%ct" HEAD`.to_i
    else
      HOMEBREW_LIBRARY.mtime.to_i
    end

    t.cmd.doctor.homebrew_is_outdated if Time.now.to_i - timestamp > 60 * 60 * 24
  end
end

def check_for_unlinked_but_not_keg_only
  return unless HOMEBREW_CELLAR.exist?
  unlinked = HOMEBREW_CELLAR.children.reject do |rack|
    if not rack.directory?
      true
    elsif not (HOMEBREW_REPOSITORY/"Library/LinkedKegs"/rack.basename).directory?
      begin
        Formulary.factory(rack.basename.to_s).keg_only?
      rescue FormulaUnavailableError
        false
      end
    else
      true
    end
  end.map{ |pn| pn.basename }

  if not unlinked.empty?
    t.cmd.doctor.unlinked_kegs_in_cellar(unlinked * "\n        ")
  end
end

  def check_xcode_license_approved
    # If the user installs Xcode-only, they have to approve the
    # license or no "xc*" tool will work.
    if `/usr/bin/xcrun clang 2>&1` =~ /license/ and not $?.success?
      t.cmd.doctor.xcode_license_not_agreed
    end
  end

  def check_for_latest_xquartz
    return unless MacOS::XQuartz.version
    return if MacOS::XQuartz.provided_by_apple?

    installed_version = Version.new(MacOS::XQuartz.version)
    latest_version    = Version.new(MacOS::XQuartz.latest_version)

    return if installed_version >= latest_version

    t.cmd.doctor.xquartz_is_outdated(installed_version, latest_version)
  end

  def check_for_old_env_vars
    t.cmd.doctor.old_env_var_homebrew_keep_info if ENV["HOMEBREW_KEEP_INFO"]
  end

  def all
    methods.map(&:to_s).grep(/^check_/)
  end
end # end class Checks

module Homebrew
  def doctor
    checks = Checks.new

    if ARGV.include? '--list-checks'
      puts checks.all.sort
      exit
    end

    inject_dump_stats(checks) if ARGV.switch? 'D'

    if ARGV.named.empty?
      methods = checks.all.sort
      methods << "check_for_linked_keg_only_brews" << "check_for_outdated_homebrew"
      methods = methods.reverse.uniq.reverse
    else
      methods = ARGV.named
    end

    first_warning = true
    methods.each do |method|
      out = checks.send(method)
      unless out.nil? or out.empty?
        if first_warning
          puts <<-EOS.undent
            #{Tty.white}Please note that these warnings are just used to help the Homebrew maintainers
            with debugging if you file an issue. If everything you use Homebrew for is
            working fine: please don't worry and just ignore them. Thanks!#{Tty.reset}
          EOS
        end

        puts
        opoo out
        Homebrew.failed = true
        first_warning = false
      end
    end
  end

  def inject_dump_stats checks
    checks.extend Module.new {
      def send(method, *)
        time = Time.now
        super
      ensure
        $times[method] = Time.now - time
      end
    }
    $times = {}
    at_exit {
      puts $times.sort_by{|k, v| v }.map{|k, v| "#{k}: #{v}"}
    }
  end
end
