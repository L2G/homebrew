class UsageError < RuntimeError; end
class FormulaUnspecifiedError < UsageError; end
class KegUnspecifiedError < UsageError; end

class MultipleVersionsInstalledError < RuntimeError
  attr_reader :name

  def initialize name
    @name = name
    super t("exceptions.multiple_versions_installed_error", :name => name)
  end
end

class NotAKegError < RuntimeError; end

class NoSuchKegError < RuntimeError
  attr_reader :name

  def initialize name
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

  def initialize name
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
  attr_reader :user, :repo, :shortname

  def initialize name
    super
    @user, @repo, @shortname = name.split("/", 3)
  end

  def to_s
    if dependent and dependent != name
      t("exceptions.tap_formula_unavailable_error_w_dependent",
        :name => shortname,
        :dependent => dependent,
        :user => user,
        :repo => repo)
    else
      t("exceptions.tap_formula_unavailable_error",
        :name => shortname,
        :user => user,
        :repo => repo)
    end
  end
end

class TapFormulaAmbiguityError < RuntimeError
  attr_reader :name, :paths, :formulae

  def initialize name, paths
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

class OperationInProgressError < RuntimeError
  def initialize name
    super t("exceptions.operation_in_progress_error", :name => name)
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
      :homebrew_prefix => HOMEBREW_PREFIX)
  end
end

class BuildError < RuntimeError
  attr_reader :formula, :env

  def initialize(formula, cmd, args, env)
    @formula = formula
    @env = env
    args = args.map{ |arg| arg.to_s.gsub " ", "\\ " }.join(" ")
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
    if not ARGV.verbose?
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
      require 'cmd/config'
      require 'cmd/--env'

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
    when %r[^file://(.+)]
      super t("exceptions.curl_download_strategy_error_local_file", :file => $1)
    else
      super t("exceptions.curl_download_strategy_error_remote_url", :url => url)
    end
  end
end

# raised by safe_system in utils.rb
class ErrorDuringExecution < RuntimeError
  def initialize(cmd, args=[])
    args = args.map { |a| a.to_s.gsub " ", "\\ " }.join(" ")
    super t("exceptions.error_during_execution", :cmd => cmd, :args => args)
  end
end

# raised by Pathname#verify_checksum when "expected" is nil or empty
class ChecksumMissingError < ArgumentError; end

# raised by Pathname#verify_checksum when verification fails
class ChecksumMismatchError < RuntimeError
  attr_reader :expected, :hash_type

  def initialize fn, expected, actual
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
