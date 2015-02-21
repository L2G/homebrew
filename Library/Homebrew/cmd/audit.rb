require 'formula'
require 'utils'
require 'extend/ENV'
require 'formula_cellar_checks'

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

    ENV.activate_extensions!
    ENV.setup_build_environment

    ff = if ARGV.named.empty?
      Formula
    else
      ARGV.formulae
    end

    output_header = !strict

    ff.each do |f|
      fa = FormulaAuditor.new(f, :strict => strict)
      fa.audit

      unless fa.problems.empty?
        unless output_header
          puts
          ohai "audit problems"
          output_header = true
        end

        formula_count += 1
        problem_count += fa.problems.size
        puts "#{f.name}:", fa.problems.map { |p| " * #{p}" }, ""
      end
    end

    unless problem_count.zero?
      ofail t.cmd.audit.problems_in(
        problem_count, t.cmd.audit.formulae(formula_count)
      )
    end
  end
end

class FormulaText
  def initialize path
    @text = path.open("rb", &:read)
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

  def initialize(formula, options={})
    @formula = formula
    @strict = !!options[:strict]
    @problems = []
    @text = FormulaText.new(formula.path)
    @specs = %w{stable devel head}.map { |s| formula.send(s) }.compact
  end

  def audit_file
    unless formula.path.stat.mode == 0100644
      problem t.cmd.audit.permissions_644(formula.path)
    end

    if text.has_DATA? and not text.has_END?
      problem t.cmd.audit.data_without_end
    end

    if text.has_END? and not text.has_DATA?
      problem t.cmd.audit.end_without_data
    end

    unless text.has_trailing_newline?
      problem t.cmd.audit.needs_ending_newline
    end
  end

  def audit_class
    if @strict
      unless formula.test_defined?
        problem "A `test do` test block should be added"
      end
    end

    if formula.class < GithubGistFormula
      problem "GithubGistFormula is deprecated, use Formula instead"
    end
  end

  @@aliases ||= Formula.aliases

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
          problem t.cmd.audit.cant_find_dependency(dep.name.inspect)
          next
        end

        if @@aliases.include?(dep.name)
          problem t.cmd.audit.alias_should_be(dep.name, dep.to_formula.name)
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
          problem t.cmd.audit.should_be_build_or_run_dependency(dep)
        when "git"
          problem t.cmd.audit.use_depends_on_git
        when "mercurial"
          problem t.cmd.audit.use_depends_on_hg
        when "ruby"
          problem t.cmd.audit.dont_use_dependency(dep)
        when 'gfortran'
          problem t.cmd.audit.use_fortran_not_gfortran
        when 'open-mpi', 'mpich2'
          problem t.cmd.audit.use_mpi_dependency
        end
      end
    end
  end

  def audit_conflicts
    formula.conflicts.each do |c|
      begin
        Formulary.factory(c.name)
      rescue FormulaUnavailableError
        problem t.cmd.audit.cant_find_conflicting(c.name.inspect)
      end
    end
  end

  def audit_options
    formula.options.each do |o|
      next unless @strict
      if o.name !~ /with(out)?-/ && o.name != "c++11" && o.name != "universal" && o.name != "32-bit"
        problem "Options should begin with with/without. Migrate '--#{o.name}' with `deprecated_option`."
      end
    end
  end

  def audit_urls
    homepage = formula.homepage

    unless homepage =~ %r[^https?://]
      problem t.cmd.audit.homepage_should_be_http(homepage)
    end

    # Check for http:// GitHub homepage urls, https:// is preferred.
    # Note: only check homepages that are repo pages, not *.github.com hosts
    if homepage =~ %r[^http://github\.com/]
      problem t.cmd.audit.homepage_github_https(homepage)
    end

    # Google Code homepages should end in a slash
    if homepage =~ %r[^https?://code\.google\.com/p/[^/]+[^/]$]
      problem t.cmd.audit.homepage_googlecode_end_slash(homepage)
    end

    # Automatic redirect exists, but this is another hugely common error.
    if homepage =~ %r[^http://code\.google\.com/]
      problem "Google Code homepages should be https:// links (URL is #{homepage})."
    end

    # GNU has full SSL/TLS support but no auto-redirect.
    if homepage =~ %r[^http://www\.gnu\.org/]
      problem "GNU homepages should be https:// links (URL is #{homepage})."
    end

    # Savannah has full SSL/TLS support but no auto-redirect.
    # Doesn't apply to the download links (boo), only the homepage.
    if homepage =~ %r[^http://savannah\.nongnu\.org/]
      problem "Savannah homepages should be https:// links (URL is #{homepage})."
    end

    if homepage =~ %r[^http://((?:trac|tools|www)\.)?ietf\.org]
      problem "ietf homepages should be https:// links (URL is #{homepage})."
    end

    if homepage =~ %r[^http://((?:www)\.)?gnupg.org/]
      problem "GnuPG homepages should be https:// links (URL is #{homepage})."
    end

    # Freedesktop is complicated to handle - It has SSL/TLS, but only on certain subdomains.
    # To enable https Freedesktop change the url from http://project.freedesktop.org/wiki to
    # https://wiki.freedesktop.org/project_name.
    # "Software" is redirected to https://wiki.freedesktop.org/www/Software/project_name
    if homepage =~ %r[^http://((?:www|nice|libopenraw|liboil|telepathy|xorg)\.)?freedesktop\.org/(?:wiki/)?]
      if homepage =~ /Software/
        problem "The url should be styled `https://wiki.freedesktop.org/www/Software/project_name`, not #{homepage})."
      else
        problem "The url should be styled `https://wiki.freedesktop.org/project_name`, not #{homepage})."
      end
    end

    if homepage =~ %r[^http://wiki\.freedesktop\.org/]
      problem "Freedesktop's Wiki subdomain should be https:// (URL is #{homepage})."
    end

    # There's an auto-redirect here, but this mistake is incredibly common too.
    if homepage =~ %r[^http://packages\.debian\.org]
      problem "Debian homepage should be https:// links (URL is #{homepage})."
    end

    # People will run into mixed content sometimes, but we should enforce and then add
    # exemptions as they are discovered. Treat mixed content on homepages as a bug.
    # Justify each exemptions with a code comment so we can keep track here.
    if homepage =~ %r[^http://[^/]*github\.io/]
      problem "Github Pages links should be https:// (URL is #{homepage})."
    end

    # There's an auto-redirect here, but this mistake is incredibly common too.
    # Only applies to the homepage and subdomains for now, not the FTP links.
    if homepage =~ %r[^http://((?:build|cloud|developer|download|extensions|git|glade|help|library|live|nagios|news|people|projects|rt|static|wiki|www)\.)?gnome\.org]
      problem "Gnome homepages should be https:// links (URL is #{homepage})."
    end

    urls = @specs.map(&:url)

    # Check GNU urls; doesn't apply to mirrors
    urls.grep(%r[^(?:https?|ftp)://(?!alpha).+/gnu/]) do |u|
      problem t.cmd.audit.homepage_gnu_ftpmirror(u)
    end

    # the rest of the checks apply to mirrors as well.
    urls.concat(@specs.map(&:mirrors).flatten)

    # Check a variety of SSL/TLS links that don't consistently auto-redirect
    # or are overly common errors that need to be reduced & fixed over time.
    urls.each do |p|
      # Skip the main url link, as it can't be made SSL/TLS yet.
      next if p =~ %r[/ftpmirror\.gnu\.org]

      case p
      when %r[^http://ftp\.gnu\.org/]
        problem "ftp.gnu.org urls should be https://, not http:// (url is #{p})."
      when %r[^http://code\.google\.com/]
        problem "code.google.com urls should be https://, not http (url is #{p})."
      when %r[^http://fossies\.org/]
        problem "Fossies urls should be https://, not http (url is #{p})."
      when %r[^http://mirrors\.kernel\.org/]
        problem "mirrors.kernel urls should be https://, not http (url is #{p})."
      when %r[^http://tools\.ietf\.org/]
        problem "ietf urls should be https://, not http (url is #{p})."
      end
    end

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

    # Check for new-url Google Code download urls, https:// is preferred
    urls.grep(%r[^http://code\.google\.com/]) do |u|
      problem "Use https:// URLs for downloads from code.google (url is #{u})."
    end

    # Check for git:// GitHub repo urls, https:// is preferred.
    urls.grep(%r[^git://[^/]*github\.com/]) do |u|
      problem t.cmd.audit.url_github_use_https(u)
    end

    # Check for git:// Gitorious repo urls, https:// is preferred.
    urls.grep(%r[^git://[^/]*gitorious\.org/]) do |u|
      problem "Use https:// URLs for accessing Gitorious repositories (url is #{u})."
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
    if head_only?(formula) && formula.tap != "Homebrew/homebrew-head-only"
      problem t.cmd.audit.head_only
    end

    if devel_only?(formula) && formula.tap != "Homebrew/homebrew-devel-only"
      problem "Devel-only (no stable download)"
    end

    %w[Stable Devel HEAD].each do |name|
      next unless spec = formula.send(name.downcase)

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

    if formula.stable && formula.devel
      if formula.devel.version < formula.stable.version
        problem "devel version #{formula.devel.version} is older than stable version #{formula.stable.version}"
      elsif formula.devel.version == formula.stable.version
        problem "stable and devel versions are identical"
      end
    end

    stable = formula.stable
    if stable && stable.url =~ /#{Regexp.escape("ftp.gnome.org/pub/GNOME/sources")}/i
      minor_version = stable.version.to_s[/\d\.(\d+)/, 1].to_i

      if minor_version.odd?
        problem "#{stable.version} is a development release"
      end
    end
  end

  def audit_patches
    legacy_patches = Patch.normalize_legacy_patches(formula.patches).grep(LegacyPatch)
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
    when %r[^http://trac\.macports\.org]
      problem "Patches from MacPorts Trac should be https://, not http:\n#{patch.url}"
    when %r[^http://bugs\.debian\.org]
      problem "Patches from Debian should be https://, not http:\n#{patch.url}"
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
    if line =~ /# Documentation:/
      problem "Please remove default template comments"
    end
    if line =~ /# if this fails, try separate make\/make install steps/
      problem t.cmd.audit.comment_remove_default
    end
    if line =~ /# The url of the archive/
      problem "Please remove default template comments"
    end
    if line =~ /## Naming --/
      problem "Please remove default template comments"
    end
    if line =~ /# if your formula requires any X11\/XQuartz components/
      problem t.cmd.audit.comment_remove_default
    end
    if line =~ /# if your formula fails when building in parallel/
      problem t.cmd.audit.comment_remove_default
    end
    if line =~ /# Remove unrecognized options if warned by configure/
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
      problem t.cmd.audit.use_build_instead_of_argv
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

    if line =~ /system (["'](#{FILEUTILS_METHODS})["' ])/o
      system = $1
      method = $2
      problem "Use the `#{method}` Ruby method instead of `system #{system}`"
    end

    if @strict
      if line =~ /system (["'][^"' ]*(?:\s[^"' ]*)+["'])/
        bad_system = $1
        good_system = bad_system.gsub(" ", "\", \"")
        problem "Use `system #{good_system}` instead of `system #{bad_system}` "
      end

      if line =~ /(require ["']formula["'])/
        problem "`#{$1}` is now unnecessary"
      end
    end
  end

  def audit_caveats
    caveats = formula.caveats

    if caveats =~ /setuid/
      problem "Don't recommend setuid in the caveats, suggest sudo instead."
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

    problem <<-EOS.undent
      The installation seems to be empty. Please ensure the prefix
      is set correctly and expected files are installed.
      The prefix configure/make argument may be case-sensitive.
    EOS
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

  def audit_check_output(output)
    problem(output) if output
  end

  def audit
    audit_file
    audit_class
    audit_specs
    audit_urls
    audit_deps
    audit_conflicts
    audit_options
    audit_patches
    audit_text
    audit_caveats
    text.without_patch.split("\n").each_with_index { |line, lineno| audit_line(line, lineno+1) }
    audit_installed
    audit_prefix_has_contents
  end

  private

  def problem p
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
  attr_reader :version, :checksum, :using, :specs, :url, :name

  def initialize(resource)
    @name     = resource.name
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
    if url =~ %r[^(cvs|bzr|hg|fossil)://] || url =~ %r[^(svn)\+http://]
      problem "Use of the #{$&} scheme is deprecated, pass `:using => :#{$1}` instead"
    end

    return unless using

    if using == :ssl3 || using == CurlSSL3DownloadStrategy
      problem "The SSL3 download strategy is deprecated, please choose a different URL"
    elsif using == CurlUnsafeDownloadStrategy || using == UnsafeSubversionDownloadStrategy
      problem "#{using.name} is deprecated, please choose a different URL"
    end

    if using == :cvs
      mod = specs[:module]

      if mod == name
        problem "Redundant :module value in URL"
      end

      if url =~ %r[:[^/]+$]
        mod = url.split(":").last

        if mod == name
          problem "Redundant CVS module appended to URL"
        else
          problem "Specify CVS module as `:module => \"#{mod}\"` instead of appending it to the URL"
        end
      end
    end

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
