require "requirement"

class X11Requirement < Requirement
  include Comparable
  attr_reader :min_version

  fatal true
  cask "xquartz"
  download "https://xquartz.macosforge.org"

  env { ENV.x11 }

  def initialize(name = "x11", tags = [])
    @name = name
    if /(\d\.)+\d/ === tags.first
      @min_version = Version.new(tags.shift)
      @min_version_string = " #{@min_version}"
    else
      @min_version = Version.new("0.0.0")
      @min_version_string = ""
    end
    super(tags)
  end

  satisfy :build_env => false do
    MacOS::XQuartz.installed? && min_version <= Version.new(MacOS::XQuartz.version)
  end

  def message
    s = if @min_version > Version.new("0.0.0")
          t("requirements.x11_dependency.xquartz_version_required",
            :version => @min_version)
        else
          t("requirements.x11_dependency.xquartz_required")
        end
    [s, super, ""].join("\n")
  end

  def <=>(other)
    return unless X11Requirement === other
    min_version <=> other.min_version
  end

  def eql?(other)
    super && min_version == other.min_version
  end

  def inspect
    "#<#{self.class.name}: #{name.inspect} #{tags.inspect} min_version=#{min_version}>"
  end
end
