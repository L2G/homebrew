require 'formula'

class Readline < Formula
  homepage 'http://tiswww.case.edu/php/chet/readline/rltop.html'
  url 'http://ftpmirror.gnu.org/readline/readline-6.3.tar.gz'
  mirror 'http://ftp.gnu.org/gnu/readline/readline-6.3.tar.gz'
  sha256 '56ba6071b9462f980c5a72ab0023893b65ba6debb4eeb475d7a563dc65cafd43'
  version '6.3.5'

  bottle do
    cellar :any
    sha1 "f18f34972c5164ea4cb94b3311e52fc04ea4b9a9" => :mavericks
    sha1 "131d59e8bb99e5a9d0270a04e63c07d794750695" => :mountain_lion
    sha1 "b119b5a05f21f9818b6c99e173597fba62d89b58" => :lion
  end

  keg_only <<-EOS
OS X provides the BSD libedit library, which shadows libreadline.
In order to prevent conflicts when programs look for libreadline we are
defaulting this GNU Readline installation to keg-only.
EOS

  # Vendor the patches.
  # The mirrors are unreliable for getting the patches, and the more patches
  # there are, the more unreliable they get. Pulling this patch inline to
  # reduce bug reports.
  # Upstream patches can be found in:
  # http://git.savannah.gnu.org/cgit/readline.git
  patch do
    url "https://gist.githubusercontent.com/jacknagel/8df5735ae9273bf5ebb2/raw/827805aa2927211e7c3d9bb871e75843da686671/readline.diff"
    sha1 "2d55658a2f01fa14a029b16fea29d20ce7d03b78"
  end

  def install
    # Always build universal, per https://github.com/Homebrew/homebrew/issues/issue/899
    ENV.universal_binary
    system "./configure", "--prefix=#{prefix}",
                          "--mandir=#{man}",
                          "--infodir=#{info}",
                          "--enable-multibyte"
    system "make install"
  end
end
