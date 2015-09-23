require "blacklist"
require "cmd/doctor"
require "cmd/search"
require "cmd/tap"
require "formula_installer"
require "hardware"

module Homebrew
  def install
    raise FormulaUnspecifiedError if ARGV.named.empty?

    if ARGV.include? "--head"
      raise t('cmd.install.head_uppercase')
    end

    ARGV.named.each do |name|
      if !File.exist?(name) && (name !~ HOMEBREW_CORE_FORMULA_REGEX) \
              && (name =~ HOMEBREW_TAP_FORMULA_REGEX || name =~ HOMEBREW_CASK_TAP_FORMULA_REGEX)
        install_tap $1, $2
      end
    end unless ARGV.force?

    begin
      formulae = []

      if ARGV.casks.any?
        brew_cask = Formulary.factory("brew-cask")
        install_formula(brew_cask) unless brew_cask.installed?
        args = []
        args << "--force" if ARGV.force?
        args << "--debug" if ARGV.debug?
        args << "--verbose" if ARGV.verbose?

        ARGV.casks.each do |c|
          cmd = "brew", "cask", "install", c, *args
          ohai cmd.join " "
          system(*cmd)
        end
      end

      # if the user's flags will prevent bottle only-installations when no
      # developer tools are available, we need to stop them early on
      FormulaInstaller.prevent_build_flags unless MacOS.has_apple_developer_tools?

      ARGV.formulae.each do |f|
        # head-only without --HEAD is an error
        if !ARGV.build_head? && f.stable.nil? && f.devel.nil?
          raise t("cmd.install.head_only_formula", :name => f.full_name)
        end

        # devel-only without --devel is an error
        if !ARGV.build_devel? && f.stable.nil? && f.head.nil?
          raise t("cmd.install.devel_only_formula", :name => f.full_name)
        end

        if ARGV.build_stable? && f.stable.nil?
          raise t("cmd.install.no_stable_download", :name => f.full_name)
        end

        # --HEAD, fail with no head defined
        if ARGV.build_head? && f.head.nil?
          raise t("cmd.install.no_head_defined", :name => f.full_name)
        end

        # --devel, fail with no devel defined
        if ARGV.build_devel? && f.devel.nil?
          raise t("cmd.install.no_devel_defined", :name => f.full_name)
        end

        if f.installed?
          if f.linked_keg.symlink? || f.keg_only?
            opoo t("cmd.install.already_installed",
                   :name => f.full_name,
                   :version => f.installed_version)
          else
            opoo t("cmd.install.already_installed_not_linked",
                   :name => f.full_name,
                   :version => f.installed_version)
          end
        elsif f.oldname && (dir = HOMEBREW_CELLAR/f.oldname).exist? && !dir.subdirs.empty? \
            && f.tap == Tab.for_keg(dir.subdirs.first).tap && !ARGV.force?
          # Check if the formula we try to install is the same as installed
          # but not migrated one. If --force passed then install anyway.
          opoo "#{f.oldname} already installed, it's just not migrated"
          puts "You can migrate formula with `brew migrate #{f}`"
          puts "Or you can force install it with `brew install #{f} --force`"
        else
          formulae << f
        end
      end

      perform_preinstall_checks

      formulae.each { |f| install_formula(f) }
    rescue FormulaUnavailableError => e
      if (blacklist = blacklisted?(e.name))
        ofail "#{e.message}\n#{blacklist}"
      else
        ofail e.message
        query = query_regexp(e.name)
        ohai t('cmd.install.searching_formulae')
        puts_columns(search_formulae(query))
        ohai t('cmd.install.searching_taps')
        puts_columns(search_taps(query))

        # If they haven't updated in 48 hours (172800 seconds), that
        # might explain the error
        master = HOMEBREW_REPOSITORY/".git/refs/heads/master"
        if master.exist? && (Time.now.to_i - File.mtime(master).to_i) > 172800
          ohai "You haven't updated Homebrew in a while."
          puts <<-EOS.undent
            A formula for #{e.name} might have been added recently.
            Run `brew update` to get the latest Homebrew updates!
          EOS
        end
      end
    end
  end

  def check_ppc
    case Hardware::CPU.type
    when :ppc, :dunno
      abort t('cmd.install.unsupported_arch')
    end
  end

  def check_writable_install_location
    raise t('cmd.install.cannot_write_dir', :path => HOMEBREW_CELLAR) if HOMEBREW_CELLAR.exist? && !HOMEBREW_CELLAR.writable_real?
    raise t('cmd.install.cannot_write_dir', :path => HOMEBREW_PREFIX) unless HOMEBREW_PREFIX.writable_real? || HOMEBREW_PREFIX.to_s == "/usr/local"
  end

  def check_xcode
    checks = Checks.new
    %w[
      check_for_unsupported_osx
      check_for_bad_install_name_tool
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
      opoo t('cmd.install.macports_or_fink_installed_1')
      puts t('cmd.install.macports_or_fink_installed_2')
    end
  end

  def check_cellar
    FileUtils.mkdir_p HOMEBREW_CELLAR unless File.exist? HOMEBREW_CELLAR
  rescue
    raise t('cmd.install.cannot_create_dir',
            :path => HOMEBREW_CELLAR,
            :parent => HOMEBREW_CELLAR.parent)
  end

  def perform_preinstall_checks
    check_ppc
    check_writable_install_location
    check_xcode if MacOS.has_apple_developer_tools?
    check_cellar
  end

  def install_formula(f)
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
