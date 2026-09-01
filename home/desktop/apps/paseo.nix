{ config, lib, pkgs, ... }:
# Paseo — open-source parallel coding-agent workspace (github:getpaseo/paseo).
# Runs Claude Code/Codex/Copilot/OpenCode/Pi in isolated git worktrees with a
# dashboard, similar niche to Orca. Not in nixpkgs; upstream ships an
# Electron AppImage, so wrap it with appimageTools like orca.nix.
let
  pname = "paseo";
  version = "0.6.1";

  src = pkgs.fetchurl {
    url = "https://github.com/getpaseo/paseo/releases/download/v${version}/Paseo-x86_64.AppImage";
    hash = "sha256-4kdgpqMHsSthLVCAEd7rLzWeiHJS2ZQDzk5iLeHcRGU=";
  };

  contents = pkgs.appimageTools.extract { inherit pname version src; };

  paseo = pkgs.appimageTools.wrapType2 {
    inherit pname version src;

    extraPkgs = p: with p; [
      libsecret          # keyring access for stored credentials
      libnotify
      at-spi2-core
    ];

    extraInstallCommands = ''
      install -Dm444 ${contents}/Paseo.desktop \
        $out/share/applications/${pname}.desktop
      substituteInPlace $out/share/applications/${pname}.desktop \
        --replace-fail 'Exec=AppRun' 'Exec=${pname}'
      cp -r ${contents}/usr/share/icons $out/share/
    '';

    meta = {
      description = "Open-source desktop app for running coding agents in parallel git worktrees";
      homepage = "https://github.com/getpaseo/paseo";
      platforms = [ "x86_64-linux" ];
      mainProgram = pname;
    };
  };
in
{
  config = {
    home.packages = [ paseo ];
  };
}
