require "formula"
require "utils"
require "extend/ENV"
require "formula_cellar_checks"
require "official_taps"
require "tap_migrations"
require "cmd/search"
require "date"
require "formula_renames"

module Homebrew
  def audit
    formula_count = 0
    problem_count = 0

    strict = ARGV.include? "--strict"
    if strict && ARGV.formulae.any? && MacOS.version >= :mavericks
      require "cmd/style"
      ohai "brew style #{ARGV.formulae.join " "}"
      style
    end

    online = ARGV.include? "--online"

    ENV.activate_extensions!
    ENV.setup_build_environment

    if ARGV.switch? "D"
      FormulaAuditor.module_eval do
        instance_methods.grep(/audit_/).map do |name|
          method = instance_method(name)
          define_method(name) do |*args, &block|
            begin
              time = Time.now
              method.bind(self).call(*args, &block)
            ensure
              $times[name] ||= 0
              $times[name] += Time.now - time
            end
          end
        end
      end

      $times = {}
      at_exit { puts $times.sort_by { |_k, v| v }.map { |k, v| "#{k}: #{v}" } }
    end

    ff = if ARGV.named.empty?
      Formula
    else
      ARGV.formulae
    end

    output_header = !strict

    ff.each do |f|
      fa = FormulaAuditor.new(f, :strict => strict, :online => online)
      fa.audit

      unless fa.problems.empty?
        unless output_header
          puts
          ohai t('cmd.audit.audit_problems')
          output_header = true
        end

        formula_count += 1
        problem_count += fa.problems.size
        puts t('cmd.audit.audit_problems_formula', :name => f.full_name),
          fa.problems.map { |p| t('cmd.audit.audit_problems_list_item', :item => p) },
          ""
      end
    end

    unless problem_count.zero?
      ofail t('cmd.audit.problems_in',
              :count => problem_count,
              :n_formulae => t('cmd.audit.formulae', :count => formula_count)
             )
    end
  end
end

class FormulaText
  def initialize(path)
    @text = path.open("rb", &:read)
    @lines = @text.lines.to_a
  end

  def without_patch
    @text.split("\n__END__").first
  end

  def has_DATA?
    /^[^#]*\bDATA\b/ =~ @text
  end

  def has_END?
    /^__END__$/ =~ @text
  end

  def has_trailing_newline?
    /\Z\n/ =~ @text
  end

  def =~(regex)
    regex =~ @text
  end

  def line_number(regex)
    index = @lines.index { |line| line =~ regex }
    index ? index + 1 : nil
  end
end

class FormulaAuditor
  include FormulaCellarChecks

  attr_reader :formula, :text, :problems

  BUILD_TIME_DEPS = %W[
    autoconf
    automake
    boost-build
    bsdmake
    cmake
    imake
    intltool
    libtool
    pkg-config
    scons
    smake
    swig
  ]

  FILEUTILS_METHODS = FileUtils.singleton_methods(false).join "|"

  def initialize(formula, options = {})
    @formula = formula
    @strict = !!options[:strict]
    @online = !!options[:online]
    @problems = []
    @text = FormulaText.new(formula.path)
    @specs = %w[stable devel head].map { |s| formula.send(s) }.compact
  end

  def audit_file
    unless formula.path.stat.mode == 0100644
      problem t('cmd.audit.permissions_644', :path => formula.path)
    end

    if text.has_DATA? && !text.has_END?
      problem t('cmd.audit.data_without_end')
    end

    if text.has_END? && !text.has_DATA?
      problem t('cmd.audit.end_without_data')
    end

    unless text.has_trailing_newline?
      problem t('cmd.audit.needs_ending_newline')
    end

    return unless @strict

    component_list = [
      [/^  desc ["'][\S\ ]+["']/,          "desc"],
      [/^  homepage ["'][\S\ ]+["']/,      "homepage"],
      [/^  url ["'][\S\ ]+["']/,           "url"],
      [/^  mirror ["'][\S\ ]+["']/,        "mirror"],
      [/^  version ["'][\S\ ]+["']/,       "version"],
      [/^  (sha1|sha256) ["'][\S\ ]+["']/, "checksum"],
      [/^  head ["'][\S\ ]+["']/,          "head"],
      [/^  stable do/,                     "stable block"],
      [/^  bottle do/,                     "bottle block"],
      [/^  devel do/,                      "devel block"],
      [/^  head do/,                       "head block"],
      [/^  option/,                        "option"],
      [/^  depends_on/,                    "depends_on"],
      [/^  def install/,                   "install method"],
      [/^  def caveats/,                   "caveats method"],
      [/^  test do/,                       "test block"]
    ]

    component_list.map do |regex, name|
      lineno = text.line_number regex
      next unless lineno
      [lineno, name]
    end.compact.each_cons(2) do |c1, c2|
      unless c1[0] < c2[0]
        problem "`#{c1[1]}` (line #{c1[0]}) should be put before `#{c2[1]}` (line #{c2[0]})"
      end
    end
  end

  def audit_class
    if @strict
      unless formula.test_defined?
        problem t('cmd.audit.add_test_do')
      end
    end

    if Object.const_defined?("GithubGistFormula") && formula.class < GithubGistFormula
      problem t('cmd.audit.formula_subclass_deprecated',
                :subclass => 'GithubGistFormula')
    end

    if Object.const_defined?("ScriptFileFormula") && formula.class < ScriptFileFormula
      problem t('cmd.audit.formula_subclass_deprecated',
                :subclass => 'ScriptFileFormula')
    end

    if Object.const_defined?("AmazonWebServicesFormula") && formula.class < AmazonWebServicesFormula
      problem t('cmd.audit.formula_subclass_deprecated',
                :subclass => 'AmazonWebServicesFormula')
    end
  end

  # core aliases + tap alias names + tap alias full name
  @@aliases ||= Formula.aliases + Formula.tap_aliases

  def audit_formula_name
    return unless @strict
    # skip for non-official taps
    return if !formula.core_formula? && !formula.tap.to_s.start_with?("homebrew")

    name = formula.name
    full_name = formula.full_name

    if Formula.aliases.include? name
      problem t('cmd.audit.conflict_with_aliases')
      return
    end

    if FORMULA_RENAMES.key? name
      problem "'#{name}' is reserved as the old name of #{FORMULA_RENAMES[name]}"
      return
    end

    if !formula.core_formula? && Formula.core_names.include?(name)
      problem t('cmd.audit.conflict_with_formulae')
      return
    end

    @@local_official_taps_name_map ||= Tap.select(&:official?).flat_map(&:formula_names).
      reduce(Hash.new) do |name_map, tap_formula_full_name|
        tap_formula_name = tap_formula_full_name.split("/").last
        name_map[tap_formula_name] ||= []
        name_map[tap_formula_name] << tap_formula_full_name
        name_map
      end

    same_name_tap_formulae = @@local_official_taps_name_map[name] || []

    if @online
      @@remote_official_taps ||= OFFICIAL_TAPS - Tap.select(&:official?).map(&:repo)

      same_name_tap_formulae += @@remote_official_taps.map do |tap|
        Thread.new { Homebrew.search_tap "homebrew", tap, name }
      end.flat_map(&:value)
    end

    same_name_tap_formulae.delete(full_name)

    if same_name_tap_formulae.size > 0
      problem t('cmd.audit.conflicts_with_formulae_list',
                :list => same_name_tap_formulae.join(t('cmd.audit.list_join')))
    end
  end

  def audit_deps
    @specs.each do |spec|
      # Check for things we don't like to depend on.
      # We allow non-Homebrew installs whenever possible.
      spec.deps.each do |dep|
        begin
          dep_f = dep.to_formula
        rescue TapFormulaUnavailableError
          # Don't complain about missing cross-tap dependencies
          next
        rescue FormulaUnavailableError
          problem t('cmd.audit.cant_find_dependency', :name => dep.name.inspect)
          next
        rescue TapFormulaAmbiguityError
          problem t('cmd.audit.ambiguous_dependency', :name => dep.name.inspect)
          next
        end

        if FORMULA_RENAMES[dep.name] == dep_f.name
          problem "Dependency '#{dep.name}' was renamed; use newname '#{dep_f.name}'."
        end

        if @@aliases.include?(dep.name)
          problem t('cmd.audit.alias_should_be',
                    :alias_name => dep.name,
                    :canonical_name => dep.to_formula.full_name)
        end

        dep.options.reject do |opt|
          next true if dep_f.option_defined?(opt)
          dep_f.requirements.detect do |r|
            if r.recommended?
              opt.name == "with-#{r.name}"
            elsif r.optional?
              opt.name == "without-#{r.name}"
            end
          end
        end.each do |opt|
          problem t('cmd.audit.dependency_has_no_option',
                    :dependency => dep,
                    :option => opt.name.inspect)
        end

        case dep.name
        when *BUILD_TIME_DEPS
          next if dep.build? || dep.run?
          problem t('cmd.audit.should_be_build_or_run_dependency', :name => dep)
        when "git"
          problem t('cmd.audit.dont_use_dependency_git')
        when "mercurial"
          problem t('cmd.audit.use_depends_on_hg')
        when "ruby"
          problem t('cmd.audit.dont_use_dependency', :name => dep)
        when "gfortran"
          problem t('cmd.audit.use_fortran_not_gfortran')
        when "open-mpi", "mpich"
          problem t('cmd.audit.use_mpi_dependency')
        end
      end
    end
  end

  def audit_conflicts
    formula.conflicts.each do |c|
      begin
        Formulary.factory(c.name)
      rescue TapFormulaUnavailableError
        # Don't complain about missing cross-tap conflicts.
        next
      rescue FormulaUnavailableError
        problem t('cmd.audit.cant_find_conflicting', :name => c.name.inspect)
      rescue TapFormulaAmbiguityError
        problem t("cmd.audit.ambiguous_conflict", :name => c.name.inspect)
      end
    end
  end

  def audit_options
    formula.options.each do |o|
      next unless @strict
      if o.name !~ /with(out)?-/ && o.name != "c++11" && o.name != "universal" && o.name != "32-bit"
        problem t('cmd.audit.migrate_deprecated_option', :option => o.name)
      end
    end
  end

  def audit_desc
    # For now, only check the description when using `--strict`
    return unless @strict

    desc = formula.desc

    unless desc && desc.length > 0
      problem t('cmd.audit.should_have_desc')
      return
    end

    # Make sure the formula name plus description is no longer than 80 characters
    linelength = formula.full_name.length + ": ".length + desc.length
    if linelength > 80
      problem t('cmd.audit.desc_too_long',
                :length => linelength,
                :full_name => formula.full_name)
    end

    if desc =~ /([Cc]ommand ?line)/
      problem "Description should use \"command-line\" instead of \"#{$1}\""
    end

    if desc =~ /^([Aa]n?)\s/
      problem "Please remove the indefinite article \"#{$1}\" from the beginning of the description"
    end
  end

  def audit_homepage
    homepage = formula.homepage

    unless homepage =~ %r{^https?://}
      problem t('cmd.audit.homepage_should_be_http', :url => homepage)
    end

    # Check for http:// GitHub homepage urls, https:// is preferred.
    # Note: only check homepages that are repo pages, not *.github.com hosts
    if homepage =~ %r{^http://github\.com/}
      problem t("cmd.audit.homepage_please_use_https", :url => homepage)
    end

    # Savannah has full SSL/TLS support but no auto-redirect.
    # Doesn't apply to the download URLs, only the homepage.
    if homepage =~ %r{^http://savannah\.nongnu\.org/}
      problem t("cmd.audit.homepage_please_use_https", :url => homepage)
    end

    # Freedesktop is complicated to handle - It has SSL/TLS, but only on certain subdomains.
    # To enable https Freedesktop change the URL from http://project.freedesktop.org/wiki to
    # https://wiki.freedesktop.org/project_name.
    # "Software" is redirected to https://wiki.freedesktop.org/www/Software/project_name
    if homepage =~ %r{^http://((?:www|nice|libopenraw|liboil|telepathy|xorg)\.)?freedesktop\.org/(?:wiki/)?}
      if homepage =~ /Software/
        problem t('cmd.audit.homepage_freedesktop_https_software_project',
                  :url => homepage)
      else
        problem t('cmd.audit.homepage_freedesktop_https_project', :url => homepage)
      end
    end

    # Google Code homepages should end in a slash
    if homepage =~ %r{^https?://code\.google\.com/p/[^/]+[^/]$}
      problem t("cmd.audit.homepage_googlecode_end_slash", :url => homepage)
    end

    # People will run into mixed content sometimes, but we should enforce and then add
    # exemptions as they are discovered. Treat mixed content on homepages as a bug.
    # Justify each exemptions with a code comment so we can keep track here.
    if homepage =~ %r{^http://[^/]*github\.io/}
      problem t("cmd.audit.homepage_please_use_https", :url => homepage)
    end

    # There's an auto-redirect here, but this mistake is incredibly common too.
    # Only applies to the homepage and subdomains for now, not the FTP URLs.
    if homepage =~ %r{^http://((?:build|cloud|developer|download|extensions|git|glade|help|library|live|nagios|news|people|projects|rt|static|wiki|www)\.)?gnome\.org}
      problem t("cmd.audit.homepage_please_use_https", :url => homepage)
    end

    # Compact the above into this list as we're able to remove detailed notations, etc over time.
    case homepage
    when %r{^http://[^/]*\.apache\.org},
         %r{^http://packages\.debian\.org},
         %r{^http://wiki\.freedesktop\.org/},
         %r{^http://((?:www)\.)?gnupg.org/},
         %r{^http://ietf\.org},
         %r{^http://[^/.]+\.ietf\.org},
         %r{^http://[^/.]+\.tools\.ietf\.org},
         %r{^http://www\.gnu\.org/},
         %r{^http://code\.google\.com/},
         %r{^http://bitbucket\.org/},
         %r{^http://(?:[^/]*\.)?archive\.org}
      problem t("cmd.audit.homepage_please_use_https", :url => homepage)
    end

    return unless @online
    begin
      nostdout { curl "--connect-timeout", "15", "-o", "/dev/null", homepage }
    rescue ErrorDuringExecution
      problem "The homepage is not reachable (curl exit code #{$?.exitstatus})"
    end
  end

  def audit_github_repository
    return unless @online

    regex = %r{https?://github.com/([^/]+)/([^/]+)/?.*}
    _, user, repo = *regex.match(formula.stable.url) if formula.stable
    _, user, repo = *regex.match(formula.homepage) unless user
    return if !user || !repo

    repo.gsub!(/.git$/, "")

    begin
      metadata = GitHub.repository(user, repo)
    rescue GitHub::HTTPNotFoundError
      return
    end

    problem "GitHub fork (not canonical repository)" if metadata["fork"]
    if (metadata["forks_count"] < 10) && (metadata["watchers_count"] < 10) &&
       (metadata["stargazers_count"] < 20)
      problem "GitHub repository not notable enough (<10 forks, <10 watchers and <20 stars)"
    end

    if Date.parse(metadata["created_at"]) > (Date.today - 30)
      problem "GitHub repository too new (<30 days old)"
    end
  end

  def audit_specs
    if head_only?(formula) && formula.tap.to_s.downcase !~ /-head-only$/
      problem t('cmd.audit.head_only')
    end

    if devel_only?(formula) && formula.tap.to_s.downcase !~ /-devel-only$/
      problem t('cmd.audit.devel_only')
    end

    %w[Stable Devel HEAD].each do |name|
      next unless spec = formula.send(name.downcase)

      ra = ResourceAuditor.new(spec).audit
      problems.concat(
        ra.problems.map do |problem|
          t('cmd.audit.name_problem', :name => name, :problem => problem)
        end
      )

      spec.resources.each_value do |resource|
        ra = ResourceAuditor.new(resource).audit
        problems.concat ra.problems.map { |problem|
          t('cmd.audit.resource_problem',
            :name => name,
            :resource => resource.name.inspect,
            :problem => problem)
        }
      end

      spec.patches.each { |p| audit_patch(p) if p.external? }
    end

    %w[Stable Devel].each do |name|
      next unless spec = formula.send(name.downcase)
      version = spec.version
      if version.to_s !~ /\d/
        problem t('cmd.audit.version_no_digit',
                  :name => name,
                  :version => version)
      end
    end

    if formula.stable && formula.devel
      if formula.devel.version < formula.stable.version
        problem t('cmd.audit.devel_older_than_stable',
          :devel => formula.devel.version,
          :stable => formula.stable.version
        )
      elsif formula.devel.version == formula.stable.version
        problem t('cmd.audit.stable_and_devel_identical')
      end
    end

    stable = formula.stable
    case stable && stable.url
    when %r{download\.gnome\.org/sources}, %r{ftp\.gnome\.org/pub/GNOME/sources}i
      minor_version = Version.parse(stable.url).to_s.split(".", 3)[1].to_i

      if minor_version.odd?
        problem t('cmd.audit.version_is_devel', :version => stable.version)
      end
    end
  end

  def audit_legacy_patches
    return unless formula.respond_to?(:patches)
    legacy_patches = Patch.normalize_legacy_patches(formula.patches).grep(LegacyPatch)
    if legacy_patches.any?
      problem t('cmd.audit.use_patch_dsl')
      legacy_patches.each { |p| audit_patch(p) }
    end
  end

  def audit_patch(patch)
    case patch.url
    when /raw\.github\.com/, %r{gist\.github\.com/raw}, %r{gist\.github\.com/.+/raw},
      %r{gist\.githubusercontent\.com/.+/raw}
      unless patch.url =~ /[a-fA-F0-9]{40}/
        problem t('cmd.audit.github_patch_needs_rev', :url => patch.url)
      end
    when %r{macports/trunk}
      problem t('cmd.audit.github_patch_macports', :url => patch.url)
    when %r{^http://trac\.macports\.org}
      problem t('cmd.audit.macports_patch_use_https', :url => patch.url)
    when %r{^http://bugs\.debian\.org}
      problem t('cmd.audit.debian_patch_use_https', :url => patch.url)
    end
  end

  def audit_text
    if text =~ /system\s+['"]scons/
      problem t('cmd.audit.scons_args')
    end

    if text =~ /system\s+['"]xcodebuild/
      problem t('cmd.audit.xcodebuild_args')
    end

    if text =~ /xcodebuild[ (]["'*]/ && text !~ /SYMROOT=/
      problem t('cmd.audit.xcodebuild_symroot')
    end

    if text =~ /Formula\.factory\(/
      problem t('cmd.audit.formula_factory')
    end

    if text =~ /system "npm", "install"/ && text !~ %r[opt_libexec}/npm/bin]
      need_npm = "\#{Formula[\"node\"].opt_libexec\}/npm/bin"
      problem <<-EOS.undent
       Please add ENV.prepend_path \"PATH\", \"#{need_npm}"\ to def install
      EOS
    end
  end

  def audit_line(line, lineno)
    if line =~ /<(Formula|AmazonWebServicesFormula|ScriptFileFormula|GithubGistFormula)/
      problem t('cmd.audit.class_inheritance_space', :superclass => $1)
    end

    # Commented-out cmake support from default template
    if line =~ /# system "cmake/
      problem t('cmd.audit.comment_cmake_found')
    end

    # Comments from default template
    if line =~ /# PLEASE REMOVE/
      problem t('cmd.audit.comment_remove_default')
    end
    if line =~ /# Documentation:/
      problem t('cmd.audit.comment_remove_default')
    end
    if line =~ /# if this fails, try separate make\/make install steps/
      problem t('cmd.audit.comment_remove_default')
    end
    if line =~ /# The url of the archive/
      problem t('cmd.audit.comment_remove_default')
    end
    if line =~ /## Naming --/
      problem t('cmd.audit.comment_remove_default')
    end
    if line =~ /# if your formula requires any X11\/XQuartz components/
      problem t('cmd.audit.comment_remove_default')
    end
    if line =~ /# if your formula fails when building in parallel/
      problem t('cmd.audit.comment_remove_default')
    end
    if line =~ /# Remove unrecognized options if warned by configure/
      problem t('cmd.audit.comment_remove_default')
    end

    # FileUtils is included in Formula
    # encfs modifies a file with this name, so check for some leading characters
    if line =~ /[^'"\/]FileUtils\.(\w+)/
      problem t('cmd.audit.fileutils_class_dont_need', :method => $1)
    end

    # Check for long inreplace block vars
    if line =~ /inreplace .* do \|(.{2,})\|/
      problem t('cmd.audit.inreplace_block_var', :block_var => $1)
    end

    # Check for string interpolation of single values.
    if line =~ /(system|inreplace|gsub!|change_make_var!).*[ ,]"#\{([\w.]+)\}"/
      problem t('cmd.audit.dont_need_to_interpolate', :method => $1, :var => $2)
    end

    # Check for string concatenation; prefer interpolation
    if line =~ /(#\{\w+\s*\+\s*['"][^}]+\})/
      problem t('cmd.audit.string_concat_in_interpolation', :interpolation => $1)
    end

    # Prefer formula path shortcuts in Pathname+
    if line =~ %r{\(\s*(prefix\s*\+\s*(['"])(bin|include|libexec|lib|sbin|share|Frameworks)[/'"])}
      problem t('cmd.audit.path_should_be',
                :bad_path => "(#{$1}...#{$2})",
                :good_path => "(#{$3.downcase}+...)")
    end

    if line =~ /((man)\s*\+\s*(['"])(man[1-8])(['"]))/
      problem t('cmd.audit.path_should_be', :bad_path => $1, :good_path => $4)
    end

    # Prefer formula path shortcuts in strings
    if line =~ %r[(\#\{prefix\}/(bin|include|libexec|lib|sbin|share|Frameworks))]
      problem t('cmd.audit.path_should_be',
                :bad_path => $1,
                :good_path => "\#{#{$2.downcase}}")
    end

    if line =~ %r[((\#\{prefix\}/share/man/|\#\{man\}/)(man[1-8]))]
      problem t('cmd.audit.path_should_be',
                :bad_path => $1,
                :good_path => "\#{#{$3}}")
    end

    if line =~ %r[((\#\{share\}/(man)))[/'"]]
      problem t('cmd.audit.path_should_be',
                :bad_path => $1,
                :good_path => "\#{#{$3}}")
    end

    if line =~ %r[(\#\{prefix\}/share/(info|man))]
      problem t('cmd.audit.path_should_be',
                :bad_path => $1,
                :good_path => "\#{#{$2}}")
    end

    if line =~ /depends_on :(automake|autoconf|libtool)/
      problem t('cmd.audit.deprecated_symbol', :name => $1)
    end

    # Commented-out depends_on
    if line =~ /#\s*depends_on\s+(.+)\s*$/
      problem t('cmd.audit.commented_out_dep', :dep => $1)
    end

    # No trailing whitespace, please
    if line =~ /[\t ]+$/
      problem t('cmd.audit.trailing_whitespace', :line_num => lineno)
    end

    if line =~ /if\s+ARGV\.include\?\s+'--(HEAD|devel)'/
      problem t('cmd.audit.use_if_argv_build', :build_test => $1.downcase)
    end

    if line =~ /make && make/
      problem t('cmd.audit.separate_make_calls')
    end

    if line =~ /^[ ]*\t/
      problem t('cmd.audit.use_spaces_not_tabs')
    end

    if line =~ /ENV\.x11/
      problem t('cmd.audit.use_depends_on_x11')
    end

    # Avoid hard-coding compilers
    if line =~ %r{(system|ENV\[.+\]\s?=)\s?['"](/usr/bin/)?(gcc|llvm-gcc|clang)['" ]}
      problem t('cmd.audit.no_hardcoding_compiler', :env => ENV.cc, :compiler => $3)
    end

    if line =~ %r{(system|ENV\[.+\]\s?=)\s?['"](/usr/bin/)?((g|llvm-g|clang)\+\+)['" ]}
      problem t('cmd.audit.no_hardcoding_compiler', :env => ENV.cxx, :compiler => $3)
    end

    if line =~ /system\s+['"](env|export)(\s+|['"])/
      problem t('cmd.audit.use_env_instead_of', :bad => $1)
    end

    if line =~ /version == ['"]HEAD['"]/
      problem t('cmd.audit.use_build_head')
    end

    if line =~ /build\.include\?[\s\(]+['"]\-\-(.*)['"]/
      problem t('cmd.audit.no_dashes', :option => $1)
    end

    if line =~ /build\.include\?[\s\(]+['"]with(out)?-(.*)['"]/
      problem t('cmd.audit.use_build_with_not_include',
                :out => $1,
                :option => $2)
    end

    if line =~ /build\.with\?[\s\(]+['"]-?-?with-(.*)['"]/
      problem t('cmd.audit.use_build_with', :option => $1)
    end

    if line =~ /build\.without\?[\s\(]+['"]-?-?without-(.*)['"]/
      problem t('cmd.audit.use_build_without', :option => $1)
    end

    if line =~ /unless build\.with\?(.*)/
      problem t('cmd.audit.use_if_build_without', :option => $1)
    end

    if line =~ /unless build\.without\?(.*)/
      problem t('cmd.audit.use_if_build_with', :option => $1)
    end

    if line =~ /(not\s|!)\s*build\.with?\?/
      problem t('cmd.audit.dont_negate_build_without')
    end

    if line =~ /(not\s|!)\s*build\.without?\?/
      problem t('cmd.audit.dont_negate_build_with')
    end

    if line =~ /ARGV\.(?!(debug\?|verbose\?|value[\(\s]))/
      problem t('cmd.audit.use_build_instead_of_argv')
    end

    if line =~ /def options/
      problem t('cmd.audit.use_new_style_opt_defs')
    end

    if line =~ /def test$/
      problem t('cmd.audit.use_new_style_test_defs')
    end

    if line =~ /MACOS_VERSION/
      problem t('cmd.audit.use_macos_version')
    end

    cats = %w[leopard snow_leopard lion mountain_lion].join("|")
    if line =~ /MacOS\.(?:#{cats})\?/
      problem t('cmd.audit.version_symbol_deprecated', :symbol => $&)
    end

    if line =~ /skip_clean\s+:all/
      problem t('cmd.audit.skip_clean_all_deprecated')
    end

    if line =~ /depends_on [A-Z][\w:]+\.new$/
      problem t('cmd.audit.depends_on_takes_classes')
    end

    if line =~ /^def (\w+).*$/
      problem t('cmd.audit.define_method_in_class_body', :method => $1.inspect)
    end

    if line =~ /ENV.fortran/ && !formula.requirements.map(&:class).include?(FortranRequirement)
      problem t('cmd.audit.use_depends_on_fortran')
    end

    if line =~ /JAVA_HOME/i && !formula.requirements.map(&:class).include?(JavaRequirement)
      problem t('cmd.audit.use_depends_on_java_to_set_java_home')
    end

    if line =~ /depends_on :(.+) (if.+|unless.+)$/
      audit_conditional_dep($1.to_sym, $2, $&)
    end

    if line =~ /depends_on ['"](.+)['"] (if.+|unless.+)$/
      audit_conditional_dep($1, $2, $&)
    end

    if line =~ /(Dir\[("[^\*{},]+")\])/
      problem t('cmd.audit.unnecessary', :dir_with_path => $1, :path => $2)
    end

    if line =~ /system (["'](#{FILEUTILS_METHODS})["' ])/o
      system = $1
      method = $2
      problem t('cmd.audit.use_ruby_method_instead_of_system',
                :method => method,
                :shell_cmd => system)
    end

    if line =~ /assert [^!]+\.include?/
      problem "Use `assert_match` instead of `assert ...include?`"
    end

    if @strict
      if line =~ /system (["'][^"' ]*(?:\s[^"' ]*)+["'])/
        bad_system = $1
        unless %w[| < > & ; *].any? { |c| bad_system.include? c }
          good_system = bad_system.gsub(" ", "\", \"")
          problem t('cmd.audit.use_system_alternative',
                    :good_system => good_system,
                    :bad_system => bad_system)
        end
      end

      if line =~ /(require ["']formula["'])/
        problem t('cmd.audit.is_now_unnecessary', :require_formula => $1)
      end
    end
  end

  def audit_caveats
    caveats = formula.caveats

    if caveats =~ /setuid/
      problem t('cmd.audit.caveats_no_setuid')
    end
  end

  def audit_reverse_migration
    # Only enforce for new formula being re-added to core
    return unless @strict
    return unless formula.core_formula?

    if TAP_MIGRATIONS.key?(formula.name)
      problem <<-EOS.undent
       #{formula.name} seems to be listed in tap_migrations.rb!
       Please remove #{formula.name} from present tap & tap_migrations.rb
       before submitting it to Homebrew/homebrew.
      EOS
    end
  end

  def audit_prefix_has_contents
    return unless formula.prefix.directory?

    Pathname.glob("#{formula.prefix}/**/*") do |file|
      next if file.directory?
      basename = file.basename.to_s
      next if Metafiles.copy?(basename)
      next if %w[.DS_Store INSTALL_RECEIPT.json].include?(basename)
      return
    end

    problem t('cmd.audit.installation_empty')
  end

  def audit_conditional_dep(dep, condition, line)
    quoted_dep = quote_dep(dep)
    dep = Regexp.escape(dep.to_s)

    case condition
    when /if build\.include\? ['"]with-#{dep}['"]$/, /if build\.with\? ['"]#{dep}['"]$/
      problem t('cmd.audit.replace_with_optional_dep',
                :line => line.inspect,
                :dep => quoted_dep)
    when /unless build\.include\? ['"]without-#{dep}['"]$/, /unless build\.without\? ['"]#{dep}['"]$/
      problem t('cmd.audit.replace_with_recommended_dep',
                :line => line.inspect,
                :dep => quoted_dep)
    end
  end

  def quote_dep(dep)
    Symbol === dep ? dep.inspect : t('cmd.audit.quoted_dep', :dep => dep)
  end

  def audit_check_output(output)
    problem(output) if output
  end

  def audit
    audit_file
    audit_formula_name
    audit_class
    audit_specs
    audit_desc
    audit_homepage
    audit_github_repository
    audit_deps
    audit_conflicts
    audit_options
    audit_legacy_patches
    audit_text
    audit_caveats
    text.without_patch.split("\n").each_with_index { |line, lineno| audit_line(line, lineno+1) }
    audit_installed
    audit_prefix_has_contents
    audit_reverse_migration
  end

  private

  def problem(p)
    @problems << p
  end

  def head_only?(formula)
    formula.head && formula.devel.nil? && formula.stable.nil?
  end

  def devel_only?(formula)
    formula.devel && formula.stable.nil?
  end
end

class ResourceAuditor
  attr_reader :problems
  attr_reader :version, :checksum, :using, :specs, :url, :mirrors, :name

  def initialize(resource)
    @name     = resource.name
    @version  = resource.version
    @checksum = resource.checksum
    @url      = resource.url
    @mirrors  = resource.mirrors
    @using    = resource.using
    @specs    = resource.specs
    @problems = []
  end

  def audit
    audit_version
    audit_checksum
    audit_download_strategy
    audit_urls
    self
  end

  def audit_version
    if version.nil?
      problem t('cmd.audit.missing_version')
    elsif version.to_s.empty?
      problem t('cmd.audit.version_empty_string')
    elsif !version.detected_from_url?
      version_text = version
      version_url = Version.detect(url, specs)
      if version_url.to_s == version_text.to_s && version.instance_of?(Version)
        problem t('cmd.audit.version_redundant', :version => version_text)
      end
    end

    if version.to_s =~ /^v/
      problem t('cmd.audit.version_no_leading_v', :version => version)
    end

    if version.to_s =~ /_\d+$/
      problem t('cmd.audit.version_trailing_underscore_digit',
                :version => version)
    end
  end

  def audit_checksum
    return unless checksum

    case checksum.hash_type
    when :md5
      problem t('cmd.audit.md5_checksums_deprecated')
      return
    when :sha1
      problem t('cmd.audit.sha1_checksums_deprecated')
      return
    when :sha256 then len = 64
    end

    if checksum.empty?
      problem t('cmd.audit.checksum_empty', :checksum_type => checksum.hash_type)
    else
      unless checksum.hexdigest.length == len
        problem t('cmd.audit.checksum_should_be_n_chars',
                  :checksum_type => checksum.hash_type,
                  :count => len)
      end
      unless checksum.hexdigest =~ /^[a-fA-F0-9]+$/
        problem t('cmd.audit.checksum_invalid_chars',
                  :checksum_type => checksum.hash_type)
      end
      unless checksum.hexdigest == checksum.hexdigest.downcase
        problem t('cmd.audit.checksum_should_be_lowercase',
                  :checksum_type => checksum.hash_type)
      end
    end
  end

  def audit_download_strategy
    if url =~ %r{^(cvs|bzr|hg|fossil)://} || url =~ %r{^(svn)\+http://}
      problem t('cmd.audit.scheme_deprecated',
                :url_scheme => $&,
                :symbol => $1)
    end

    url_strategy = DownloadStrategyDetector.detect(url)

    if using == :git || url_strategy == GitDownloadStrategy
      if specs[:tag] && !specs[:revision]
        problem t('cmd.audit.git_specify_revision_with_tag')
      end
    end

    return unless using

    if using == :ssl3 || \
       (Object.const_defined?("CurlSSL3DownloadStrategy") && using == CurlSSL3DownloadStrategy)
      problem t('cmd.audit.ssl3_deprecated')
    elsif (Object.const_defined?("CurlUnsafeDownloadStrategy") && using == CurlUnsafeDownloadStrategy) || \
          (Object.const_defined?("UnsafeSubversionDownloadStrategy") && using == UnsafeSubversionDownloadStrategy)
      problem t('cmd.audit.strategy_deprecated', :strategy => using.name)
    end

    if using == :cvs
      mod = specs[:module]

      if mod == name
        problem t('cmd.audit.redundant_module_value')
      end

      if url =~ %r{:[^/]+$}
        mod = url.split(":").last

        if mod == name
          problem t('cmd.audit.redundant_cvs_module')
        else
          problem t('cmd.audit.specify_cvs_module', :module => mod)
        end
      end
    end

    using_strategy = DownloadStrategyDetector.detect("", using)

    if url_strategy == using_strategy
      problem t('cmd.audit.url_using_redundant')
    end
  end

  def audit_urls
    # Check GNU urls; doesn't apply to mirrors
    if url =~ %r{^(?:https?|ftp)://(?!alpha).+/gnu/}
      problem t("cmd.audit.homepage_gnu_ftpmirror", :url => url)
    end

    # GNU's ftpmirror does NOT support SSL/TLS.
    if url =~ %r{^https://ftpmirror\.gnu\.org/}
      problem "Please use http:// for #{url}"
    end

    if mirrors.include?(url)
      problem t("cmd.audit.url_duped_mirror", :url => url)
    end

    urls = [url] + mirrors

    # Check a variety of SSL/TLS URLs that don't consistently auto-redirect
    # or are overly common errors that need to be reduced & fixed over time.
    urls.each do |p|
      case p
      when %r{^http://ftp\.gnu\.org/},
           %r{^http://[^/]*\.apache\.org/},
           %r{^http://code\.google\.com/},
           %r{^http://fossies\.org/},
           %r{^http://mirrors\.kernel\.org/},
           %r{^http://(?:[^/]*\.)?bintray\.com/},
           %r{^http://tools\.ietf\.org/},
           %r{^http://www\.mirrorservice\.org/},
           %r{^http://launchpad\.net/},
           %r{^http://bitbucket\.org/},
           %r{^http://(?:[^/]*\.)?archive\.org}
        problem t("cmd.audit.homepage_please_use_https", :url => p)
      when %r{^http://search\.mcpan\.org/CPAN/(.*)}i
        problem t("cmd.audit.url_metacpan", :url => p, :url_path => $1)
      when %r{^(http|ftp)://ftp\.gnome\.org/pub/gnome/(.*)}i
        problem t("cmd.audit.url_download_gnome_org", :url => p, :url_path => $2)
      end
    end

    # Check SourceForge urls
    urls.each do |p|
      # Skip if the URL looks like a SVN repo
      next if p =~ %r{/svnroot/}
      next if p =~ /svn\.sourceforge/

      # Is it a sourceforge http(s) URL?
      next unless p =~ %r{^https?://.*\b(sourceforge|sf)\.(com|net)}

      if p =~ /(\?|&)use_mirror=/
        problem t("cmd.audit.url_sourceforge_no_mirror",
                  :url_query_part => $1,
                  :url => p)
      end

      if p =~ /\/download$/
        problem t("cmd.audit.url_sourceforge_no_download", :url => p)
      end

      if p =~ %r{^https?://sourceforge\.}
        problem t("cmd.audit.url_sourceforge_geoloc", :url => p)
      end

      if p =~ %r{^https?://prdownloads\.}
        problem t("cmd.audit.url_sourceforge_no_prdown", :url => p)
      end

      if p =~ %r{^http://\w+\.dl\.}
        problem t("cmd.audit.url_sourceforge_no_specific", :url => p)
      end

      if p.start_with? "http://downloads"
        problem t("cmd.audit.homepage_please_use_https", :url => p)
      end
    end

    # Check for Google Code download urls, https:// is preferred
    # Intentionally not extending this to SVN repositories due to certificate
    # issues.
    urls.grep(%r{^http://.*\.googlecode\.com/files.*}) do |u|
      problem t("cmd.audit.homepage_please_use_https", :url => u)
    end

    # Check for new-url Google Code download urls, https:// is preferred
    urls.grep(%r{^http://code\.google\.com/}) do |u|
      problem t("cmd.audit.homepage_please_use_https", :url => u)
    end

    # Check for git:// GitHub repo urls, https:// is preferred.
    urls.grep(%r{^git://[^/]*github\.com/}) do |u|
      problem t("cmd.audit.homepage_please_use_https", :url => u)
    end

    # Check for git:// Gitorious repo urls, https:// is preferred.
    urls.grep(%r{^git://[^/]*gitorious\.org/}) do |u|
      problem t("cmd.audit.homepage_please_use_https", :url => u)
    end

    # Check for http:// GitHub repo urls, https:// is preferred.
    urls.grep(%r{^http://github\.com/.*\.git$}) do |u|
      problem t("cmd.audit.homepage_please_use_https", :url => u)
    end

    # Use new-style archive downloads
    urls.each do |u|
      next unless u =~ %r{https://.*github.*/(?:tar|zip)ball/} && u !~ /\.git$/
      problem t("cmd.audit.url_github_tarballs", :url => u)
    end

    # Don't use GitHub .zip files
    urls.each do |u|
      next unless u =~ %r{https://.*github.*/(archive|releases)/.*\.zip$} && u !~ %r{releases/download}
      problem t("cmd.audit.url_github_no_zips", :url => u)
    end
  end

  def problem(text)
    @problems << text
  end
end
