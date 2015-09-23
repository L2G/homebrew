require "requirement"

class MaximumMacOSRequirement < Requirement
  fatal true

  def initialize(tags)
    @version = MacOS::Version.from_symbol(tags.first)
    super
  end

  satisfy(:build_env => false) { MacOS.version <= @version }

  def message
    t("requirements.maximum_macos_requirement",
      :version => @version.pretty_name)
  end
end
