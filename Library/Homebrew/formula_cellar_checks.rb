module FormulaCellarChecks
  def check_PATH(bin)
    # warn the user if stuff was installed outside of their PATH
    return unless bin.directory?
    return unless bin.children.length > 0

    prefix_bin = (HOMEBREW_PREFIX/bin.basename)
    return unless prefix_bin.directory?

    prefix_bin = prefix_bin.realpath
    return if ORIGINAL_PATHS.include? prefix_bin

    t("formula_cellar_checks.prefix_bin_not_in_path",
      :prefix_bin => prefix_bin,
      :shell_profile => shell_profile)
  end

  def check_manpages
    # Check for man pages that aren't in share/man
    return unless (formula.prefix+"man").directory?

    t("formula_cellar_checks.top_level_man_dir")
  end

  def check_infopages
    # Check for info pages that aren't in share/info
    return unless (formula.prefix+"info").directory?

    t("formula_cellar_checks.top_level_info_dir")
  end

  def check_jars
    return unless formula.lib.directory?
    jars = formula.lib.children.select { |g| g.extname == ".jar" }
    return if jars.empty?

    t("formula_cellar_checks.jars_found_in_lib", :path => formula.lib) +
      (jars * "\n        ")
  end

  def check_non_libraries
    return unless formula.lib.directory?

    valid_extensions = %w[.a .dylib .framework .jnilib .la .o .so
                          .jar .prl .pm .sh]
    non_libraries = formula.lib.children.select do |g|
      next if g.directory?
      !valid_extensions.include? g.extname
    end
    return if non_libraries.empty?

    t("formula_cellar_checks.non_libraries_found_in_lib",
      :path => formula.lib) +
      (non_libraries * "\n        ")
  end

  def check_non_executables(bin)
    return unless bin.directory?

    non_exes = bin.children.select { |g| g.directory? || !g.executable? }
    return if non_exes.empty?

    t("formula_cellar_checks.non_execs_found_in_bin", :path => bin) +
      (non_exes * "\n        ")
  end

  def check_generic_executables(bin)
    return unless bin.directory?
    generic_names = %w[run service start stop]
    generics = bin.children.select { |g| generic_names.include? g.basename.to_s }
    return if generics.empty?

    t("formula_cellar_checks.generics_found_in_bin", :path => bin) +
      (generics * "\n        ")
  end

  def check_shadowed_headers
    ["libtool", "subversion", "berkeley-db"].each do |formula_name|
      return if formula.name.start_with?(formula_name)
    end

    return if MacOS.version < :mavericks && formula.name.start_with?("postgresql")
    return if MacOS.version < :yosemite  && formula.name.start_with?("memcached")

    return if formula.keg_only? || !formula.include.directory?

    files  = relative_glob(formula.include, "**/*.h")
    files &= relative_glob("#{MacOS.sdk_path}/usr/include", "**/*.h")
    files.map! { |p| File.join(formula.include, p) }

    return if files.empty?

    t("formula_cellar_checks.shadowed_headers_found_in_include",
      :path => formula.include) +
      (files * "\n        ")
  end

  def check_easy_install_pth(lib)
    pth_found = Dir["#{lib}/python{2.7,3}*/site-packages/easy-install.pth"].map { |f| File.dirname(f) }
    return if pth_found.empty?

    t("formula_cellar_checks.easy_install_pth_files_found") +
      (pth_found * "\n        ")
  end

  def check_openssl_links
    return unless formula.prefix.directory?
    keg = Keg.new(formula.prefix)
    system_openssl = keg.mach_o_files.select do |obj|
      dlls = obj.dynamically_linked_libraries
      dlls.any? { |dll| /\/usr\/lib\/lib(crypto|ssl).(\d\.)*dylib/.match dll }
    end
    return if system_openssl.empty?

    t("formula_cellar_checks.obj_linked_against_system_openssl") +
      (system_openssl * "\n        ")
  end

  def check_python_framework_links(lib)
    python_modules = Pathname.glob lib/"python*/site-packages/**/*.so"
    framework_links = python_modules.select do |obj|
      dlls = obj.dynamically_linked_libraries
      dlls.any? { |dll| /Python\.framework/.match dll }
    end
    return if framework_links.empty?

    t("formula_cellar_checks.python_explicit_frameworks") +
      (framework_links * "\n        ")
  end

  def check_emacs_lisp(share, name)
    return unless (share/"emacs/site-lisp").directory?

    # Emacs itself can do what it wants
    return if name == "emacs"

    elisps = (share/"emacs/site-lisp").children.select { |file| %w[.el .elc].include? file.extname }
    return if elisps.empty?

    <<-EOS.undent
      Emacs Lisp files were linked directly to #{HOMEBREW_PREFIX}/share/emacs/site-lisp

      This may cause conflicts with other packages; install to a subdirectory instead, such as
      #{share}/emacs/site-lisp/#{name}

      The offending files are:
        #{elisps * "\n        "}
    EOS
  end

  def audit_installed
    audit_check_output(check_manpages)
    audit_check_output(check_infopages)
    audit_check_output(check_jars)
    audit_check_output(check_non_libraries)
    audit_check_output(check_non_executables(formula.bin))
    audit_check_output(check_generic_executables(formula.bin))
    audit_check_output(check_non_executables(formula.sbin))
    audit_check_output(check_generic_executables(formula.sbin))
    audit_check_output(check_shadowed_headers)
    audit_check_output(check_easy_install_pth(formula.lib))
    audit_check_output(check_openssl_links)
    audit_check_output(check_python_framework_links(formula.lib))
    audit_check_output(check_emacs_lisp(formula.share, formula.name))
  end

  private

  def relative_glob(dir, pattern)
    File.directory?(dir) ? Dir.chdir(dir) { Dir[pattern] } : []
  end
end
