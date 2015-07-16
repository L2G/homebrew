class Fltk < Formula
  desc "Cross-platform C++ GUI toolkit"
  homepage "http://www.fltk.org/"
  url "https://fossies.org/linux/misc/fltk-1.3.3-source.tar.gz"
  sha256 "f8398d98d7221d40e77bc7b19e761adaf2f1ef8bb0c30eceb7beb4f2273d0d97"
  revision 1

  bottle do
    sha1 "33c75cce41deadbfe54bdcc22ae91d17d3ecc782" => :mavericks
    sha1 "3674769086a1a667379c94aa50aa59b5f66f75d3" => :mountain_lion
  end

  option :universal

  depends_on "libpng"
  depends_on "jpeg"

  fails_with :clang do
    build 318
    cause "http://llvm.org/bugs/show_bug.cgi?id=10338"
  end

  # Fixes a couple of issues:
  # * issue with -lpng not found (patch based on
  #   https://trac.macports.org/browser/trunk/dports/aqua/fltk/files/patch-src-Makefile.diff)
  # * jpeg_read_header() from jpeg library called with integer instead of boolean
  patch :DATA

  def install
    ENV.universal_binary if build.universal?
    system "./configure", "--prefix=#{prefix}",
                          "--enable-threads",
                          "--enable-shared"
    system "make", "install"
  end

  test do
    output = shell_output("#{bin}/fltk-config --version")
    assert_equal "#{version}\n", output
  end
end

__END__
diff --git a/src/Makefile b/src/Makefile
index fcad5f0..5a5a850 100644
--- a/src/Makefile
+++ b/src/Makefile
@@ -360,7 +360,7 @@ libfltk_images.1.3.dylib: $(IMGOBJECTS) libfltk.1.3.dylib
 		-install_name $(libdir)/$@ \
 		-current_version 1.3.1 \
 		-compatibility_version 1.3.0 \
-		$(IMGOBJECTS)  -L. $(LDLIBS) $(IMAGELIBS) -lfltk
+		$(IMGOBJECTS)  -L. $(LDLIBS) $(IMAGELIBS) -lfltk $(LDFLAGS)
 	$(RM) libfltk_images.dylib
 	$(LN) libfltk_images.1.3.dylib libfltk_images.dylib

diff --git a/src/Fl_JPEG_Image.cxx b/src/Fl_JPEG_Image.cxx
index 179ade6..ede4ed4 100644
--- a/src/Fl_JPEG_Image.cxx
+++ b/src/Fl_JPEG_Image.cxx
@@ -155,7 +155,7 @@ Fl_JPEG_Image::Fl_JPEG_Image(const char *filename)	// I - File to load

   jpeg_create_decompress(&dinfo);
   jpeg_stdio_src(&dinfo, fp);
-  jpeg_read_header(&dinfo, 1);
+  jpeg_read_header(&dinfo, TRUE);

   dinfo.quantize_colors      = (boolean)FALSE;
   dinfo.out_color_space      = JCS_RGB;
@@ -337,7 +337,7 @@ Fl_JPEG_Image::Fl_JPEG_Image(const char *name, const unsigned char *data)

   jpeg_create_decompress(&dinfo);
   jpeg_mem_src(&dinfo, data);
-  jpeg_read_header(&dinfo, 1);
+  jpeg_read_header(&dinfo, TRUE);

   dinfo.quantize_colors      = (boolean)FALSE;
   dinfo.out_color_space      = JCS_RGB;
