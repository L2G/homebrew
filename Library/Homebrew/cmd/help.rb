module Homebrew extend self
  def help
    puts t.cmd.help
  end
  def help_s
    t.cmd.help
  end
end
