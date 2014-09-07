require "formula"

class Readline < Formula
  homepage "http://tiswww.case.edu/php/chet/readline/rltop.html"
  url "http://ftpmirror.gnu.org/readline/readline-6.3.tar.gz"
  mirror "http://ftp.gnu.org/gnu/readline/readline-6.3.tar.gz"
  sha256 "56ba6071b9462f980c5a72ab0023893b65ba6debb4eeb475d7a563dc65cafd43"
  version "6.3.6"

  bottle do
    cellar :any
    sha1 "63bfa23f0b192827b7b021707f391b34346ec4e3" => :mavericks
    sha1 "968e8b5a125aff9c78b585c0fadefaf6cc5bc7b9" => :mountain_lion
    sha1 "56a126196db602b61f73cb1152a257bb04148fcf" => :lion
  end

  keg_only :shadowed_by_osx, <<-EOS
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
    url "https://gist.githubusercontent.com/jacknagel/d886531fb6623b60b2af/raw/d6aec221e7369ea152e64c8af83f6b048433dd82/readline-6.3.6.diff"
    sha1 "774e4d3fe8c22dc715b430343d68beecf6f4e673"
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
