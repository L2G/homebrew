require "requirement"

class UnsignedKextRequirement < Requirement
  fatal true

  satisfy(:build_env => false) { MacOS.version < :yosemite }

  def message
    [t("requirements.unsigned_kext_requirement.forbidden_by_yosemite"),
     super, ''].join("\n")
  end
end
