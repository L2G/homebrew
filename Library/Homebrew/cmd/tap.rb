module Homebrew
  def tap
    if ARGV.empty?
      each_tap do |user, repo|
        puts "#{user.basename}/#{repo.basename.sub("homebrew-", "")}" if (repo/".git").directory?
      end
    elsif ARGV.first == "--repair"
      repair_taps
    else
      opoo "Already tapped!" unless install_tap(*tap_args)
    end
  end

  def install_tap user, repo
    # we special case homebrew so users don't have to shift in a terminal
    repouser = if user == "homebrew" then "Homebrew" else user end
    user = "homebrew" if user == "Homebrew"

    # we downcase to avoid case-insensitive filesystem issues
    tapd = HOMEBREW_LIBRARY/"Taps/#{user.downcase}/homebrew-#{repo.downcase}"
    return false if tapd.directory?
    ohai "Tapping #{repouser}/#{repo}"
    args = %W[clone https://github.com/#{repouser}/homebrew-#{repo} #{tapd}]
    args << "--depth=1" unless ARGV.include?("--full")
    safe_system "git", *args

    files = []
    tapd.find_formula { |file| files << file }
    link_tap_formula(files)
    puts t("cmd.tap.tapped_formulae_abv", :count => files.length, :abv => tapd.abv)

    if private_tap?(repouser, repo)
      puts t("cmd.tap.private_repo_tapped",
             :path => tapd,
             :repo => repo,
             :repo_user => repouser)
    end

    true
  end

  def link_tap_formula(paths, warn_about_conflicts=true)
    ignores = (HOMEBREW_LIBRARY/"Formula/.gitignore").read.split rescue []
    tapped = 0

    paths.each do |path|
      to = HOMEBREW_LIBRARY.join("Formula", path.basename)

      # Unexpected, but possible, lets proceed as if nothing happened
      to.delete if to.symlink? && to.resolved_path == path

      begin
        to.make_relative_symlink(path)
      rescue SystemCallError
        to = to.resolved_path if to.symlink?
        if warn_about_conflicts
          opoo t("cmd.tap.could_not_create_link",
                 :path => tap_ref(path),
                 :to_path => tap_ref(to),
                 :highlight_color => Tty.white,
                 :reset_color => Tty.reset)
        end
      else
        ignores << path.basename.to_s
        tapped += 1
      end
    end

    HOMEBREW_LIBRARY.join("Formula/.gitignore").atomic_write(ignores.uniq.join("\n"))

    tapped
  end

  def repair_taps(warn_about_conflicts=true)
    count = 0
    # prune dead symlinks in Formula
    Dir.glob("#{HOMEBREW_LIBRARY}/Formula/*.rb") do |fn|
      if not File.exist? fn
        File.delete fn
        count += 1
      end
    end
    puts t("cmd.tap.pruned_formulae", :count => count)

    return unless HOMEBREW_REPOSITORY.join("Library/Taps").exist?

    count = 0
    # check symlinks are all set in each tap
    each_tap do |user, repo|
      files = []
      repo.find_formula { |file| files << file }
      count += link_tap_formula(files, warn_about_conflicts)
    end

    puts t("cmd.tap.tapped_formulae", :count => count)
  end

  private

  def each_tap
    taps = HOMEBREW_LIBRARY.join("Taps")

    if taps.directory?
      taps.subdirs.each do |user|
        user.subdirs.each do |repo|
          yield user, repo
        end
      end
    end
  end

  def tap_args(tap_name=ARGV.named.first)
    tap_name =~ HOMEBREW_TAP_ARGS_REGEX
    raise t("cmd.tap.invalid_name") unless $1 && $3
    [$1, $3]
  end

  def private_tap?(user, repo)
    GitHub.private_repo?(user, "homebrew-#{repo}")
  rescue GitHub::HTTPNotFoundError
    true
  rescue GitHub::Error
    false
  end

  def tap_ref(path)
    case path.to_s
    when %r{^#{Regexp.escape(HOMEBREW_LIBRARY.to_s)}/Formula}o
      "Homebrew/homebrew/#{path.basename(".rb")}"
    when HOMEBREW_TAP_PATH_REGEX
      "#{$1}/#{$2.sub("homebrew-", "")}/#{path.basename(".rb")}"
    end
  end
end
