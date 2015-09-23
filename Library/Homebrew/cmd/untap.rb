require "cmd/tap" # for tap_args
require "descriptions"

module Homebrew
  def untap
    raise t("cmd.untap.error_usage") if ARGV.empty?

    ARGV.named.each do |tapname|
      tap = Tap.new(*tap_args(tapname))

      raise TapUnavailableError, tap.name unless tap.installed?
      puts t("cmd.untap.untapping", :name => tap, :abv => tap.path.abv)

      tap.unpin if tap.pinned?

      formula_count = tap.formula_files.size
      Descriptions.uncache_formulae(tap.formula_names)
      tap.path.rmtree
      tap.path.dirname.rmdir_if_possible
      puts t("cmd.untap.untapped_formulae", :count => formula_count)
    end
  end
end
