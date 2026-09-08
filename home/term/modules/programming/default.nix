{ config, lib, pkgs, inputs, osConfig, ... }:
let
  # Depot CLI (depot.dev) -- remote build acceleration for Docker/container
  # builds. Not in nixpkgs; upstream ships a static Go binary tarball, no
  # patching needed (single static executable, no dynamic deps).
  depot-cli = pkgs.stdenv.mkDerivation rec {
    pname = "depot";
    version = "2.102.7";

    src = pkgs.fetchurl {
      url = "https://github.com/depot/cli/releases/download/v${version}/depot_${version}_linux_amd64.tar.gz";
      hash = "sha256-V2/403jIp0Ygth2BNRPlKG8gWc3kWW46MezMIAWnRmk=";
    };

    sourceRoot = ".";

    installPhase = ''
      install -Dm755 bin/depot $out/bin/depot
    '';

    meta = {
      description = "Remote build acceleration for Docker/container builds";
      homepage = "https://depot.dev";
      platforms = [ "x86_64-linux" ];
      mainProgram = "depot";
    };
  };
in
{
  imports = [
    ./python
  ];
  options = {
    programming = {
      enable = lib.mkEnableOption "Enable programming";
      R.enable = lib.mkEnableOption "Enable R";
    };
  };
  config = lib.mkIf config.programming.enable {
    programming = {
      python.enable = lib.mkDefault true;
      # R pulls ~1G; install on-demand with `nix-shell -p R` when needed.
      R.enable = lib.mkDefault false;
    };



    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
      enableZshIntegration = true; # Set to true if you use zsh
      enableBashIntegration = true; # Set to true if you use bash
      silent = true;
    };



    home.packages = with pkgs; [
      uv
      nodejs
      gh
      depot-cli
      (lib.mkIf config.programming.R.enable R)
    ];
  };
}
