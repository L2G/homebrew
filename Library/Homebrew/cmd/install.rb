require "blacklist"
require "cmd/doctor"
require "cmd/search"
require "cmd/tap"
require "formula_installer"
require "hardware"

module Homebrew
  def install
    raise FormulaUnspecifiedError if ARGV.named.empty?

    if ARGV.include? '--head'
      raise t.cmd.install.head_uppercase
    end

    ARGV.named.each do |name|
      # if a formula has been tapped ignore the blacklisting
      unless Formula.path(name).file?
        msg = blacklisted? name
        raise t.cmd.install.formula_blacklisted(name, msg) if msg
      end
      if !File.exist?(name) && (name =~ HOMEBREW_TAP_FORMULA_REGEX \
                                || name =~ HOMEBREW_CASK_TAP_FORMULA_REGEX)
        install_tap $1, $2
      end
    end unless ARGV.force?

    begin
      formulae = []

      if ARGV.casks.any?
        brew_cask = Formulary.factory("brew-cask")
        install_formula(brew_cask) unless brew_cask.installed?

        ARGV.casks.each do |c|
          cmd = "brew", "cask", "install", c
          ohai cmd.join " "
          system(*cmd)
        end
      end

      ARGV.formulae.each do |f|
        # Building head-only without --HEAD is an error
        if not ARGV.build_head? and f.stable.nil?
          raise <<-EOS.undent
          #{f.name} is a head-only formula
          Install with `brew install --HEAD #{f.name}`
          EOS
        end

        # Building stable-only with --HEAD is an error
        if ARGV.build_head? and f.head.nil?
          raise "No head is defined for #{f.name}"
        end

        if f.installed?
          msg = "#{f.name}-#{f.installed_version} already installed"
          msg << ", it's just not linked" unless f.linked_keg.symlink? or f.keg_only?
          opoo msg
        else
          formulae << f
        end
      end

      perform_preinstall_checks

      formulae.each { |f| install_formula(f) }
    rescue FormulaUnavailableError => e
      ofail e.message
      query = query_regexp(e.name)
      puts t.cmd.install.searching_formulae
      puts_columns(search_formulae(query))
      puts t.cmd.install.searching_taps
      puts_columns(search_taps(query))
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
    checks = Checks.new
    %w[
      check_for_installed_developer_tools
      check_xcode_license_approved
      check_for_osx_gcc_installer
      check_for_bad_install_name_tool
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
    f.print_tap_action

    fi = FormulaInstaller.new(f)
    fi.options             = f.build.used_options
    fi.ignore_deps         = ARGV.ignore_deps?
    fi.only_deps           = ARGV.only_deps?
    fi.build_bottle        = ARGV.build_bottle?
    fi.build_from_source   = ARGV.build_from_source?
    fi.force_bottle        = ARGV.force_bottle?
    fi.interactive         = ARGV.interactive?
    fi.git                 = ARGV.git?
    fi.verbose             = ARGV.verbose?
    fi.quieter             = ARGV.quieter?
    fi.debug               = ARGV.debug?
    fi.prelude
    fi.install
    fi.caveats
    fi.finish
  rescue FormulaInstallationAlreadyAttemptedError
    # We already attempted to install f as part of the dependency tree of
    # another formula. In that case, don't generate an error, just move on.
  rescue CannotInstallFormulaError => e
    ofail e.message
  rescue BuildError
    check_macports
    raise
  end
end
