class Htmldoc < Formula
  desc "Convert HTML to PDF or PostScript"
  homepage "http://www.msweet.org/projects.php?Z1"
  url "http://www.msweet.org/files/project1/htmldoc-1.8.28-source.tar.bz2"
  sha256 "2a688bd820ad6f7bdebb274716102dafbf4d5fcfa20a5b8d87a56b030d184732"
  revision 2

  depends_on "libpng"
  depends_on "jpeg"

  # Patch for stricter Boolean values required by jpeg library 9a.
  # Upstream ticket: https://www.msweet.org/bugs.php?U507
  patch :DATA

  def install
    system "./configure", "--disable-debug",
                          "--prefix=#{prefix}",
                          "--mandir=#{man}"
    system "make"
    system "make", "install"
  end

  test do
    assert_match(/^#{version}$/, shell_output("#{bin}/htmldoc --version"))
  end
end

__END__
diff --git a/htmldoc/image.cxx b/htmldoc/image.cxx
index 6a2fcbd..77cb9cc 100644
--- a/htmldoc/image.cxx
+++ b/htmldoc/image.cxx
@@ -1382,7 +1382,7 @@ image_load_jpeg(image_t *img,	/* I - Image pointer */
   jpeg_stdio_src(&cinfo, fp);
   jpeg_read_header(&cinfo, (boolean)1);

-  cinfo.quantize_colors = 0;
+  cinfo.quantize_colors = FALSE;

   if (gray || cinfo.num_components == 1)
   {
