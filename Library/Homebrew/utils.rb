require "pathname"
require "exceptions"
require "os/mac"
require "utils/json"
require "utils/inreplace"
require "utils/popen"
require "utils/fork"
require "utils/git"
require "open-uri"

class Tty
  class << self
    def blue
      bold 34
    end

    def white
      bold 39
    end

    def red
      underline 31
    end

    def yellow
      underline 33
    end

    def reset
      escape 0
    end

    def em
      underline 39
    end

    def green
      bold 32
    end

    def gray
      bold 30
    end

    def width
      `/usr/bin/tput cols`.strip.to_i
    end

    def truncate(str)
      str.to_s[0, width - 4]
    end

    private

    def color(n)
      escape "0;#{n}"
    end

    def bold(n)
      escape "1;#{n}"
    end

    def underline(n)
      escape "4;#{n}"
    end

    def escape(n)
      "\033[#{n}m" if $stdout.tty?
    end
  end
end

def ohai(title, *sput)
  title = Tty.truncate(title) if $stdout.tty? && !ARGV.verbose?
  puts t('utils.message_colored_w_arrow_colored',
         :message => title,
         :message_color => Tty.white,
         :arrow_color => Tty.blue,
         :reset_color => Tty.reset)
  puts sput
end

def oh1(title)
  title = Tty.truncate(title) if $stdout.tty? && !ARGV.verbose?
  puts t('utils.message_colored_w_arrow_colored',
         :message => title,
         :message_color => Tty.white,
         :arrow_color => Tty.green,
         :reset_color => Tty.reset)
end

# Print a warning (do this rarely)
def opoo(warning)
  $stderr.puts t('utils.message_w_intro_colored',
                 :intro => t('utils.warning'),
                 :message => warning,
                 :intro_color => Tty.yellow,
                 :reset_color => Tty.reset)
end

def onoe(error)
  $stderr.puts t('utils.message_w_intro_colored',
                 :intro => t('utils.error_1'),
                 :message => error,
                 :intro_color => Tty.red,
                 :reset_color => Tty.reset)
end

def ofail(error)
  onoe error
  Homebrew.failed = true
end

def odie(error)
  onoe error
  exit 1
end

def pretty_duration(s)
  return t('utils.seconds', :count => s.to_i) if s < 120
  return t('utils.minutes', :count => (s/6).to_i/10.0)
end

def plural(n, s = "s")
  opoo t('utils.plural_called')
  (n == 1) ? "" : s
end

def interactive_shell(f = nil)
  unless f.nil?
    ENV["HOMEBREW_DEBUG_PREFIX"] = f.prefix
    ENV["HOMEBREW_DEBUG_INSTALL"] = f.full_name
  end

  if ENV["SHELL"].include?("zsh") && ENV["HOME"].start_with?(HOMEBREW_TEMP.resolved_path.to_s)
    FileUtils.touch "#{ENV["HOME"]}/.zshrc"
  end

  Process.wait fork { exec ENV["SHELL"] }

  if $?.success?
    return
  elsif $?.exited?
    puts t('utils.interactive_shell_abort')
    exit $?.exitstatus
  else
    raise $?.inspect
  end
end

module Homebrew
  def self.system(cmd, *args)
    puts "#{cmd} #{args*" "}" if ARGV.verbose?
    pid = fork do
      yield if block_given?
      args.collect!(&:to_s)
      exec({"LC_ALL" => "C"}, cmd, *args) rescue nil # LC_ALL set to quell i18n warnings
      exit! 1 # never gets here unless exec failed
    end
    Process.wait(pid)
    $?.success?
  end

  def self.git_head
    HOMEBREW_REPOSITORY.cd { `git rev-parse --verify -q HEAD 2>/dev/null`.chuzzle }
  end

  def self.git_short_head
    HOMEBREW_REPOSITORY.cd { `git rev-parse --short=4 --verify -q HEAD 2>/dev/null`.chuzzle }
  end

  # Return a string the way `git show -s --format="%cr"` would, e.g. "3 months
  # ago".  The time argument is only needed for testing.
  #
  # Git source reference:
  # https://github.com/git/git/blob/1e6f5b22ad318446500fbd3b94b733eddd5b6414/date.c#L89
  def self.git_last_commit(time = nil)
    HOMEBREW_REPOSITORY.cd do
      last_commit_time = time ||
        Time.at(`git show -s --format="%ct" HEAD 2>/dev/null`.to_i)
      diff = Time.now - last_commit_time

      return t("utils.in_the_future") if diff < 0

      return t("utils.how_long_ago",
               :how_long => t("utils.seconds", :count => diff.to_i)) if diff < 90

      diff = (diff + 30) / 60
      return t("utils.how_long_ago",
               :how_long => t("utils.minutes", :count => diff.to_i)) if diff < 90

      diff = (diff + 30) / 60
      return t("utils.how_long_ago",
               :how_long => t("utils.hours", :count => diff.to_i)) if diff < 36

      diff = ((diff + 12) / 24).to_i
      return t("utils.how_long_ago",
               :how_long => t("utils.days", :count => diff)) if diff < 14

      if diff < 70
        return t("utils.how_long_ago",
                 :how_long => t("utils.weeks", :count => (diff + 3) / 7))
        # No fallthrough
      end

      if diff < 365
        return t("utils.how_long_ago",
                 :how_long => t("utils.months", :count => (diff + 15) / 30))
        # No fallthrough
      end

      total_months = (diff * 12 * 2 + 365) / (365 * 2)
      years = total_months / 12

      if diff < 1825
        months = total_months % 12
        if months == 0
          return t("utils.how_long_ago",
                   :how_long => t("utils.years", :count => years))
        else
          return t("utils.how_long_ago",
                   :how_long =>
                     t("utils.years_with_months",
                       :n_years => t("utils.years", :count => years),
                       :n_months => t("utils.months", :count => months))
                  )
        end
        # No fallthrough
      end

      return t("utils.last_commit_how_long_ago",
               :how_long => t("utils.years", :count => years))
    end
  end

  def self.git_last_commit_date
    HOMEBREW_REPOSITORY.cd { `git show -s --format="%cd" --date=short HEAD 2>/dev/null`.chuzzle }
  end

  def self.homebrew_version_string
    if Utils.git_available? && (pretty_revision = git_short_head)
      last_commit = git_last_commit_date
      "#{HOMEBREW_VERSION} (git revision #{pretty_revision}; last commit #{last_commit})"
    else
      "#{HOMEBREW_VERSION} (no git repository)"
    end
  end

  def self.install_gem_setup_path!(gem, version = nil, executable = gem)
    require "rubygems"
    ENV["PATH"] = "#{Gem.user_dir}/bin:#{ENV["PATH"]}"

    args = [gem]
    args << "-v" << version if version

    unless quiet_system "gem", "list", "--installed", *args
      safe_system "gem", "install", "--no-ri", "--no-rdoc",
                                    "--user-install", *args
    end

    unless which executable
      odie t('utils.gem_installed_but_exec_not_in_path',
             :gem => gem,
             :executable => executable,
             :path => ENV["PATH"])
    end
  end
end

def with_system_path
  old_path = ENV["PATH"]
  ENV["PATH"] = "/usr/bin:/bin"
  yield
ensure
  ENV["PATH"] = old_path
end

def run_as_not_developer(&_block)
  old = ENV.delete "HOMEBREW_DEVELOPER"
  yield
ensure
  ENV["HOMEBREW_DEVELOPER"] = old
end

# Kernel.system but with exceptions
def safe_system(cmd, *args)
  Homebrew.system(cmd, *args) || raise(ErrorDuringExecution.new(cmd, args))
end

# prints no output
def quiet_system(cmd, *args)
  Homebrew.system(cmd, *args) do
    # Redirect output streams to `/dev/null` instead of closing as some programs
    # will fail to execute if they can't write to an open stream.
    $stdout.reopen("/dev/null")
    $stderr.reopen("/dev/null")
  end
end

def curl(*args)
  brewed_curl = HOMEBREW_PREFIX/"opt/curl/bin/curl"
  curl = if MacOS.version <= "10.6" && brewed_curl.exist?
    brewed_curl
  else
    Pathname.new "/usr/bin/curl"
  end
  raise t('utils.not_executable', :path => curl) unless curl.exist? && curl.executable?

  flags = HOMEBREW_CURL_ARGS
  flags = flags.delete("#") if ARGV.verbose?

  args = [flags, HOMEBREW_USER_AGENT, *args]
  args << "--verbose" if ENV["HOMEBREW_CURL_VERBOSE"]
  args << "--silent" unless $stdout.tty?

  safe_system curl, *args
end

def puts_columns(items, star_items = [])
  return if items.empty?

  if star_items && star_items.any?
    items = items.map do |item|
      star_items.include?(item) ? t('utils.item_with_star', :item => item) : item
    end
  end

  if $stdout.tty?
    # determine the best width to display for different console sizes
    console_width = `/bin/stty size`.chomp.split(" ").last.to_i
    console_width = 80 if console_width <= 0
    longest = items.sort_by(&:length).last
    optimal_col_width = (console_width.to_f / (longest.length + 2).to_f).floor
    cols = optimal_col_width > 1 ? optimal_col_width : 1

    IO.popen("/usr/bin/pr -#{cols} -t -w#{console_width}", "w") { |io| io.puts(items) }
  else
    puts items
  end
end

def which(cmd, path = ENV["PATH"])
  path.split(File::PATH_SEPARATOR).each do |p|
    begin
      pcmd = File.expand_path(cmd, p)
    rescue ArgumentError
      # File.expand_path will raise an ArgumentError if the path is malformed.
      # See https://github.com/Homebrew/homebrew/issues/32789
      next
    end
    return Pathname.new(pcmd) if File.file?(pcmd) && File.executable?(pcmd)
  end
  nil
end

def which_editor
  editor = ENV.values_at("HOMEBREW_EDITOR", "VISUAL", "EDITOR").compact.first
  return editor unless editor.nil?

  # Find Textmate
  editor = "mate" if which "mate"
  # Find BBEdit / TextWrangler
  editor ||= "edit" if which "edit"
  # Find vim
  editor ||= "vim" if which "vim"
  # Default to standard vim
  editor ||= "/usr/bin/vim"

  opoo t('utils.using_editor_as_fallback', :editor => editor)

  editor
end

def exec_editor(*args)
  safe_exec(which_editor, *args)
end

def exec_browser(*args)
  browser = ENV["HOMEBREW_BROWSER"] || ENV["BROWSER"] || OS::PATH_OPEN
  safe_exec(browser, *args)
end

def safe_exec(cmd, *args)
  # This buys us proper argument quoting and evaluation
  # of environment variables in the cmd parameter.
  exec "/bin/sh", "-c", "#{cmd} \"$@\"", "--", *args
end

# GZips the given paths, and returns the gzipped paths
def gzip(*paths)
  paths.collect do |path|
    with_system_path { safe_system "gzip", path }
    Pathname.new("#{path}.gz")
  end
end

# Returns array of architectures that the given command or library is built for.
def archs_for_command(cmd)
  cmd = which(cmd) unless Pathname.new(cmd).absolute?
  Pathname.new(cmd).archs
end

def ignore_interrupts(opt = nil)
  std_trap = trap("INT") do
    puts t('utils.cleaning_up') unless opt == :quietly
  end
  yield
ensure
  trap("INT", std_trap)
end

def nostdout
  if ARGV.verbose?
    yield
  else
    begin
      out = $stdout.dup
      $stdout.reopen("/dev/null")
      yield
    ensure
      $stdout.reopen(out)
      out.close
    end
  end
end

def paths
  @paths ||= ENV["PATH"].split(File::PATH_SEPARATOR).collect do |p|
    begin
      File.expand_path(p).chomp("/")
    rescue ArgumentError
      onoe t('utils.path_component_invalid', :path => p)
    end
  end.uniq.compact
end

# return the shell profile file based on users' preference shell
def shell_profile
  case ENV["SHELL"]
  when %r{/(ba)?sh} then "~/.bash_profile"
  when %r{/zsh} then "~/.zshrc"
  when %r{/ksh} then "~/.kshrc"
  else "~/.bash_profile"
  end
end

module GitHub
  extend self
  ISSUES_URI = URI.parse("https://api.github.com/search/issues")

  Error = Class.new(RuntimeError)
  HTTPNotFoundError = Class.new(Error)

  class RateLimitExceededError < Error
    def initialize(reset, error)
      super t('utils.rate_limit_exceeded',
              :error => error,
              :duration => pretty_ratelimit_reset(reset))
    end

    def pretty_ratelimit_reset(reset)
      if (seconds = Time.at(reset) - Time.now) > 60
        t('utils.rate_limit_time_m_s',
          :n_minutes => t('utils.minutes', :count => seconds.to_i / 60),
          :n_seconds => t('utils.seconds', :count => seconds.to_i % 60))
      else
        t('utils.seconds', :count => seconds)
      end
    end
  end

  class AuthenticationFailedError < Error
    def initialize(error)
      super t('utils.authentication_failed', :error => error)
    end
  end

  def open(url, &_block)
    # This is a no-op if the user is opting out of using the GitHub API.
    return if ENV["HOMEBREW_NO_GITHUB_API"]

    require "net/https"

    headers = {
      "User-Agent" => HOMEBREW_USER_AGENT,
      "Accept"     => "application/vnd.github.v3+json"
    }

    headers["Authorization"] = "token #{HOMEBREW_GITHUB_API_TOKEN}" if HOMEBREW_GITHUB_API_TOKEN

    begin
      Kernel.open(url, headers) { |f| yield Utils::JSON.load(f.read) }
    rescue OpenURI::HTTPError => e
      handle_api_error(e)
    rescue EOFError, SocketError, OpenSSL::SSL::SSLError => e
      raise Error,
            t('utils.failed_to_connect', :url => url, :message => e.message),
            e.backtrace
    rescue Utils::JSON::Error => e
      raise Error,
            t('utils.failed_to_parse_json', :message => e.message),
            e.backtrace
    end
  end

  def handle_api_error(e)
    if e.io.meta["x-ratelimit-remaining"].to_i <= 0
      reset = e.io.meta.fetch("x-ratelimit-reset").to_i
      error = Utils::JSON.load(e.io.read)["message"]
      raise RateLimitExceededError.new(reset, error)
    end

    case e.io.status.first
    when "401", "403"
      raise AuthenticationFailedError.new(e.message)
    when "404"
      raise HTTPNotFoundError, e.message, e.backtrace
    else
      raise Error, e.message, e.backtrace
    end
  end

  def issues_matching(query, qualifiers = {})
    uri = ISSUES_URI.dup
    uri.query = build_query_string(query, qualifiers)
    open(uri) { |json| json["items"] }
  end

  def repository(user, repo)
    open(URI.parse("https://api.github.com/repos/#{user}/#{repo}")) { |j| j }
  end

  def build_query_string(query, qualifiers)
    s = "q=#{uri_escape(query)}+"
    s << build_search_qualifier_string(qualifiers)
    s << "&per_page=100"
  end

  def build_search_qualifier_string(qualifiers)
    {
      :repo => "Homebrew/homebrew",
      :in => "title"
    }.update(qualifiers).map do |qualifier, value|
      "#{qualifier}:#{value}"
    end.join("+")
  end

  def uri_escape(query)
    if URI.respond_to?(:encode_www_form_component)
      URI.encode_www_form_component(query)
    else
      require "erb"
      ERB::Util.url_encode(query)
    end
  end

  def issues_for_formula(name)
    issues_matching(name, :state => "open")
  end

  def print_pull_requests_matching(query)
    return [] if ENV["HOMEBREW_NO_GITHUB_API"]
    ohai t('utils.searching_pull_requests')

    open_or_closed_prs = issues_matching(query, :type => "pr")

    open_prs = open_or_closed_prs.select { |i| i["state"] == "open" }
    if open_prs.any?
      puts t('utils.open_pull_requests')
      prs = open_prs
    elsif open_or_closed_prs.any?
      puts t('utils.closed_pull_requests')
      prs = open_or_closed_prs
    else
      return
    end

    prs.each do |i|
      puts t('utils.pull_request_with_url',
             :title => i["title"],
             :html_url => i["html_url"])
    end
  end

  def private_repo?(user, repo)
    uri = URI.parse("https://api.github.com/repos/#{user}/#{repo}")
    open(uri) { |json| json["private"] }
  end
end
