require "hardware"
require "software_spec"

module Homebrew
  def config
    dump_verbose_config
  end

  def llvm
    @llvm ||= MacOS.llvm_build_version if MacOS.has_apple_developer_tools?
  end

  def gcc_42
    @gcc_42 ||= MacOS.gcc_42_build_version if MacOS.has_apple_developer_tools?
  end

  def gcc_40
    @gcc_40 ||= MacOS.gcc_40_build_version if MacOS.has_apple_developer_tools?
  end

  def clang
    @clang ||= MacOS.clang_version if MacOS.has_apple_developer_tools?
  end

  def clang_build
    @clang_build ||= MacOS.clang_build_version if MacOS.has_apple_developer_tools?
  end

  def xcode
    if instance_variable_defined?(:@xcode)
      @xcode
    elsif MacOS::Xcode.installed?
      @xcode = if MacOS::Xcode.default_prefix?
                 MacOS::Xcode.version
               else
                 t('cmd.config.pair_with_arrow',
                   :from => MacOS::Xcode.version,
                   :to => MacOS::Xcode.prefix)
               end
    end
  end

  def clt
    if instance_variable_defined?(:@clt)
      @clt
    elsif MacOS::CLT.installed? && MacOS::Xcode.version >= "4.3"
      @clt = MacOS::CLT.version
    end
  end

  def head
    Homebrew.git_head || t('cmd.config.none')
  end

  def last_commit
    Homebrew.git_last_commit || t('cmd.config.never')
  end

  def origin
    origin = HOMEBREW_REPOSITORY.cd do
      `git config --get remote.origin.url 2>/dev/null`.chomp
    end
    if origin.empty? then t('cmd.config.none') else origin end
  end

  def describe_path(path)
    return t('cmd.config.not_applicable') if path.nil?
    realpath = path.realpath
    if realpath == path
      path
    else
      t('cmd.config.pair_with_arrow', :from => path, :to => realpath)
    end
  end

  def describe_x11
    return t('cmd.config.not_applicable') unless MacOS::XQuartz.installed?
    t('cmd.config.pair_with_arrow',
      :from => MacOS::XQuartz.version,
      :to => describe_path(MacOS::XQuartz.prefix))
  end

  def describe_perl
    describe_path(which "perl")
  end

  def describe_python
    python = which "python"
    if %r{/shims/python$} =~ python && which("pyenv")
      begin
        t('cmd.config.pair_with_arrow',
          :from => python,
          :to => Pathname.new(`pyenv which python`.strip).realpath)
      rescue
        describe_path(python)
      end
    else
      describe_path(python)
    end
  end

  def describe_ruby
    ruby = which "ruby"
    if %r{/shims/ruby$} =~ ruby && which("rbenv")
      begin
        t('cmd.config.pair_with_arrow',
          :from => ruby,
          :to => Pathname.new(`rbenv which ruby`.strip).realpath)
      rescue
        describe_path(ruby)
      end
    else
      describe_path(ruby)
    end
  end

  def hardware
    t('cmd.config.item_hardware',
      :cores_as_words => Hardware.cores_as_words,
      :cpu_bits => Hardware::CPU.bits,
      :cpu_family => Hardware::CPU.family)
  end

  def kernel
    `uname -m`.chomp
  end

  def macports_or_fink
    @ponk ||= MacOS.macports_or_fink
    @ponk.join(t('cmd.config.comma_join')) unless @ponk.empty?
  end

  def describe_system_ruby
    s = ""
    case RUBY_VERSION
    when /^1\.[89]/, /^2\.0/
      s << "#{RUBY_VERSION}-p#{RUBY_PATCHLEVEL}"
    else
      s << RUBY_VERSION
    end

    if RUBY_PATH.to_s !~ %r{^/System/Library/Frameworks/Ruby.framework/Versions/[12]\.[089]/usr/bin/ruby}
      s = t('cmd.config.pair_with_arrow', :from => s, :to => RUBY_PATH)
    end
    s
  end

  def describe_java
    if which("java").nil?
      t('cmd.config.not_applicable')
    elsif !(`/usr/libexec/java_home --failfast &>/dev/null` && $?.success?)
      t('cmd.config.not_applicable')
    else
      java = `java -version 2>&1`.lines.first.chomp
      java =~ /java version "(.+?)"/ ? $1 : java
    end
  end

  def dump_verbose_config(f = $stdout)
    f.puts t('cmd.config.item_homebrew_version', :value => HOMEBREW_VERSION)
    f.puts t('cmd.config.item_origin', :value => origin)
    f.puts t('cmd.config.item_head', :value => head)
    f.puts t('cmd.config.item_last_commit', :value => last_commit)
    f.puts t('cmd.config.item_homebrew_prefix', :value => HOMEBREW_PREFIX)
    f.puts "HOMEBREW_REPOSITORY: #{HOMEBREW_REPOSITORY}"
    f.puts t('cmd.config.item_homebrew_cellar', :value => HOMEBREW_CELLAR)
    f.puts t('cmd.config.item_homebrew_bottle_domain',
             :value => BottleSpecification::DEFAULT_DOMAIN)
    f.puts hardware
    f.puts t('cmd.config.item_os_x',
             :version => MACOS_FULL_VERSION,
             :kernel => kernel)
    f.puts t('cmd.config.item_xcode',
             :value => xcode ? xcode : t('cmd.config.not_applicable'))
    f.puts t('cmd.config.item_clt',
             :value => clt ? clt : t('cmd.config.not_applicable'))
    f.puts t('cmd.config.item_gcc_40', :value => gcc_40) if gcc_40
    f.puts t('cmd.config.item_gcc_42', :value => gcc_42) if gcc_42
    f.puts t('cmd.config.item_llvm_gcc', :value => llvm) if llvm
    f.puts t('cmd.config.item_clang',
             :value => clang ? "#{clang} build #{clang_build}"
                             : t('cmd.config.not_applicable'))
    f.puts t('cmd.config.item_macports_fink', :value => macports_or_fink) if macports_or_fink
    f.puts t('cmd.config.item_x11', :value => describe_x11)
    f.puts t('cmd.config.item_system_ruby', :value => describe_system_ruby)
    f.puts t('cmd.config.item_perl', :value => describe_perl)
    f.puts t('cmd.config.item_python', :value => describe_python)
    f.puts t('cmd.config.item_ruby', :value => describe_ruby)
    f.puts t('cmd.config.item_java', :value => describe_java)
  end
end
