require "formula"

class Readline < Formula
  homepage "http://tiswww.case.edu/php/chet/readline/rltop.html"
  url "http://ftpmirror.gnu.org/readline/readline-6.3.tar.gz"
  mirror "http://ftp.gnu.org/gnu/readline/readline-6.3.tar.gz"
  sha256 "56ba6071b9462f980c5a72ab0023893b65ba6debb4eeb475d7a563dc65cafd43"
  version "6.3.8"

  bottle do
    cellar :any
    sha1 "d8bec6237197bfff8535cd3ac10c18f2e4458a2a" => :yosemite
    sha1 "d530f4e966bb9c654a86f5cc0e65b20b1017aef2" => :mavericks
    sha1 "7473587d992d8c3eb37afe6c3e0adc3587c977f1" => :mountain_lion
    sha1 "e84f9cd95503b284651ef24bc8e7da30372687d3" => :lion
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
    url "https://gist.githubusercontent.com/jacknagel/d886531fb6623b60b2af/raw/746fc543e56bc37a26ccf05d2946a45176b0894e/readline-6.3.8.diff"
    sha1 "dccc973e4a75ecfe45c25c296e0f7785b06586dc"
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
