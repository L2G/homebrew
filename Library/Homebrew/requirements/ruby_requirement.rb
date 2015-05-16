class RubyRequirement < Requirement
  fatal true
  default_formula "ruby"

  def initialize(tags)
    @version = tags.shift if /(\d\.)+\d/ === tags.first
    raise t("requirements.ruby_requirement.version_required") unless @version
    super
  end

  satisfy :build_env => false do
    next unless which "ruby"
    version = /\d\.\d/.match Utils.popen_read("ruby", "--version")
    next unless version
    Version.new(version.to_s) >= Version.new(@version)
  end

  env do
    ENV.prepend_path "PATH", which("ruby").dirname
  end

  def message
    s = t("requirements.ruby_requirement.ruby_version_is_required",
          :version => @version)
    s += super
    s
  end

  def inspect
    "#<#{self.class.name}: #{name.inspect} #{tags.inspect} version=#{@version.inspect}>"
  end
end
