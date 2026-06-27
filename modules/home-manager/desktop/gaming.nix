{ pkgs, config, lib, osConfig, ... }:
let
  ydotoold = "${pkgs.ydotool}/bin/ydotoold";
in
{
  options.desktop.gaming.enable = lib.mkEnableOption "Enable gaming";
  config = lib.mkIf config.desktop.gaming.enable {
    home.packages = with pkgs; [
      pkgs.r2modman
      (pkgs.writeShellScriptBin "steam" ''
        ${pkgs.flatpak}/bin/flatpak run com.valvesoftware.Steam -silent "$@"
      '')
    ];
    services.flatpak = {
      packages = [
        " com.valvesoftware.Steam "
        " net.lutris.Lutris "
        " org.prismlauncher.PrismLauncher "
        " net.veloren.airshipper "
      ];
      overrides = {
        "org.prismlauncher.PrismLauncher" = {
          Context = {
            filesystems = [
              "xdg-data/applications:create"
            ];
          };
        };
        "com.valvesoftware.Steam" = {
          Context = {
            filesystems = [
              "xdg-config/r2modmanPlus-local:rw"
              "xdg-data/icons:create"
              "xdg-data/applications:create"
            ];
            device = [
              "dri"
            ];
          };
        };
        "net.lutris.Lutris" = {
          Context = {
            filesystems = [
              "xdg-data/icons:create"
              "~/.var/app/com.valvesoftware.Steam:create"
              "~/.steam:create"
              "xdg-desktop:create"
            ];
          };
        };
      };
    };
    programs.zsh.shellAliases.stardewmacro = lib.mkIf osConfig.programs.hyprland.enable "hyprctl keyword bind ',mouse:276,exec,env YDOTOOL_SOCKET=/run/user/1000/.$ ydotool key 54:1 111:1 19:1 19:0 54:0 111:0' && ${ydotoold}";
  };
}

