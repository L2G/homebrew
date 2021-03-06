require "language/java"

class JavaRequirement < Requirement
  fatal true
  cask "java"
  download "http://www.oracle.com/technetwork/java/javase/downloads/index.html"

  satisfy(:build_env => false) { java_version }

  env do
    java_home = Pathname.new(@java_home)
    ENV["JAVA_HOME"] = java_home
    ENV.prepend_path "PATH", java_home/"bin"
    if (java_home/"include").exist? # Oracle JVM
      ENV.append_to_cflags "-I#{java_home}/include"
      ENV.append_to_cflags "-I#{java_home}/include/darwin"
    else # Apple JVM
      ENV.append_to_cflags "-I/System/Library/Frameworks/JavaVM.framework/Versions/Current/Headers/"
    end
  end

  def initialize(tags)
    @version = tags.shift if /(\d\.)+\d/ === tags.first
    super
  end

  def java_version
    args = %w[--failfast]
    args << "--version" << "#{@version}" if @version
    @java_home = Utils.popen_read("/usr/libexec/java_home", *args).chomp
    $?.success?
  end

  def message
    s = if @version
          t("requirements.java_dependency.java_required_with_version",
            :version => @version)
        else
          t("requirements.java_dependency.java_required")
        end
    s += super
    s
  end

  def inspect
    "#<#{self.class.name}: #{name.inspect} #{tags.inspect} version=#{@version.inspect}>"
  end
end
