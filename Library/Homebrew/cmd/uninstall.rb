require 'keg'
require 'formula'

module Homebrew
  def uninstall
    raise KegUnspecifiedError if ARGV.named.empty?

    if not ARGV.force?
      ARGV.kegs.each do |keg|
        keg.lock do
          puts t('cmd.uninstall.uninstalling', :name => keg, :abv => keg.abv)
          keg.unlink
          keg.uninstall
          rack = keg.rack
          rm_pin rack
          if rack.directory?
            versions = rack.subdirs.map(&:basename)
            puts t('cmd.uninstall.still_installed',
                   :name => keg.name,
                   :versions => versions.join(t('cmd.uninstall.comma')),
                   :count => versions.length)
            puts t('cmd.uninstall.remove_all', :name => keg.name)
          end
        end
      end
    else
      ARGV.named.each do |name|
        name = Formulary.canonical_name(name)
        rack = HOMEBREW_CELLAR/name

        if rack.directory?
          puts t('cmd.uninstall.uninstalling', :name => name, :abv => rack.abv)
          rack.subdirs.each do |d|
            keg = Keg.new(d)
            keg.unlink
            keg.uninstall
          end
        end

        rm_pin rack
      end
    end
  rescue MultipleVersionsInstalledError => e
    ofail e
    puts t('cmd.uninstall.must_remove_all', :name => e.name)
  end

  def rm_pin rack
    Formulary.from_rack(rack).unpin rescue nil
  end
end
