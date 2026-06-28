{ lib, config, pkgs, ... }:
{
  options = {
    comms = {
      enable = lib.mkEnableOption "Enable communications";
    };
  };
  config = lib.mkIf config.comms.enable {
    home.packages = [
      (lib.mkIf config.desktop.japanese.input.enable (pkgs.symlinkJoin
        {
          name = "signal-desktop";
          paths = [ pkgs.signal-desktop ];
          buildInputs = [ pkgs.makeWrapper ];
          postBuild = ''
            wrapProgram $out/bin/signal-desktop \
                  --add-flags "--enable-wayland-ime=true"
          '';
        }))
      (lib.mkIf (!config.desktop.japanese.input.enable) pkgs.signal-desktop)
    ];
  };
}
