require "cmd/install"
require "cmd/outdated"

module Homebrew
  def upgrade
    FormulaInstaller.prevent_build_flags unless MacOS.has_apple_developer_tools?

    Homebrew.perform_preinstall_checks

    if ARGV.named.empty?
      outdated = Homebrew.outdated_brews(Formula.installed)
      exit 0 if outdated.empty?
    elsif ARGV.named.any?
      outdated = Homebrew.outdated_brews(ARGV.resolved_formulae)

      (ARGV.resolved_formulae - outdated).each do |f|
        if f.rack.directory?
          version = f.rack.subdirs.map { |d| Keg.new(d).version }.max
          onoe t('cmd.upgrade.formula_version_already_installed',
                 :name => f.full_name,
                 :version => version)
        else
          onoe t('cmd.upgrade.formula_already_installed', :name => f.full_name)
        end
      end
      exit 1 if outdated.empty?
    end

    unless upgrade_pinned?
      pinned = outdated.select(&:pinned?)
      outdated -= pinned
    end

    unless outdated.empty?
      oh1 t('cmd.upgrade.upgrading_outdated_pkg', :count => outdated.length)
      puts outdated.map { |f|
        t('cmd.upgrade.formula_name_and_version',
          :name => f.full_name,
          :version => f.pkg_version)
      }.join(t('cmd.upgrade.list_join'))
    else
      oh1 t('cmd.upgrade.no_pkgs_to_upgrade')
    end

    unless upgrade_pinned? || pinned.empty?
      oh1 t('cmd.upgrade.not_upgrading_pinned_pkg', :count => pinned.length)
      puts pinned.map do |f|
        t('cmd.upgrade.formula_name_and_version',
          :name => f.full_name,
          :version => f.pkg_version)
      end.join(t('cmd.upgrade.list_join'))
    end

    outdated.each { |f| upgrade_formula(f) }
  end

  def upgrade_pinned?
    !ARGV.named.empty?
  end

  def upgrade_formula(f)
    outdated_keg = Keg.new(f.linked_keg.resolved_path) if f.linked_keg.directory?
    tab = Tab.for_formula(f)

    fi = FormulaInstaller.new(f)
    fi.options             = tab.used_options
    fi.build_bottle        = ARGV.build_bottle? || (!f.bottled? && tab.build_bottle?)
    fi.build_from_source   = ARGV.build_from_source?
    fi.verbose             = ARGV.verbose?
    fi.quieter             = ARGV.quieter?
    fi.debug               = ARGV.debug?
    fi.prelude

    oh1 t('cmd.upgrade.upgrading_formula', :name => f.full_name)

    # first we unlink the currently active keg for this formula otherwise it is
    # possible for the existing build to interfere with the build we are about to
    # do! Seriously, it happens!
    outdated_keg.unlink if outdated_keg

    fi.install
    fi.finish

    # If the formula was pinned, and we were force-upgrading it, unpin and
    # pin it again to get a symlink pointing to the correct keg.
    if f.pinned?
      f.unpin
      f.pin
    end
  rescue FormulaInstallationAlreadyAttemptedError
    # We already attempted to upgrade f as part of the dependency tree of
    # another formula. In that case, don't generate an error, just move on.
  rescue CannotInstallFormulaError => e
    ofail e
  rescue BuildError => e
    e.dump
    puts
    Homebrew.failed = true
  rescue DownloadError => e
    ofail e
  ensure
    # restore previous installation state if build failed
    outdated_keg.link if outdated_keg && !f.installed? rescue nil
  end
end
