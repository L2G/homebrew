require 'formula'
require 'utils'
require 'extend/ENV'
require 'formula_cellar_checks'

module Homebrew
  def audit
    formula_count = 0
    problem_count = 0

    ENV.activate_extensions!
    ENV.setup_build_environment

    ff = if ARGV.named.empty?
      Formula
    else
      ARGV.formulae
    end

    ff.each do |f|
      fa = FormulaAuditor.new f
      fa.audit

      unless fa.problems.empty?
        puts "#{f.name}:"
        fa.problems.each { |p| puts " * #{p}" }
        puts
        formula_count += 1
        problem_count += fa.problems.size
      end
    end

    unless problem_count.zero?
      ofail t.cmd.audit.problems_in(
        problem_count, t.cmd.audit.formulae(formula_count)
      )
    end
  end
end

# Formula extensions for auditing
class Formula
  def head_only?
    @head and @stable.nil?
  end

  def text
    @text ||= FormulaText.new(@path)
  end
end

class FormulaText
  def initialize path
    @text = path.open("rb", &:read)
  end

  def without_patch
    @text.split("__END__")[0].strip()
  end

  def has_DATA?
    /\bDATA\b/ =~ @text
  end

  def has_END?
    /^__END__$/ =~ @text
  end

  def has_trailing_newline?
    /\Z\n/ =~ @text
  end
end

class FormulaAuditor
  include FormulaCellarChecks

  attr_reader :f, :text, :problems

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

  def initialize f
    @f = f
    @problems = []
    @text = f.text.without_patch
    @specs = %w{stable devel head}.map { |s| f.send(s) }.compact
  end

  def audit_file
    unless f.path.stat.mode.to_s(8) == "100644"
      problem t.cmd.audit.permissions_644(f.path)
    end

    if f.text.has_DATA? and not f.text.has_END?
      problem t.cmd.audit.data_without_end
    end

    if f.text.has_END? and not f.text.has_DATA?
      problem t.cmd.audit.end_without_data
    end

    unless f.text.has_trailing_newline?
      problem t.cmd.audit.needs_ending_newline
    end
  end

  def audit_deps
    # Don't depend_on aliases; use full name
    @@aliases ||= Formula.aliases
    f.deps.select { |d| @@aliases.include? d.name }.each do |d|
      real_name = d.to_formula.name
      problem t.cmd.audit.alias_should_be(d, real_name)
    end

    # Check for things we don't like to depend on.
    # We allow non-Homebrew installs whenever possible.
    f.deps.each do |dep|
      begin
        dep_f = dep.to_formula
      rescue TapFormulaUnavailableError
        # Don't complain about missing cross-tap dependencies
        next
      rescue FormulaUnavailableError
        problem t.cmd.audit.cant_find_dependency(dep.name.inspect)
        next
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
        problem t.cmd.audit.dependency_has_no_option(dep, opt.name.inspect)
      end

      case dep.name
      when *BUILD_TIME_DEPS
        next if dep.build? or dep.run?
        problem t.cmd.audit.should_be_build_dependency(dep)
      when "git", "ruby", "mercurial"
        problem t.cmd.audit.dont_use_dependency(dep)
      when 'gfortran'
        problem t.cmd.audit.use_fortran_not_gfortran
      when 'open-mpi', 'mpich2'
        problem t.cmd.audit.use_mpi_dependency
      end
    end
  end

  def audit_conflicts
    f.conflicts.each do |c|
      begin
        Formulary.factory(c.name)
      rescue FormulaUnavailableError
        problem t.cmd.audit.cant_find_conflicting(c.name.inspect)
      end
    end
  end

  def audit_urls
    unless f.homepage =~ %r[^https?://]
      problem t.cmd.audit.homepage_should_be_http(f.homepage)
    end

    # Check for http:// GitHub homepage urls, https:// is preferred.
    # Note: only check homepages that are repo pages, not *.github.com hosts
    if f.homepage =~ %r[^http://github\.com/]
      problem t.cmd.audit.homepage_github_https(f.homepage)
    end

    # Google Code homepages should end in a slash
    if f.homepage =~ %r[^https?://code\.google\.com/p/[^/]+[^/]$]
      problem t.cmd.audit.homepage_googlecode_end_slash(f.homepage)
    end

    urls = @specs.map(&:url)

    # Check GNU urls; doesn't apply to mirrors
    urls.grep(%r[^(?:https?|ftp)://(?!alpha).+/gnu/]) do |u|
      problem t.cmd.audit.homepage_gnu_ftpmirror(u)
    end

    # the rest of the checks apply to mirrors as well
    urls.concat(@specs.map(&:mirrors).flatten)

    # Check SourceForge urls
    urls.each do |p|
      # Skip if the URL looks like a SVN repo
      next if p =~ %r[/svnroot/]
      next if p =~ %r[svn\.sourceforge]

      # Is it a sourceforge http(s) URL?
      next unless p =~ %r[^https?://.*\b(sourceforge|sf)\.(com|net)]

      if p =~ /(\?|&)use_mirror=/
        problem t.cmd.audit.url_sourceforge_no_mirror($1, p)
      end

      if p =~ /\/download$/
        problem t.cmd.audit.url_sourceforge_no_download(p)
      end

      if p =~ %r[^https?://sourceforge\.]
        problem t.cmd.audit.url_sourceforge_geoloc(p)
      end

      if p =~ %r[^https?://prdownloads\.]
        problem t.cmd.audit.url_sourceforge_no_prdown(p)
      end

      if p =~ %r[^http://\w+\.dl\.]
        problem t.cmd.audit.url_sourceforge_no_specific(p)
      end

      if p.start_with? "http://downloads"
        problem t.cmd.audit.url_sourceforge_use_https(p)
      end
    end

    # Check for Google Code download urls, https:// is preferred
    urls.grep(%r[^http://.*\.googlecode\.com/files.*]) do |u|
      problem t.cmd.audit.url_googlecode_use_https(u)
    end

    # Check for git:// GitHub repo urls, https:// is preferred.
    urls.grep(%r[^git://[^/]*github\.com/]) do |u|
      problem t.cmd.audit.url_github_use_https(u)
    end

    # Check for http:// GitHub repo urls, https:// is preferred.
    urls.grep(%r[^http://github\.com/.*\.git$]) do |u|
      problem t.cmd.audit.url_github_use_https(u)
    end

    # Use new-style archive downloads
    urls.select { |u| u =~ %r[https://.*github.*/(?:tar|zip)ball/] && u !~ %r[\.git$] }.each do |u|
      problem t.cmd.audit.url_github_tarballs(u)
    end

    # Don't use GitHub .zip files
    urls.select { |u| u =~ %r[https://.*github.*/(archive|releases)/.*\.zip$] && u !~ %r[releases/download] }.each do |u|
      problem t.cmd.audit.url_github_no_zips(u)
    end
  end

  def audit_specs
    problem t.cmd.audit.head_only if f.head_only?

    %w[Stable Devel HEAD].each do |name|
      next unless spec = f.send(name.downcase)

      ra = ResourceAuditor.new(spec).audit
      problems.concat ra.problems.map { |problem| "#{name}: #{problem}" }

      spec.resources.each_value do |resource|
        ra = ResourceAuditor.new(resource).audit
        problems.concat ra.problems.map { |problem|
          t.cmd.audit.resource_problem(name, resource.name.inspect, problem)
        }
      end

      spec.patches.select(&:external?).each { |p| audit_patch(p) }
    end
  end

  def audit_patches
    legacy_patches = Patch.normalize_legacy_patches(f.patches).grep(LegacyPatch)
    if legacy_patches.any?
      problem t.cmd.audit.use_patch_dsl
      legacy_patches.each { |p| audit_patch(p) }
    end
  end

  def audit_patch(patch)
    case patch.url
    when %r[raw\.github\.com], %r[gist\.github\.com/raw], %r[gist\.github\.com/.+/raw],
      %r[gist\.githubusercontent\.com/.+/raw]
      unless patch.url =~ /[a-fA-F0-9]{40}/
        problem t.cmd.audit.github_patch_needs_rev(patch.url)
      end
    when %r[macports/trunk]
      problem t.cmd.audit.github_patch_macports(patch.url)
    when %r[^https?://github\.com/.*commit.*\.patch$]
      problem t.cmd.audit.github_patch_use_dot_diff
    end
  end

  def audit_text
    if text =~ /system\s+['"]scons/
      problem t.cmd.audit.scons_args
    end

    if text =~ /system\s+['"]xcodebuild/
      problem t.cmd.audit.xcodebuild_args
    end

    if text =~ /xcodebuild[ (]["'*]/ && text !~ /SYMROOT=/
      problem t.cmd.audit.xcodebuild_symroot
    end

    if text =~ /Formula\.factory\(/
      problem t.cmd.audit.formula_factory
    end
  end

  def audit_line(line, lineno)
    if line =~ /<(Formula|AmazonWebServicesFormula|ScriptFileFormula|GithubGistFormula)/
      problem t.cmd.audit.class_inheritance_space($1)
    end

    # Commented-out cmake support from default template
    if line =~ /# system "cmake/
      problem t.cmd.audit.comment_cmake_found
    end

    # Comments from default template
    if line =~ /# PLEASE REMOVE/
      problem t.cmd.audit.comment_remove_default
    end
    if line =~ /# if this fails, try separate make\/make install steps/
      problem t.cmd.audit.comment_remove_default
    end
    if line =~ /# if your formula requires any X11\/XQuartz components/
      problem t.cmd.audit.comment_remove_default
    end
    if line =~ /# if your formula's build system can't parallelize/
      problem t.cmd.audit.comment_remove_default
    end

    # FileUtils is included in Formula
    # encfs modifies a file with this name, so check for some leading characters
    if line =~ /[^'"\/]FileUtils\.(\w+)/
      problem t.cmd.audit.fileutils_class_dont_need($1)
    end

    # Check for long inreplace block vars
    if line =~ /inreplace .* do \|(.{2,})\|/
      problem t.cmd.audit.inreplace_block_var($1)
    end

    # Check for string interpolation of single values.
    if line =~ /(system|inreplace|gsub!|change_make_var!).*[ ,]"#\{([\w.]+)\}"/
      problem t.cmd.audit.dont_need_to_interpolate($1, $2)
    end

    # Check for string concatenation; prefer interpolation
    if line =~ /(#\{\w+\s*\+\s*['"][^}]+\})/
      problem t.cmd.audit.string_concat_in_interpolation($1)
    end

    # Prefer formula path shortcuts in Pathname+
    if line =~ %r{\(\s*(prefix\s*\+\s*(['"])(bin|include|libexec|lib|sbin|share|Frameworks)[/'"])}
      problem t.cmd.audit.path_should_be("(#{$1}...#{$2})", "(#{$3.downcase}+...)")
    end

    if line =~ %r[((man)\s*\+\s*(['"])(man[1-8])(['"]))]
      problem t.cmd.audit.path_should_be($1, $4)
    end

    # Prefer formula path shortcuts in strings
    if line =~ %r[(\#\{prefix\}/(bin|include|libexec|lib|sbin|share|Frameworks))]
      problem t.cmd.audit.path_should_be($1, "\#{#{$2.downcase}}")
    end

    if line =~ %r[((\#\{prefix\}/share/man/|\#\{man\}/)(man[1-8]))]
      problem t.cmd.audit.path_should_be($1, "\#{#{$3}}")
    end

    if line =~ %r[((\#\{share\}/(man)))[/'"]]
      problem t.cmd.audit.path_should_be($1, "\#{#{$3}}")
    end

    if line =~ %r[(\#\{prefix\}/share/(info|man))]
      problem t.cmd.audit.path_should_be($1, "\#{#{$2}}")
    end

    # Commented-out depends_on
    if line =~ /#\s*depends_on\s+(.+)\s*$/
      problem t.cmd.audit.commented_out_dep($1)
    end

    # No trailing whitespace, please
    if line =~ /[\t ]+$/
      problem t.cmd.audit.trailing_whitespace(lineno)
    end

    if line =~ /if\s+ARGV\.include\?\s+'--(HEAD|devel)'/
      problem t.cmd.audit.use_if_argv_build($1.downcase)
    end

    if line =~ /make && make/
      problem t.cmd.audit.separate_make_calls
    end

    if line =~ /^[ ]*\t/
      problem t.cmd.audit.use_spaces_not_tabs
    end

    if line =~ /ENV\.x11/
      problem t.cmd.audit.use_depends_on_x11
    end

    # Avoid hard-coding compilers
    if line =~ %r{(system|ENV\[.+\]\s?=)\s?['"](/usr/bin/)?(gcc|llvm-gcc|clang)['" ]}
      problem t.cmd.audit.no_hardcoding_compiler(ENV.cc, $3)
    end

    if line =~ %r{(system|ENV\[.+\]\s?=)\s?['"](/usr/bin/)?((g|llvm-g|clang)\+\+)['" ]}
      problem t.cmd.audit.no_hardcoding_compiler(ENV.cxx, $3)
    end

    if line =~ /system\s+['"](env|export)(\s+|['"])/
      problem t.cmd.audit.use_env_instead_of($1)
    end

    if line =~ /version == ['"]HEAD['"]/
      problem t.cmd.audit.use_build_head
    end

    if line =~ /build\.include\?[\s\(]+['"]\-\-(.*)['"]/
      problem t.cmd.audit.no_dashes($1)
    end

    if line =~ /build\.include\?[\s\(]+['"]with(out)?-(.*)['"]/
      problem t.cmd.audit.use_build_with_not_include($1, $2)
    end

    if line =~ /build\.with\?[\s\(]+['"]-?-?with-(.*)['"]/
      problem t.cmd.audit.use_build_with($1)
    end

    if line =~ /build\.without\?[\s\(]+['"]-?-?without-(.*)['"]/
      problem t.cmd.audit.use_build_without($1)
    end

    if line =~ /unless build\.with\?(.*)/
      problem t.cmd.audit.use_if_build_without($1)
    end

    if line =~ /unless build\.without\?(.*)/
      problem t.cmd.audit.use_if_build_with($1)
    end

    if line =~ /(not\s|!)\s*build\.with?\?/
      problem t.cmd.audit.dont_negate_build_without
    end

    if line =~ /(not\s|!)\s*build\.without?\?/
      problem t.cmd.audit.dont_negate_build_with
    end

    if line =~ /ARGV\.(?!(debug\?|verbose\?|value[\(\s]))/
      # Python formulae need ARGV for Requirements
      problem t.cmd.audit.use_build_instead_of_argv,
              :whitelist => %w{pygobject3 qscintilla2}
    end

    if line =~ /def options/
      problem t.cmd.audit.use_new_style_opt_defs
    end

    if line =~ /def test$/
      problem t.cmd.audit.use_new_style_test_defs
    end

    if line =~ /MACOS_VERSION/
      problem t.cmd.audit.use_macos_version
    end

    cats = %w{leopard snow_leopard lion mountain_lion}.join("|")
    if line =~ /MacOS\.(?:#{cats})\?/
      problem t.cmd.audit.version_symbol_deprecated($&)
    end

    if line =~ /skip_clean\s+:all/
      problem t.cmd.audit.skip_clean_all_deprecated
    end

    if line =~ /depends_on [A-Z][\w:]+\.new$/
      problem t.cmd.audit.depends_on_takes_classes
    end

    if line =~ /^def (\w+).*$/
      problem t.cmd.audit.define_method_in_class_body($1.inspect)
    end

    if line =~ /ENV.fortran/
      problem t.cmd.audit.use_depends_on_fortran
    end

    if line =~ /depends_on :(.+) (if.+|unless.+)$/
      audit_conditional_dep($1.to_sym, $2, $&)
    end

    if line =~ /depends_on ['"](.+)['"] (if.+|unless.+)$/
      audit_conditional_dep($1, $2, $&)
    end

    if line =~ /(Dir\[("[^\*{},]+")\])/
      problem t.cmd.audit.unnecessary($1, $2)
    end
  end

  def audit_conditional_dep(dep, condition, line)
    quoted_dep = quote_dep(dep)
    dep = Regexp.escape(dep.to_s)

    case condition
    when /if build\.include\? ['"]with-#{dep}['"]$/, /if build\.with\? ['"]#{dep}['"]$/
      problem t.cmd.audit.replace_with_optional_dep(line.inspect, quoted_dep)
    when /unless build\.include\? ['"]without-#{dep}['"]$/, /unless build\.without\? ['"]#{dep}['"]$/
      problem t.cmd.audit.replace_with_recommended_dep(line.inspect, quoted_dep)
    end
  end

  def quote_dep(dep)
    Symbol === dep ? dep.inspect : "'#{dep}'"
  end

  def audit_check_output warning_and_description
    return unless warning_and_description
    warning, description = *warning_and_description
    problem "#{warning}\n#{description}"
  end

  def audit_installed
    audit_check_output(check_manpages)
    audit_check_output(check_infopages)
    audit_check_output(check_jars)
    audit_check_output(check_non_libraries)
    audit_check_output(check_non_executables(f.bin))
    audit_check_output(check_generic_executables(f.bin))
    audit_check_output(check_non_executables(f.sbin))
    audit_check_output(check_generic_executables(f.sbin))
  end

  def audit
    audit_file
    audit_specs
    audit_urls
    audit_deps
    audit_conflicts
    audit_patches
    audit_text
    text.split("\n").each_with_index {|line, lineno| audit_line(line, lineno+1) }
    audit_installed
  end

  private

  def problem p, options={}
    return if options[:whitelist].to_a.include? f.name
    @problems << p
  end
end

class ResourceAuditor
  attr_reader :problems
  attr_reader :version, :checksum, :using, :specs, :url

  def initialize(resource)
    @version  = resource.version
    @checksum = resource.checksum
    @url      = resource.url
    @using    = resource.using
    @specs    = resource.specs
    @problems = []
  end

  def audit
    audit_version
    audit_checksum
    audit_download_strategy
    self
  end

  def audit_version
    if version.nil?
      problem t.cmd.audit.missing_version
    elsif version.to_s.empty?
      problem t.cmd.audit.version_empty_string
    elsif not version.detected_from_url?
      version_text = version
      version_url = Version.detect(url, specs)
      if version_url.to_s == version_text.to_s && version.instance_of?(Version)
        problem t.cmd.audit.version_redundant(version_text)
      end
    end

    if version.to_s =~ /^v/
      problem t.cmd.audit.version_no_leading_v(version)
    end
  end

  def audit_checksum
    return unless checksum

    case checksum.hash_type
    when :md5
      problem t.cmd.audit.md5_checksums_deprecated
      return
    when :sha1   then len = 40
    when :sha256 then len = 64
    end

    if checksum.empty?
      problem t.cmd.audit.checksum_empty(checksum.hash_type)
    else
      unless checksum.hexdigest.length == len
        problem t.cmd.audit.checksum_should_be_n_chars(checksum.hash_type, len)
      end
      unless checksum.hexdigest =~ /^[a-fA-F0-9]+$/
        problem t.cmd.audit.checksum_invalid_chars(checksum.hash_type)
      end
      unless checksum.hexdigest == checksum.hexdigest.downcase
        problem t.cmd.audit.checksum_should_be_lowercase(checksum.hash_type)
      end
    end
  end

  def audit_download_strategy
    return unless using

    url_strategy   = DownloadStrategyDetector.detect(url)
    using_strategy = DownloadStrategyDetector.detect('', using)

    if url_strategy == using_strategy
      problem t.cmd.audit.url_using_redundant
    end
  end

  def problem text
    @problems << text
  end
end
