require 'cmd/tap'
require 'cmd/untap'

module Homebrew extend self
  def update
    unless ARGV.named.empty?
      abort t.cmd.update.no_formula_names
    end
    abort t.cmd.update.install_git unless which "git"

    # ensure GIT_CONFIG is unset as we need to operate on .git/config
    ENV.delete('GIT_CONFIG')

    cd HOMEBREW_REPOSITORY
    git_init_if_necessary

    tapped_formulae = []
    HOMEBREW_LIBRARY.join("Formula").children.each do |path|
      next unless path.symlink?
      tapped_formulae << path.resolved_path
    end
    unlink_tap_formula(tapped_formulae)

    report = Report.new
    master_updater = Updater.new
    begin
      master_updater.pull!
    ensure
      link_tap_formula(tapped_formulae)
    end
    report.merge!(master_updater.report)

    # rename Taps directories
    # this procedure will be removed in the future if it seems unnecessasry
    rename_taps_dir_if_necessary

    each_tap do |user, repo|
      repo.cd do
        updater = Updater.new

        begin
          updater.pull!
        rescue
          onoe t.cmd.update.update_tap_failed(user.basename,
                                              repo.basename.sub("homebrew-", ""))
        else
          report.merge!(updater.report) do |key, oldval, newval|
            oldval.concat(newval)
          end
        end
      end
    end

    # we unlink first in case the formula has moved to another tap
    Homebrew.unlink_tap_formula(report.removed_tapped_formula)
    Homebrew.link_tap_formula(report.new_tapped_formula)

    # automatically tap any migrated formulae's new tap
    report.select_formula(:D).each do |f|
      next unless (HOMEBREW_CELLAR/f).exist?
      migration = TAP_MIGRATIONS[f]
      next unless migration
      tap_user, tap_repo = migration.split '/'
      install_tap tap_user, tap_repo
    end if load_tap_migrations

    if report.empty?
      puts t.cmd.update.already_up_to_date
    else
      puts t.cmd.update.updated_homebrew(master_updater.initial_revision[0,8],
                                         master_updater.current_revision[0,8])
      report.dump
    end
  end

  private

  def git_init_if_necessary
    if Dir['.git/*'].empty?
      safe_system "git init"
      safe_system "git config core.autocrlf false"
      safe_system "git remote add origin https://github.com/Homebrew/homebrew.git"
      safe_system "git fetch origin"
      safe_system "git reset --hard origin/master"
    end

    if `git remote show origin -n` =~ /Fetch URL: \S+mxcl\/homebrew/
      safe_system "git remote set-url origin https://github.com/Homebrew/homebrew.git"
      safe_system "git remote set-url --delete origin .*mxcl\/homebrew.*"
    end
  rescue Exception
    FileUtils.rm_rf ".git"
    raise
  end

  def rename_taps_dir_if_necessary
    need_repair_taps = false
    Dir["#{HOMEBREW_LIBRARY}/Taps/*/"].each do |tapd|
      begin
        tapd_basename = File.basename(tapd)

        if File.directory?(tapd + "/.git")
          if tapd_basename.include?("-")
            # only replace the *last* dash: yes, tap filenames suck
            user, repo = tapd_basename.reverse.sub("-", "/").reverse.split("/")

            FileUtils.mkdir_p("#{HOMEBREW_LIBRARY}/Taps/#{user.downcase}")
            FileUtils.mv(tapd, "#{HOMEBREW_LIBRARY}/Taps/#{user.downcase}/homebrew-#{repo.downcase}")
            need_repair_taps = true

            if tapd_basename.count("-") >= 2
              opoo t.cmd.update.homebrew_tap_structure_1(
                t.cmd.update.homebrew_tap_structure_2(
                  "#{HOMEBREW_LIBRARY}/Taps/#{user.downcase}/"\
                  "homebrew-#{repo.downcase}"
                )
              )
            end
          else
            opoo t.cmd.update.homebrew_tap_structure_1(
              t.cmd.update.homebrew_tap_structure_3(tapd)
            )
          end
        end
      rescue => ex
        onoe ex.message
        next # next tap directory
      end
    end

    repair_taps if need_repair_taps
  end

  def load_tap_migrations
    require 'tap_migrations'
  rescue LoadError
    false
  end
end

class Updater
  attr_reader :initial_revision, :current_revision

  def pull!
    safe_system "git checkout -q master"

    @initial_revision = read_current_revision

    # ensure we don't munge line endings on checkout
    safe_system "git config core.autocrlf false"

    args = ["pull"]
    args << "--rebase" if ARGV.include? "--rebase"
    args << "-q" unless ARGV.verbose?
    args << "origin"
    # the refspec ensures that 'origin/master' gets updated
    args << "refs/heads/master:refs/remotes/origin/master"

    reset_on_interrupt { safe_system "git", *args }

    @current_revision = read_current_revision
  end

  def reset_on_interrupt
    ignore_interrupts { yield }
  ensure
    if $?.signaled? && $?.termsig == 2 # SIGINT
      safe_system "git", "reset", "--hard", @initial_revision
    end
  end

  # Matches raw git diff format (see `man git-diff-tree`)
  DIFFTREE_RX = /^:[0-7]{6} [0-7]{6} [0-9a-fA-F]{40} [0-9a-fA-F]{40} ([ACDMRTUX])\d{0,3}\t(.+?)(?:\t(.+))?$/

  def report
    map = Hash.new{ |h,k| h[k] = [] }

    if initial_revision && initial_revision != current_revision
      `git diff-tree -r --raw -M85% #{initial_revision} #{current_revision}`.each_line do |line|
        DIFFTREE_RX.match line
        path = case status = $1.to_sym
          when :R then $3
          else $2
          end
        map[status] << Pathname.pwd.join(path)
      end
    end

    map
  end

  private

  def read_current_revision
    `git rev-parse -q --verify HEAD`.chomp
  end

  def `(cmd)
    out = Kernel.`(cmd) #`
    if $? && !$?.success?
      $stderr.puts out
      raise ErrorDuringExecution, t.cmd.update.failure_while_executing(cmd)
    end
    ohai(cmd, out) if ARGV.verbose?
    out
  end
end


class Report < Hash

  def dump
    # Key Legend: Added (A), Copied (C), Deleted (D), Modified (M), Renamed (R)

    dump_formula_report :A, t.cmd.update.new_formulae
    dump_formula_report :M, t.cmd.update.updated_formulae
    dump_formula_report :D, t.cmd.update.deleted_formulae
    dump_formula_report :R, t.cmd.update.renamed_formulae
#    dump_new_commands
#    dump_deleted_commands
  end

  def tapped_formula_for key
    fetch(key, []).select do |path|
      case path.relative_path_from(HOMEBREW_REPOSITORY).to_s
      when %r{^Library/Taps/([\w-]+/[\w-]+/.*)}
        valid_formula_location?($1)
      else
        false
      end
    end.compact
  end

  def valid_formula_location?(relative_path)
    ruby_file = /\A.*\.rb\Z/
    parts = relative_path.split('/')[2..-1]
    [
      parts.length == 1 && parts.first =~ ruby_file,
      parts.length == 2 && parts.first == 'Formula' && parts.last =~ ruby_file,
      parts.length == 2 && parts.first == 'HomebrewFormula' && parts.last =~ ruby_file,
    ].any?
  end

  def new_tapped_formula
    tapped_formula_for :A
  end

  def removed_tapped_formula
    tapped_formula_for :D
  end

  def select_formula key
    fetch(key, []).map do |path|
      case path.relative_path_from(HOMEBREW_REPOSITORY).to_s
      when %r{^Library/Formula}
        path.basename(".rb").to_s
      when %r{^Library/Taps/([\w-]+)/(homebrew-)?([\w-]+)/(.*)\.rb}
        "#$1/#$3/#{path.basename(".rb")}"
      end
    end.compact.sort
  end

  def dump_formula_report key, title
    formula = select_formula(key)
    unless formula.empty?
      ohai title
      puts_columns formula.uniq
    end
  end

end
