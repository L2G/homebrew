class Flactag < Formula
  desc "Tag single album FLAC files with MusicBrainz CUE sheets"
  homepage "http://flactag.sourceforge.net/"
  url "https://downloads.sourceforge.net/project/flactag/v2.0.4/flactag-2.0.4.tar.gz"
  sha256 "c96718ac3ed3a0af494a1970ff64a606bfa54ac78854c5d1c7c19586177335b2"
  revision 1

  depends_on "pkg-config" => :build
  depends_on "asciidoc" => :build
  depends_on "flac"
  depends_on "libmusicbrainz"
  depends_on "neon"
  depends_on "libdiscid"
  depends_on "s-lang"
  depends_on "unac"
  depends_on "jpeg"

  # Fix a compilation error by typecasting a "bool" value to "boolean"
  # Upstream ticket: https://sourceforge.net/p/flactag/patches/2/
  patch :DATA

  def install
    ENV["XML_CATALOG_FILES"] = "#{etc}/xml/catalog"
    ENV.append "LDFLAGS", "-liconv"
    ENV.append "LDFLAGS", "-lFLAC"
    system "./configure", "--disable-dependency-tracking",
                          "--prefix=#{prefix}"
    system "make", "install"
  end

  test do
    system "#{bin}/flactag"
  end
end

__END__
diff --git a/CoverArt.cc b/CoverArt.cc
index e730476..15cca7e 100644
--- a/CoverArt.cc
+++ b/CoverArt.cc
@@ -195,7 +195,7 @@ boolean CCoverArt::FillInputBuffer(j_decompress_ptr cinfo)
	src->pub.next_input_byte = src->eoi_buffer;
	src->pub.bytes_in_buffer = 2;

-	return true;
+	return (boolean)true;
 }

 void CCoverArt::SkipInputData(j_decompress_ptr cinfo, long num_bytes)
