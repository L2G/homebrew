class Riemann < Formula
  homepage "http://riemann.io"
  url "http://aphyr.com/riemann/riemann-0.2.9.tar.bz2"
  sha256 "8363e936d5c31d879a7e725e6c8fe41f1a1627b90530a7fb7968aaf4b448ff83"

  def shim_script
    <<-EOS.undent
      #!/bin/bash
      if [ -z "$1" ]
      then
        config="#{etc}/riemann.config"
      else
        config=$@
      fi
      exec "#{libexec}/bin/riemann" "$config"
    EOS
  end

  def install
    etc.install "etc/riemann.config" => "riemann.config.guide"

    # Install jars in libexec to avoid conflicts
    libexec.install Dir["*"]

    (bin+"riemann").write shim_script
  end

  def caveats; <<-EOS.undent
    You may also wish to install these Ruby gems:
      riemann-client
      riemann-tools
      riemann-dash
    EOS
  end

  def plist; <<-EOS.undent
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
      <dict>
        <key>KeepAlive</key>
        <true/>
        <key>Label</key>
        <string>#{plist_name}</string>
        <key>ProgramArguments</key>
        <array>
          <string>#{opt_bin}/riemann</string>
          <string>#{etc}/riemann.config</string>
        </array>
        <key>RunAtLoad</key>
        <true/>
        <key>StandardErrorPath</key>
        <string>#{var}/log/riemann.log</string>
        <key>StandardOutPath</key>
        <string>#{var}/log/riemann.log</string>
      </dict>
    </plist>
    EOS
  end

  test do
    system "#{bin}/riemann", "-help", "0"
  end
end
