{ stdenv
, lib
, buildFHSUserEnv
, fetchurl
, gsettings-desktop-schemas
, makeDesktopItem
, makeWrapper
, writeTextDir
, configText ? ""
}:
let
  version = "2111";

  sysArch =
    if stdenv.hostPlatform.system == "x86_64-linux" then "x64"
    else throw "Unsupported system: ${stdenv.hostPlatform.system}";
  # The downloaded archive also contains ARM binaries, but these have not been tested.

  # For USB support, ensure that /var/run/vmware/<YOUR-UID>
  # exists and is owned by you. Then run vmware-usbarbitrator as root.
  bins = [ "vmware-view" "vmware-usbarbitrator" ];

  # This forces the default GTK theme (Adwaita) because Horizon is prone to
  # UI usability issues when using non-default themes, such as Adwaita-dark.
  wrapBinCommands = name: ''
    makeWrapper "$out/bin/${name}" "$out/bin/${name}_wrapper" \
    --set GTK_THEME Adwaita \
    --suffix XDG_DATA_DIRS : "${gsettings-desktop-schemas}/share/gsettings-schemas/${gsettings-desktop-schemas.name}" \
    --suffix LD_LIBRARY_PATH : "$out/lib/vmware/view/crtbora:$out/lib/vmware"
  '';

  vmwareHorizonClientFiles = stdenv.mkDerivation {
    name = "vmwareHorizonClientFiles";
    inherit version;
    src = fetchurl {
      url = "https://download3.vmware.com/software/view/viewclients/CART22FH2/VMware-Horizon-Client-Linux-2111-8.4.0-18957622.tar.gz";
      sha256 = "2f79d2d8d34e6f85a5d21a3350618c4763d60455e7d68647ea40715eaff486f7";
    };
    nativeBuildInputs = [ makeWrapper ];
    installPhase = ''
      mkdir ext $out
      find ${sysArch} -type f -print0 | xargs -0n1 tar -Cext --strip-components=1 -xf
      mv ext/bin ext/lib ext/share "$out"/

      # Horizon includes a copy of libstdc++ which is loaded via $LD_LIBRARY_PATH
      # when it cannot detect a new enough version already present on the system.
      # The checks are distribution-specific and do not function correctly on NixOS.
      # Deleting the bundled library is the simplest way to force it to use our version.
      rm "$out/lib/vmware/gcc/libstdc++.so.6"

      # This library causes the program to core-dump occasionally. Use ours instead.
      rm $out/lib/vmware/view/crtbora/libcairo.*

      ${lib.concatMapStrings wrapBinCommands bins}
    '';
  };

  vmwareFHSUserEnv = name: buildFHSUserEnv {
    inherit name;

    runScript = "${vmwareHorizonClientFiles}/bin/${name}_wrapper";

    targetPkgs = pkgs: with pkgs; [
      at-spi2-atk
      atk
      cairo
      dbus
      fontconfig
      freetype
      gdk-pixbuf
      glib
      gtk2
      gtk3-x11
      harfbuzz
      liberation_ttf
      libjpeg
      libpulseaudio
      libtiff
      libudev0-shim
      libuuid
      libv4l
      libxml2
      pango
      pcsclite
      pixman
      vmwareHorizonClientFiles
      xorg.libX11
      xorg.libXcursor
      xorg.libXext
      xorg.libXi
      xorg.libXinerama
      xorg.libxkbfile
      xorg.libXrandr
      xorg.libXrender
      xorg.libXScrnSaver
      xorg.libXtst
      zlib

      (writeTextDir "etc/vmware/config" configText)
    ];
  };

  desktopItem = makeDesktopItem {
    name = "vmware-view";
    desktopName = "VMware Horizon Client";
    icon = "${vmwareHorizonClientFiles}/share/icons/vmware-view.png";
    exec = "${vmwareFHSUserEnv "vmware-view"}/bin/vmware-view %u";
    mimeTypes = [ "x-scheme-handler/vmware-view" ];
  };

  binLinkCommands = lib.concatMapStringsSep
    "\n"
    (bin: "ln -s ${vmwareFHSUserEnv bin}/bin/${bin} $out/bin/")
    bins;

in
stdenv.mkDerivation {
  name = "vmware-horizon-client";

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/bin $out/share/applications
    cp ${desktopItem}/share/applications/* $out/share/applications/
    ${binLinkCommands}
  '';

  unwrapped = vmwareHorizonClientFiles;

  passthru.updateScript = ./update.sh;

  meta = with lib; {
    mainProgram = "vmware-view";
    description = "Allows you to connect to your VMware Horizon virtual desktop";
    homepage = "https://www.vmware.com/go/viewclients";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
    maintainers = with maintainers; [ buckley310 ];
  };
}
