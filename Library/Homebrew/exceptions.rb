class UsageError < RuntimeError; end
class FormulaUnspecifiedError < UsageError; end
class KegUnspecifiedError < UsageError; end

class MultipleVersionsInstalledError < RuntimeError
  attr_reader :name

  def initialize(name)
    @name = name
    super t("exceptions.multiple_versions_installed_error", :name => name)
  end
end

class NotAKegError < RuntimeError; end

class NoSuchKegError < RuntimeError
  attr_reader :name

  def initialize(name)
    @name = name
    super t("exceptions.no_such_keg_error",
            :cellar => HOMEBREW_CELLAR,
            :name => name)

  end
end

class FormulaValidationError < StandardError
  attr_reader :attr

  def initialize(attr, value)
    @attr = attr
    super t("exceptions.formula_validation_error",
            :attr => attr,
            :value => value.inspect)
  end
end

class FormulaSpecificationError < StandardError; end

class FormulaUnavailableError < RuntimeError
  attr_reader :name
  attr_accessor :dependent

  def initialize(name)
    @name = name
  end

  # TODO (i18n): This is vestigial as far as the translations go, but I'm
  # leaving it in just in case some hapless outside caller is using it
  def dependent_s
  end

  def to_s
    if dependent and dependent != name
      t("exceptions.formula_unavailable_error_w_dependent",
        :name => name,
        :dependent => dependent)
    else
      t("exceptions.formula_unavailable_error", :name => name)
    end
  end
end

class TapFormulaUnavailableError < FormulaUnavailableError
  attr_reader :tap, :user, :repo

  def initialize(tap, name)
    @tap = tap
    @user = tap.user
    @repo = tap.repo
    super "#{tap}/#{name}"
  end

  def to_s
    s = super
    s += "\n" + t("exceptions.tap_and_try_again", :tap => tap) unless tap.installed?
    s
  end
end

class TapFormulaAmbiguityError < RuntimeError
  attr_reader :name, :paths, :formulae

  def initialize(name, paths)
    @name = name
    @paths = paths
    @formulae = paths.map do |path|
      path.to_s =~ HOMEBREW_TAP_PATH_REGEX
      "#{$1}/#{$2.sub("homebrew-", "")}/#{path.basename(".rb")}"
    end

    super <<-EOS.undent
      Formulae found in multiple taps: #{formulae.map { |f| "\n       * #{f}" }.join}

      Please use the fully-qualified name e.g. #{formulae.first} to refer the formula.
    EOS
  end
end

class TapFormulaWithOldnameAmbiguityError < RuntimeError
  attr_reader :name, :possible_tap_newname_formulae, :taps

  def initialize(name, possible_tap_newname_formulae)
    @name = name
    @possible_tap_newname_formulae = possible_tap_newname_formulae

    @taps = possible_tap_newname_formulae.map do |newname|
      newname =~ HOMEBREW_TAP_FORMULA_REGEX
      "#{$1}/#{$2}"
    end

    super <<-EOS.undent
      Formulae with '#{name}' old name found in multiple taps: #{taps.map { |t| "\n       * #{t}" }.join}

      Please use the fully-qualified name e.g. #{taps.first}/#{name} to refer the formula or use its new name.
    EOS
  end
end

class TapUnavailableError < RuntimeError
  attr_reader :name

  def initialize(name)
    @name = name

    super <<-EOS.undent
      No available tap #{name}.
    EOS
  end
end

class TapPinStatusError < RuntimeError
  attr_reader :name, :pinned

  def initialize(name, pinned)
    @name = name
    @pinned = pinned

    super pinned ? "#{name} is already pinned." : "#{name} is already unpinned."
  end
end

class OperationInProgressError < RuntimeError
  def initialize(name)
    message = t("exceptions.operation_in_progress_error", :name => name)
    super message
  end
end

class CannotInstallFormulaError < RuntimeError; end

class FormulaInstallationAlreadyAttemptedError < RuntimeError
  def initialize(formula)
    super t("exceptions.formula_installation_already_attempted_error",
            :name => formula.full_name)
  end
end

class UnsatisfiedRequirements < RuntimeError
  def initialize(reqs)
    super t("exceptions.unsatisfied_requirements", :count => reqs.length)
  end
end

class FormulaConflictError < RuntimeError
  attr_reader :formula, :conflicts

  def initialize(formula, conflicts)
    @formula = formula
    @conflicts = conflicts
    super message
  end

  def conflict_message(conflict)
    # XXX (i18n): I predict we will have to do this a different way...
    if conflict.reason
      t("exceptions.formula_conflict_error_line_item_w_reason",
        :name => conflict.name,
        :reason => conflict.reason)
    else
      t("exceptions.formula_conflict_error_line_item", :name => conflict.name)
    end
  end

  def message
    t("exceptions.formula_conflict_error",
      :error_intro => t("exceptions.formula_conflict_error_intro",
                        :name => formula.full_name,
                        :count => conflicts.length),
      :conflict_list => conflicts.map { |c| conflict_message(c) }.join("\n") + "\n",
      :conflicts => (conflicts.map(&:name)*" "),
      :homebrew_prefix => HOMEBREW_PREFIX)
  end
end

class BuildError < RuntimeError
  attr_reader :formula, :env

  def initialize(formula, cmd, args, env)
    @formula = formula
    @env = env
    args = args.map { |arg| arg.to_s.gsub " ", "\\ " }.join(" ")
    super t("exceptions.build_error.failed_executing",
            :cmd => cmd,
            :args => args)
  end

  def issues
    @issues ||= fetch_issues
  end

  def fetch_issues
    GitHub.issues_for_formula(formula.name)
  rescue GitHub::RateLimitExceededError => e
    opoo e.message
    []
  end

  def dump
    if !ARGV.verbose?
      puts
      puts t("exceptions.build_error.read_this",
             :read_this_color => Tty.red,
             :url => OS::ISSUES_URL,
             :url_color => Tty.em,
             :reset_color => Tty.reset)
      if formula.tap?
        case formula.tap
        when "homebrew/homebrew-boneyard"
          puts t("exceptions.build_error.moved_to_boneyard",
                 :formula => formula)
        else
          puts t("exceptions.build_error.report_tap_issue",
                 :tap => formula.tap)
        end
      end
    else
      require "cmd/config"
      require "cmd/--env"

      ohai t("exceptions.build_error.dump_heading_formula")
      puts t("exceptions.build_error.dump_tap", :tap => formula.tap) if formula.tap?
      puts t("exceptions.build_error.dump_path", :path => formula.path)

      ohai t("exceptions.build_error.dump_heading_configuration")
      Homebrew.dump_verbose_config

      ohai t("exceptions.build_error.dump_heading_env")
      Homebrew.dump_build_env(env)
      puts
      onoe t("exceptions.build_error.formula_did_not_build",
             :name => formula.full_name,
             :version => formula.version)
      unless (logs = Dir["#{formula.logs}/*"]).empty?
        puts t("exceptions.build_error.dump_heading_logs")
        logs.each do |log_entry|
          puts t("exceptions.build_error.logs_line_item",
                 :log_entry => log_entry)
        end
      end
    end
    puts
    unless RUBY_VERSION < "1.8.7" || issues.empty?
      puts t("exceptions.build_error.refer_to_issues")
      issues.each do |i|
        puts t("exceptions.build_error.issues_line_item",
               :title => i['title'],
               :url => i['html_url'])
      end
    end

    if MacOS.version >= "10.11"
      require "cmd/doctor"
      opoo Checks.new.check_for_unsupported_osx
    end
  end
end

# raised by FormulaInstaller.check_dependencies_bottled and
# FormulaInstaller.install if the formula or its dependencies are not bottled
# and are being installed on a system without necessary build tools
class BuildToolsError < RuntimeError
  def initialize(formulae)
    if formulae.length > 1
      formula_text = "formulae"
      package_text = "binary packages"
    else
      formula_text = "formula"
      package_text = "a binary package"
    end

    if MacOS.version >= "10.10"
      xcode_text = <<-EOS.undent
        To continue, you must install Xcode from the App Store,
        or the CLT by running:
          xcode-select --install
      EOS
    elsif MacOS.version == "10.9"
      xcode_text = <<-EOS.undent
        To continue, you must install Xcode from:
          https://developer.apple.com/downloads/
        or the CLT by running:
          xcode-select --install
      EOS
    elsif MacOS.version >= "10.7"
      xcode_text = <<-EOS.undent
        To continue, you must install Xcode or the CLT from:
          https://developer.apple.com/downloads/
      EOS
    else
      xcode_text = <<-EOS.undent
        To continue, you must install Xcode from:
          https://developer.apple.com/xcode/downloads/
      EOS
    end

    super <<-EOS.undent
      The following #{formula_text}:
        #{formulae.join(", ")}
      cannot be installed as a #{package_text} and must be built from source.
      #{xcode_text}
    EOS
  end
end

# raised by Homebrew.install, Homebrew.reinstall, and Homebrew.upgrade
# if the user passes any flags/environment that would case a bottle-only
# installation on a system without build tools to fail
class BuildFlagsError < RuntimeError
  def initialize(flags)
    if flags.length > 1
      flag_text = "flags"
      require_text = "require"
    else
      flag_text = "flag"
      require_text = "requires"
    end

    if MacOS.version >= "10.10"
      xcode_text = <<-EOS.undent
        or install Xcode from the App Store, or the CLT by running:
          xcode-select --install
      EOS
    elsif MacOS.version == "10.9"
      xcode_text = <<-EOS.undent
        or install Xcode from:
          https://developer.apple.com/downloads/
        or the CLT by running:
          xcode-select --install
      EOS
    elsif MacOS.version >= "10.7"
      xcode_text = <<-EOS.undent
        or install Xcode or the CLT from:
          https://developer.apple.com/downloads/
      EOS
    else
      xcode_text = <<-EOS.undent
        or install Xcode from:
          https://developer.apple.com/xcode/downloads/
      EOS
    end

    super <<-EOS.undent
      The following #{flag_text}:
        #{flags.join(", ")}
      #{require_text} building tools, but none are installed.
      Either remove the #{flag_text} to attempt bottle installation,
      #{xcode_text}
    EOS
  end
end

# raised by CompilerSelector if the formula fails with all of
# the compilers available on the user's system
class CompilerSelectionError < RuntimeError
  def initialize(formula)
    super t("exceptions.compiler_selection_error", :name => formula.full_name)
  end
end

# Raised in Resource.fetch
class DownloadError < RuntimeError
  def initialize(resource, cause)
    super t("exceptions.download_error",
            :resource => resource.download_name.inspect,
            :message => cause.message)
    set_backtrace(cause.backtrace)
  end
end

# raised in CurlDownloadStrategy.fetch
class CurlDownloadStrategyError < RuntimeError
  def initialize(url)
    case url
    when %r{^file://(.+)}
      super t("exceptions.curl_download_strategy_error_local_file", :file => $1)
    else
      super t("exceptions.curl_download_strategy_error_remote_url", :url => url)
    end
  end
end

# raised by safe_system in utils.rb
class ErrorDuringExecution < RuntimeError
  def initialize(cmd, args = [])
    args = args.map { |a| a.to_s.gsub " ", "\\ " }.join(" ")
    super t("exceptions.error_during_execution", :cmd => cmd, :args => args)
  end
end

# raised by Pathname#verify_checksum when "expected" is nil or empty
class ChecksumMissingError < ArgumentError; end

# raised by Pathname#verify_checksum when verification fails
class ChecksumMismatchError < RuntimeError
  attr_reader :expected, :hash_type

  def initialize(fn, expected, actual)
    @expected = expected
    @hash_type = expected.hash_type.to_s.upcase

    super t("exceptions.checksum_mismatch_error",
            :hash_type => @hash_type,
            :expected => expected,
            :actual => actual,
            :file => fn)
  end
end

class ResourceMissingError < ArgumentError
  def initialize(formula, resource)
    super t("exceptions.resource_missing_error",
            :formula => formula.full_name,
            :resource => resource.inspect)
  end
end

class DuplicateResourceError < ArgumentError
  def initialize(resource)
    super t("exceptions.duplicate_resource_error", :resource => resource.inspect)
  end
end

class BottleVersionMismatchError < RuntimeError
  def initialize(bottle_file, bottle_version, formula, formula_version)
    super <<-EOS.undent
      Bottle version mismatch
      Bottle: #{bottle_file} (#{bottle_version})
      Formula: #{formula.full_name} (#{formula_version})
    EOS
  end
end
