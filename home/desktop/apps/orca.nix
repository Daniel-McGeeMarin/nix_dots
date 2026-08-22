{ config, lib, pkgs, ... }:
# Orca — Stably's agent development environment (github:stablyai/orca).
# Not in nixpkgs; upstream ships an Electron AppImage, so wrap it with
# appimageTools. Binary is `orca-ide` (pkgs.orca is the GNOME screen reader).
let
  pname = "orca-ide";
  version = "1.4.184";

  src = pkgs.fetchurl {
    url = "https://github.com/stablyai/orca/releases/download/v${version}/orca-linux.AppImage";
    hash = "sha256-we74NUJ9DVCsGCQmsSiwIRfMQEOmO/A+g+5VeJQ/T6g=";
  };

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
