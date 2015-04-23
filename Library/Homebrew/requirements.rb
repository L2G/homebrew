require 'requirement'
require 'requirements/apr_dependency'
require 'requirements/fortran_dependency'
require 'requirements/language_module_dependency'
require 'requirements/minimum_macos_requirement'
require 'requirements/maximum_macos_requirement'
require 'requirements/mpi_dependency'
require 'requirements/osxfuse_dependency'
require 'requirements/python_dependency'
require 'requirements/java_dependency'
require 'requirements/ruby_requirement'
require 'requirements/tuntap_dependency'
require 'requirements/unsigned_kext_requirement'
require 'requirements/x11_dependency'

class XcodeDependency < Requirement
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

class MysqlDependency < Requirement
  fatal true
  default_formula 'mysql'

  satisfy { which 'mysql_config' }
end

class PostgresqlDependency < Requirement
  fatal true
  default_formula 'postgresql'

  satisfy { which 'pg_config' }
end

class GPGDependency < Requirement
  fatal true
  default_formula "gpg"

  satisfy { which("gpg") || which("gpg2") }
end

class TeXDependency < Requirement
  fatal true
  cask "mactex"
  download "https://www.tug.org/mactex/"

  satisfy { which('tex') || which('latex') }

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

  satisfy do
    case @arch
    when :x86_64 then MacOS.prefer_64_bit?
    when :intel, :ppc then Hardware::CPU.type == @arch
    end
  end

  def message
    t("requirements.architecture_required", :arch => @arch)
  end
end

class MercurialDependency < Requirement
  fatal true
  default_formula 'mercurial'

  satisfy { which('hg') }
end

class GitDependency < Requirement
  fatal true
  default_formula 'git'
  satisfy { !!which('git') }
end

