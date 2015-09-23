class Caveats
  attr_reader :f

  def initialize(f)
    @f = f
  end

  def caveats
    caveats = []
    s = f.caveats.to_s
    caveats << s.chomp + "\n" if s.length > 0
    caveats << keg_only_text
    caveats << bash_completion_caveats
    caveats << zsh_completion_caveats
    caveats << fish_completion_caveats
    caveats << plist_caveats
    caveats << python_caveats
    caveats << app_caveats
    caveats << elisp_caveats
    caveats.compact.join("\n")
  end

  def empty?
    caveats.empty?
  end

  private

  def keg
    @keg ||= [f.prefix, f.opt_prefix, f.linked_keg].map do |d|
      Keg.new(d.resolved_path) rescue nil
    end.compact.first
  end

  def keg_only_text
    return unless f.keg_only?

    s = t("caveats.keg_only_1", :path => HOMEBREW_PREFIX)
    s << "\n\n#{f.keg_only_reason}"
    if f.lib.directory? || f.include.directory?
      s << "\n\n" + t("caveats.keg_only_2") + "\n\n"
      s << "    " + t("caveats.keg_only_ldflags",  :path => f.opt_lib)     + "\n" if f.lib.directory?
      s << "    " + t("caveats.keg_only_cppflags", :path => f.opt_include) + "\n" if f.include.directory?
    end
    s << "\n"
  end

  def bash_completion_caveats
    if keg && keg.completion_installed?(:bash)
      t('caveats.bash_completion', :path => "#{HOMEBREW_PREFIX}/etc/bash_completion.d")
    end
  end

  def zsh_completion_caveats
    if keg && keg.completion_installed?(:zsh)
      t('caveats.zsh_completion', :path => "#{HOMEBREW_PREFIX}/share/zsh/site-functions")
    end
  end

  def fish_completion_caveats
    if keg && keg.completion_installed?(:fish) && which("fish") then <<-EOS.undent
      fish completion has been installed to:
        #{HOMEBREW_PREFIX}/share/fish/vendor_completions.d
      EOS
    end
  end

  def python_caveats
    return unless keg
    return unless keg.python_site_packages_installed?

    s = nil
    homebrew_site_packages = Language::Python.homebrew_site_packages
    user_site_packages = Language::Python.user_site_packages "python"
    pth_file = user_site_packages/"homebrew.pth"
    instructions = <<-EOS.undent.gsub(/^/, "  ")
      mkdir -p #{user_site_packages}
      echo 'import site; site.addsitedir("#{homebrew_site_packages}")' >> #{pth_file}
    EOS

    if f.keg_only?
      keg_site_packages = f.opt_prefix/"lib/python2.7/site-packages"
      unless Language::Python.in_sys_path?("python", keg_site_packages)
        s = t('caveats.python_find_keg_bindings',
              :cmd => "echo #{keg_site_packages} >> #{homebrew_site_packages/f.name}.pth"
            )
        s += instructions unless Language::Python.reads_brewed_pth_files?("python")
      end
      return s
    end

    return if Language::Python.reads_brewed_pth_files?("python")

    if !Language::Python.in_sys_path?("python", homebrew_site_packages)
      s = t('caveats.python_modules_installed') + instructions
    elsif keg.python_pth_files_installed?
      s = t('caveats.python_pth_files_installed') + instructions
    end
    s
  end

  def app_caveats
    if keg && keg.app_installed?
      t('caveats.app', :name => keg.name)
    end
  end

  def elisp_caveats
    return if f.keg_only?
    if keg && keg.elisp_installed?
      <<-EOS.undent
        Emacs Lisp files have been installed to:
        #{HOMEBREW_PREFIX}/share/emacs/site-lisp/

        Add the following to your init file to have packages installed by Homebrew added to your load-path:
        (let ((default-directory "#{HOMEBREW_PREFIX}/share/emacs/site-lisp/"))
          (normal-top-level-add-subdirs-to-load-path))
      EOS
    end
  end

  def plist_caveats
    s = []
    if f.plist || (keg && keg.plist_installed?)
      destination = if f.plist_startup
        "/Library/LaunchDaemons"
      else
        "~/Library/LaunchAgents"
      end

      plist_filename = if f.plist
        f.plist_path.basename
      else
        File.basename Dir["#{keg}/*.plist"].first
      end
      plist_link = "#{destination}/#{plist_filename}"
      plist_domain = f.plist_path.basename(".plist")
      destination_path = Pathname.new File.expand_path destination
      plist_path = destination_path/plist_filename

      # we readlink because this path probably doesn't exist since caveats
      # occurs before the link step of installation
      # Yosemite security measures mildly tighter rules:
      # https://github.com/Homebrew/homebrew/issues/33815
      if !plist_path.file? || !plist_path.symlink?
        if f.plist_startup
          s << t("caveats.plist_startup", :name => f.full_name)
          s << "  sudo mkdir -p #{destination}" unless destination_path.directory?
          s << "  sudo cp -fv #{f.opt_prefix}/*.plist #{destination}"
          s << "  sudo chown root #{plist_link}"
        else
          s << t("caveats.plist_login", :name => f.full_name)
          s << "  mkdir -p #{destination}" unless destination_path.directory?
          s << "  ln -sfv #{f.opt_prefix}/*.plist #{destination}"
        end
        s << t("caveats.plist_then_load", :name => f.full_name)
        if f.plist_startup
          s << "  sudo launchctl load #{plist_link}"
        else
          s << "  launchctl load #{plist_link}"
        end
      # For startup plists, we cannot tell whether it's running on launchd,
      # as it requires for `sudo launchctl list` to get real result.
      elsif f.plist_startup
        s << t("caveats.plist_upgrade", :name => f.full_name)
        s << "  sudo launchctl unload #{plist_link}"
        s << "  sudo cp -fv #{f.opt_prefix}/*.plist #{destination}"
        s << "  sudo chown root #{plist_link}"
        s << "  sudo launchctl load #{plist_link}"
      elsif Kernel.system "/bin/launchctl list #{plist_domain} &>/dev/null"
        s << t("caveats.plist_upgrade", :name => f.full_name)
        s << "  launchctl unload #{plist_link}"
        s << "  launchctl load #{plist_link}"
      else
        s << t("caveats.plist_load", :name => f.full_name)
        s << "  launchctl load #{plist_link}"
      end

      if f.plist_manual
        s << t("caveats.plist_manual")
        s << "  #{f.plist_manual}"
      end

      s << "" << t("caveats.plist_tmux_warning") if ENV["TMUX"]
    end
    s.join("\n") unless s.empty?
  end
end
