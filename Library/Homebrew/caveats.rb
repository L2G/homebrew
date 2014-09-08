class Caveats
  attr_reader :f

  def initialize(f)
    @f = f
  end

  def caveats
    caveats = []
    caveats << f.caveats if f.caveats.to_s.length > 0
    caveats << f.keg_only_text if f.keg_only? && f.respond_to?(:keg_only_text)
    caveats << bash_completion_caveats
    caveats << zsh_completion_caveats
    caveats << plist_caveats
    caveats << python_caveats
    caveats << app_caveats
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

  def bash_completion_caveats
    if keg and keg.completion_installed? :bash
      t.caveats.bash_completion("#{HOMEBREW_PREFIX}/etc/bash_completion.d")
    end
  end

  def zsh_completion_caveats
    if keg and keg.completion_installed? :zsh
      t.caveats.zsh_completion("#{HOMEBREW_PREFIX}/share/zsh/site-functions")
    end
  end

  def python_caveats
    return unless keg
    return unless keg.python_site_packages_installed?
    return if Formula["python"].installed?
    site_packages = if f.keg_only?
      "#{f.opt_prefix}/lib/python2.7/site-packages"
    else
      "#{HOMEBREW_PREFIX}/lib/python2.7/site-packages"
    end
    dir = "~/Library/Python/2.7/lib/python/site-packages"
    dir_path = Pathname.new(dir).expand_path
    file = "#{dir}/homebrew.pth"
    file_path = Pathname.new(file).expand_path
    if !file_path.readable? || !file_path.read.include?(site_packages)
      if dir_path.exist?
        s = t.caveats.python(dir, site_packages, file)
      else
        s = t.caveats.python_no_dir(site_packages, file)
      end
    end
  end

  def app_caveats
    t.caveats.app if keg and keg.app_installed?
  end

  def plist_caveats
    s = []
    if f.plist or (keg and keg.plist_installed?)
      destination = f.plist_startup ? '/Library/LaunchDaemons' \
                                    : '~/Library/LaunchAgents'

      plist_filename = f.plist_path.basename
      plist_link = "#{destination}/#{plist_filename}"
      plist_domain = f.plist_path.basename('.plist')
      destination_path = Pathname.new File.expand_path destination
      plist_path = destination_path/plist_filename

      # we readlink because this path probably doesn't exist since caveats
      # occurs before the link step of installation
      if (not plist_path.file?) and (not plist_path.symlink?)
        if f.plist_startup
          s << t.caveats.plist_startup(f.name)
          s << "    sudo mkdir -p #{destination}" unless destination_path.directory?
          s << "    sudo cp -fv #{f.opt_prefix}/*.plist #{destination}"
        else
          s << t.caveats.plist_login(f.name)
          s << "    mkdir -p #{destination}" unless destination_path.directory?
          s << "    ln -sfv #{f.opt_prefix}/*.plist #{destination}"
        end
        s << t.caveats.plist_then_load(f.name)
        if f.plist_startup
          s << "    sudo launchctl load #{plist_link}"
        else
          s << "    launchctl load #{plist_link}"
        end
      # For startup plists, we cannot tell whether it's running on launchd,
      # as it requires for `sudo launchctl list` to get real result.
      elsif f.plist_startup
          s << t.caveats.plist_upgrade(f.name)
          s << "    sudo launchctl unload #{plist_link}"
          s << "    sudo cp -fv #{f.opt_prefix}/*.plist #{destination}"
          s << "    sudo launchctl load #{plist_link}"
      elsif Kernel.system "/bin/launchctl list #{plist_domain} &>/dev/null"
          s << t.caveats.plist_upgrade(f.name)
          s << "    launchctl unload #{plist_link}"
          s << "    launchctl load #{plist_link}"
      else
          s << t.caveats.plist_load(f.name)
          s << "    launchctl load #{plist_link}"
      end

      if f.plist_manual
        s << t.caveats.plist_manual
        s << "    #{f.plist_manual}"
      end

      s << "" << t.caveats.plist_tmux_warning if ENV['TMUX']
    end
    s.join("\n") unless s.empty?
  end
end
