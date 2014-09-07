module HomebrewArgvExtension
  def named
    @named ||= self - options_only
  end

  def options_only
    select { |arg| arg.start_with?("-") }
  end

  def flags_only
    select { |arg| arg.start_with?("--") }
  end

  def formulae
    require "formula"
    @formulae ||= downcased_unique_named.map { |name| Formulary.factory(name, spec) }
  end

  def kegs
    require 'keg'
    require 'formula'
    @kegs ||= downcased_unique_named.collect do |name|
      canonical_name = Formulary.canonical_name(name)
      rack = HOMEBREW_CELLAR/canonical_name
      dirs = rack.directory? ? rack.subdirs : []

      raise NoSuchKegError.new(canonical_name) if dirs.empty?

      linked_keg_ref = HOMEBREW_LIBRARY.join("LinkedKegs", canonical_name)
      opt_prefix = HOMEBREW_PREFIX.join("opt", canonical_name)

      begin
        if opt_prefix.symlink? && opt_prefix.directory?
          Keg.new(opt_prefix.resolved_path)
        elsif linked_keg_ref.symlink? && linked_keg_ref.directory?
          Keg.new(linked_keg_ref.resolved_path)
        elsif dirs.length == 1
          Keg.new(dirs.first)
        elsif (prefix = Formulary.factory(canonical_name).prefix).directory?
          Keg.new(prefix)
        else
          raise MultipleVersionsInstalledError.new(canonical_name)
        end
      rescue FormulaUnavailableError
        raise t[:extend].argv.multiple_kegs(rack)
      end
    end
  end

  # self documenting perhaps?
  def include? arg
    @n=index arg
  end
  def next
    at @n+1 or raise UsageError
  end

  def value arg
    arg = find {|o| o =~ /--#{arg}=(.+)/}
    $1 if arg
  end

  def force?
    flag? '--force'
  end
  def verbose?
    flag? '--verbose' or !ENV['VERBOSE'].nil? or !ENV['HOMEBREW_VERBOSE'].nil?
  end
  def debug?
    flag? '--debug' or !ENV['HOMEBREW_DEBUG'].nil?
  end
  def quieter?
    flag? '--quieter'
  end
  def interactive?
    flag? '--interactive'
  end
  def one?
    flag? '--1'
  end
  def dry_run?
    include?('--dry-run') || switch?('n')
  end

  def homebrew_developer?
    include? '--homebrew-developer' or !ENV['HOMEBREW_DEVELOPER'].nil?
  end

  def ignore_deps?
    include? '--ignore-dependencies'
  end

  def only_deps?
    include? '--only-dependencies'
  end

  def json
    value 'json'
  end

  def build_head?
    include? '--HEAD'
  end

  def build_devel?
    include? '--devel'
  end

  def build_stable?
    not (build_head? or build_devel?)
  end

  def build_universal?
    include? '--universal'
  end

  # Request a 32-bit only build.
  # This is needed for some use-cases though we prefer to build Universal
  # when a 32-bit version is needed.
  def build_32_bit?
    include? '--32-bit'
  end

  def build_bottle?
    include? '--build-bottle' or !ENV['HOMEBREW_BUILD_BOTTLE'].nil?
  end

  def bottle_arch
    arch = value 'bottle-arch'
    arch.to_sym if arch
  end

  def build_from_source?
    switch?("s") || include?("--build-from-source") || !!ENV["HOMEBREW_BUILD_FROM_SOURCE"]
  end

  def flag? flag
    options_only.include?(flag) || switch?(flag[2, 1])
  end

  def force_bottle?
    include? '--force-bottle'
  end

  # eg. `foo -ns -i --bar` has three switches, n, s and i
  def switch? char
    return false if char.length > 1
    options_only.any? { |arg| arg[1, 1] != "-" && arg.include?(char) }
  end

  def usage
    require 'cmd/help'
    Homebrew.help_s
  end

  def cc
    value 'cc'
  end

  def env
    value 'env'
  end

  private

  def spec
    if include?("--HEAD")
      :head
    elsif include?("--devel")
      :devel
    else
      :stable
    end
  end

  def downcased_unique_named
    # Only lowercase names, not paths or URLs
    @downcased_unique_named ||= named.map do |arg|
      arg.include?("/") ? arg : arg.downcase
    end.uniq
  end
end
