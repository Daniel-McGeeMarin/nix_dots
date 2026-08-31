{ config, lib, pkgs, ... }:
# Orca — Stably's agent development environment (github:stablyai/orca).
# Not in nixpkgs; upstream ships an Electron AppImage, so wrap it with
# appimageTools. Binary is `orca-ide` (pkgs.orca is the GNOME screen reader).
#
# CUSTOM BUILD, not the official release. This is built from stablyai/orca
# PR #15836 (cunicopia-dev/orca, branch feat/terminal-background-image,
# commit a7236a1b), which adds terminalBackgroundImage /
# terminalBackgroundImageOpacity / terminalBackgroundImageFit settings --
# background images behind terminal panes. The PR is open but unreviewed
# upstream (as of 2026-08-31); this is not an official Stably build.
#
# Tradeoff: the PR branch was cut from an older point in Orca's history
# than the official release above (package.json reports 1.4.178-rc.2 vs
# the 1.4.190 official build this replaces) -- so this trades ~12 versions
# of upstream fixes for the one feature. Auto-update is also effectively
# off: the app's own updater still points at the real release feed, but
# nothing here re-fetches from it, so this binary only changes when
# re-built by hand.
#
# The AppImage itself was built outside Nix (pnpm install && pnpm run
# build:linux needs network access for deps + Electron download, which
# Nix's sandboxed build doesn't allow without real pnpm2nix-style
# packaging) and is stored locally, not in git -- 200MB+ binaries don't
# belong in version control, and this isn't independently reproducible
# from this repo alone. To rebuild after the PR updates or to move to a
# newer base:
#   git clone https://github.com/cunicopia-dev/orca.git -b feat/terminal-background-image
#   cd orca && pnpm install && pnpm run build:linux
#   cp dist/orca-linux.AppImage ~/MyApps/orca-custom/orca-linux-bgimage.AppImage
# then rebuild this flake.
let
  pname = "orca-ide";
  version = "1.4.178-rc.2-bgimage";

  src = /home/xia/MyApps/orca-custom/orca-linux-bgimage.AppImage;

  contents = pkgs.appimageTools.extract { inherit pname version src; };

  orca = pkgs.appimageTools.wrapType2 {
    inherit pname version src;

    extraPkgs = p: with p; [
      libsecret          # keyring access for stored credentials
      libnotify
      at-spi2-core
    ];

    extraInstallCommands = ''
      install -Dm444 ${contents}/${pname}.desktop \
        $out/share/applications/${pname}.desktop
      substituteInPlace $out/share/applications/${pname}.desktop \
        --replace-fail 'Exec=AppRun' 'Exec=${pname}'
      cp -r ${contents}/usr/share/icons $out/share/
    '';

    meta = {
      description = "Next-gen IDE for parallel agentic development";
      homepage = "https://github.com/stablyai/orca";
      platforms = [ "x86_64-linux" ];
      mainProgram = pname;
    };
  };
in
{
  config = lib.mkIf config.desktop.enable {
    home.packages = [ orca ];
  };
}
