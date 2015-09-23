HOMEBREW_HELP = t('cmd.help')

module Homebrew
  def help
    puts HOMEBREW_HELP
  end

  def help_s
    HOMEBREW_HELP
  end
end
