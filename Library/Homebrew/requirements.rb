require "requirement"
require "requirements/apr_requirement"
require "requirements/fortran_requirement"
require "requirements/language_module_requirement"
require "requirements/minimum_macos_requirement"
require "requirements/maximum_macos_requirement"
require "requirements/mpi_requirement"
require "requirements/osxfuse_requirement"
require "requirements/python_requirement"
require "requirements/java_requirement"
require "requirements/ruby_requirement"
require "requirements/tuntap_requirement"
require "requirements/unsigned_kext_requirement"
require "requirements/x11_requirement"
require "requirements/emacs_requirement"

class XcodeRequirement < Requirement
  fatal true

  satisfy(:build_env => false) { xcode_installed_version }

  def initialize(tags)
    @version = tags.find { |t| tags.delete(t) if /(\d\.)+\d/ === t }
    super
  end

  def xcode_installed_version
    return false unless MacOS::Xcode.installed?
    return true unless @version
    MacOS::Xcode.version >= @version
  end

  def message
    message = if @version
                t("requirements.full_xcode_required_with_version",
                  :version => @version)
              else
                t("requirements.full_xcode_required")
              end
    if MacOS.version >= :lion
      message += t("requirements.xcode_install_hint_lion")
    else
      message += t("requirements.xcode_install_hint")
    end
    "#{message}\n"
  end

  def inspect
    "#<#{self.class.name}: #{name.inspect} #{tags.inspect} version=#{@version.inspect}>"
  end
end

class MysqlRequirement < Requirement
  fatal true
  default_formula "mysql"

  satisfy { which "mysql_config" }
end

class PostgresqlRequirement < Requirement
  fatal true
  default_formula "postgresql"

  satisfy { which "pg_config" }
end

class GPGRequirement < Requirement
  fatal true
  default_formula "gpg"

  satisfy { which("gpg") || which("gpg2") }
end

class TeXRequirement < Requirement
  fatal true
  cask "mactex"
  download "https://www.tug.org/mactex/"

  satisfy { which("tex") || which("latex") }

  def message
    s = t("requirements.latex_required")
    s += super
    s
  end
end

class ArchRequirement < Requirement
  fatal true

  def initialize(arch)
    @arch = arch.pop
    super
  end

  satisfy(:build_env => false) do
    case @arch
    when :x86_64 then MacOS.prefer_64_bit?
    when :intel, :ppc then Hardware::CPU.type == @arch
    end
  end

  def message
    t("requirements.architecture_required", :arch => @arch)
  end
end

class MercurialRequirement < Requirement
  fatal true
  default_formula "mercurial"

  satisfy { which("hg") }
end

class GitRequirement < Requirement
  fatal true
  default_formula "git"
  satisfy { !!which("git") }
end

