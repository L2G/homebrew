require 'formula_installer'
require 'hardware'
require 'blacklist'

module Homebrew extend self
  def install
    raise FormulaUnspecifiedError if ARGV.named.empty?

    {
      'gcc' => 'gcc-4.2',
      'llvm' => 'llvm-gcc',
      'clang' => 'clang'
    }.each_pair do |old, new|
      opt = "--use-#{old}"
      opoo t.cmd.install.option_use_deprecated(opt.inspect, new) if ARGV.include? opt
    end

    if ARGV.include? '--head'
      raise t.cmd.install.head_uppercase
    end

    ARGV.named.each do |name|
      # if a formula has been tapped ignore the blacklisting
      unless Formula.path(name).file?
        msg = blacklisted? name
        raise t.cmd.install.formula_blacklisted(name, msg) if msg
      end
      if not File.exist? name and name =~ HOMEBREW_TAP_FORMULA_REGEX then
        require 'cmd/tap'
        install_tap $1, $2
      end
    end unless ARGV.force?

    perform_preinstall_checks

    begin
      ARGV.formulae.each { |f| install_formula(f) }
    rescue FormulaUnavailableError => e
      ofail e.message
      require 'cmd/search'
      puts t.cmd.install.searching_taps
      puts_columns(search_taps(query_regexp(e.name)))
    end
  end

  def check_ppc
    case Hardware::CPU.type
    when :ppc, :dunno
      abort t.cmd.install.unsupported_arch
    end
  end

  def check_writable_install_location
    raise t.cmd.install.cannot_write_dir(HOMEBREW_CELLAR) if HOMEBREW_CELLAR.exist? and not HOMEBREW_CELLAR.writable_real?
    raise t.cmd.install.cannot_write_dir(HOMEBREW_PREFIX) unless HOMEBREW_PREFIX.writable_real? or HOMEBREW_PREFIX.to_s == '/usr/local'
  end

  def check_xcode
    require 'cmd/doctor'
    checks = Checks.new
    %w[
      check_for_installed_developer_tools
      check_xcode_license_approved
      check_for_osx_gcc_installer
    ].each do |check|
      out = checks.send(check)
      opoo out unless out.nil?
    end
  end

  def check_macports
    unless MacOS.macports_or_fink.empty?
      opoo t.cmd.install.macports_or_fink_installed_1
      puts t.cmd.install.macports_or_fink_installed_2
    end
  end

  def check_cellar
    FileUtils.mkdir_p HOMEBREW_CELLAR if not File.exist? HOMEBREW_CELLAR
  rescue
    raise t.cmd.install.cannot_create_dir(HOMEBREW_CELLAR, HOMEBREW_CELLAR.parent)
  end

  def perform_preinstall_checks
    check_ppc
    check_writable_install_location
    check_xcode
    check_cellar
  end

  def install_formula f
    fi = FormulaInstaller.new(f)
    fi.options             = f.build.used_options
    fi.ignore_deps         = ARGV.ignore_deps? || ARGV.interactive?
    fi.only_deps           = ARGV.only_deps?
    fi.build_bottle        = ARGV.build_bottle?
    fi.build_from_source   = ARGV.build_from_source?
    fi.force_bottle        = ARGV.force_bottle?
    fi.interactive         = ARGV.interactive?
    fi.interactive       &&= :git if ARGV.flag? "--git"
    fi.verbose             = ARGV.verbose?
    fi.verbose           &&= :quieter if ARGV.quieter?
    fi.debug               = ARGV.debug?
    fi.prelude
    fi.install
    fi.caveats
    fi.finish
  rescue FormulaInstallationAlreadyAttemptedError
    # We already attempted to install f as part of the dependency tree of
    # another formula. In that case, don't generate an error, just move on.
  rescue FormulaAlreadyInstalledError => e
    opoo e.message
  rescue CannotInstallFormulaError => e
    ofail e.message
    check_macports
  end
end
