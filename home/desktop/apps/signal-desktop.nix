{ lib, pkgs, inputs, ... }:
# Signal Desktop: whichever is newer of nixpkgs-unstable's build and
# Signal's own release, pinned below.
#
# nixpkgs builds Signal from source and lags upstream by days (8.32.0 shipped
# 2026-10-20; nixpkgs-unstable still had 8.31.0 on 2026-10-24), and every
# Signal release expires 90 days after it ships. The official .deb bridges
# that gap.
#
# The pin never holds Signal back: once nixpkgs reaches the pinned version,
# nixpkgs wins and the official build drops out by itself. Signal must never
# go backwards, because it migrates its database forward and refuses one a
# newer version wrote (DBVersionFromFutureError; see fe7f0c2).
#
# To bump: copy Version and SHA256 of the signal-desktop entry from
#   https://updates.signal.org/desktop/apt/dists/xenial/main/binary-amd64/Packages
let
  official = pkgs.stdenv.mkDerivation rec {
    pname = "signal-desktop";
    version = "8.32.0";

    src = pkgs.fetchurl {
      url = "https://updates.signal.org/desktop/apt/pool/s/signal-desktop/signal-desktop_${version}_amd64.deb";
      sha256 = "5cbca1616cac7273fd1f06b62d3e0e6a23088252dd11bbcdb4b6a3eb28d7c8de";
    };

    nativeBuildInputs = with pkgs; [ dpkg autoPatchelfHook wrapGAppsHook3 ];

    buildInputs = with pkgs; [
      alsa-lib at-spi2-atk at-spi2-core atk cairo cups dbus expat fontconfig
      freetype gdk-pixbuf glib gtk3 libappindicator-gtk3 libgbm libnotify
      libpulseaudio libuuid nspr nss pango systemd
      xorg.libX11 xorg.libXScrnSaver xorg.libXcomposite xorg.libXcursor
      xorg.libXdamage xorg.libXext xorg.libXfixes xorg.libXi xorg.libXrandr
      xorg.libXrender xorg.libXtst xorg.libxcb xorg.libxshmfence
    ];

    # dlopen()ed at run time, so autoPatchelf cannot see them.
    runtimeDependencies = with pkgs; [
      (lib.getLib systemd) libappindicator-gtk3 libnotify libdbusmenu
      pipewire wayland
    ];

    unpackPhase = "dpkg-deb --fsys-tarfile $src | tar -x --no-same-owner --no-same-permissions";
    dontBuild = true;
    dontConfigure = true;

    installPhase = ''
      runHook preInstall

      mkdir -p $out/lib $out/bin $out/share/polkit-1/actions
      mv opt/Signal $out/lib/signal-desktop
      mv usr/share/{applications,icons} $out/share/
      # Setuid helper; the store cannot hold setuid files, and Electron uses
      # unprivileged user namespaces instead.
      rm $out/lib/signal-desktop/chrome-sandbox
      cp $out/lib/signal-desktop/resources/*.policy $out/share/polkit-1/actions/
      ln -s $out/lib/signal-desktop/signal-desktop $out/bin/signal-desktop

      # Same desktop file name and Exec as nixpkgs' build.
      mv $out/share/applications/signal{-desktop,}.desktop
      substituteInPlace $out/share/applications/signal.desktop \
        --replace-fail "/opt/Signal/signal-desktop" signal-desktop

      runHook postInstall
    '';

    preFixup = ''
      gappsWrapperArgs+=(--suffix PATH : ${lib.makeBinPath [ pkgs.xdg-utils ]})
      patchelf --add-needed ${pkgs.libpulseaudio}/lib/libpulse.so \
        $out/lib/signal-desktop/resources/app.asar.unpacked/node_modules/@signalapp/ringrtc/build/linux/libringrtc-x64.node
    '';

    meta = {
      description = "Signal Desktop, Signal's official build";
      homepage = "https://signal.org/";
      license = lib.licenses.agpl3Only;
      mainProgram = "signal-desktop";
      platforms = [ "x86_64-linux" ];
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    };
  };

  fromNixpkgs = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.signal-desktop;
in
{
  home.packages = [
    (if lib.versionAtLeast fromNixpkgs.version official.version then fromNixpkgs else official)
  ];
}
