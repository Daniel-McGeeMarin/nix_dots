{ pkgs, lib, inputs, config, secrets, ... }:
let
  brightnessctl = "${pkgs.brightnessctl}/bin/brightnessctl";
  socat = "${pkgs.socat}/bin/socat";
  hyprctl = "${pkgs.hyprland}/bin/hyprctl";
  hyprWorkspaceCycle = pkgs.writeShellScriptBin "hypr-workspace-cycle" (builtins.readFile ./hypr-workspace-cycle.sh);
  hyprWorkspaceNext = pkgs.writeShellScriptBin "hypr-workspace-next" ''exec "${hyprWorkspaceCycle}/bin/hypr-workspace-cycle" next'';
  hyprWorkspacePrev = pkgs.writeShellScriptBin "hypr-workspace-prev" ''exec "${hyprWorkspaceCycle}/bin/hypr-workspace-cycle" prev'';
in
{
  imports = [
    ./base.nix
    ./binds.nix
    ./rules.nix
  ];

  programs.rofi.enable = true;

  xdg.desktopEntries."org.gnome.Settings" = {
    name = "Settings";
    comment = "Gnome Control Center";
    icon = "org.gnome.Settings";
    exec = "env XDG_CURRENT_DESKTOP=gnome ${pkgs.gnome-control-center}/bin/gnome-control-center";
    categories = [ "X-Preferences" ];
    terminal = false;
  };

  home.sessionVariables = {
    WLR_NO_HARDWARE_CURSORS = "1";
    XCURSOR_SIZE = "48";
    NIXOS_OZONE_WL = "1";
  };

  home.packages = [
    hyprWorkspaceCycle
    hyprWorkspaceNext
    hyprWorkspacePrev
    inputs.nixpkgs-unstable.legacyPackages.${pkgs.system}.nwg-drawer
    pkgs.wtype
    pkgs.grimblast
    pkgs.ydotool
    pkgs.grim
    pkgs.slurp
    (pkgs.writeShellScriptBin "devbright" ''
      val=$(${brightnessctl} get)
      max=$(${brightnessctl} max)
      h="$(printf "%02x\n" "$((val*255/max))")"
      mice=$(${pkgs.libratbag}/bin/ratbagctl | ${pkgs.coreutils-full}/bin/cut -d: -f1)
      if [[ -n $mice ]]; then
        while read -r mouse; do
          ${pkgs.libratbag}/bin/ratbagctl "$mouse" led 0 set color "$h$h$h"
        done <<< "$mice"
      fi
    '')
    (pkgs.writeShellScriptBin "bwfloat" ''
      windowtitlev2() {
        IFS=',' read -r -a args <<< "$1"
        args[0]="''${args[0]#*>>}"
        if [[ ''${args[1]} == "Extension: (Bitwarden Password Manager) - — LibreWolf" ]]; then
          ${hyprctl} --batch "\
            dispatch setfloating address:0x''${args[0]}; \
            dispatch resizewindowpixel exact 20% 50%, address:0x''${args[0]}; \
            dispatch centerwindow; \
          "
        fi
      }
      handle() {
        case $1 in
          windowtitlev2\>*) windowtitlev2 "$1" ;;
        esac
      }
      ${socat} -U - UNIX-CONNECT:"/$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" \
        | while read -r line; do handle "$line"; done
    '')
    (pkgs.writeShellScriptBin "qshot" ''
      ${pkgs.grim}/bin/grim -g "$(${pkgs.slurp}/bin/slurp)" "/tmp/clip.png" &&\
      ${pkgs.wl-clipboard}/bin/wl-copy < /tmp/clip.png
    '')
    (pkgs.writeShellScriptBin "hyprperf" ''
      HYPRGAMEMODE=$(hyprctl getoption animations:enabled | awk 'NR==1{print $2}')
      if [ "$HYPRGAMEMODE" = 1 ] ; then
          hyprctl --batch "\
              keyword animations:enabled 0;\
              keyword decoration:shadow:enabled 0;\
              keyword decoration:blur:enabled 0;\
              keyword general:gaps_in 0;\
              keyword general:gaps_out 0;\
              keyword general:border_size 1;\
              keyword decoration:rounding 0"
          exit
      fi
      hyprctl reload
    '')
    (pkgs.writeShellScriptBin "swapcaps" ''
      HYPRGAMEMODE=$(hyprctl getoption input:kb_options | awk 'NR==1{print $2}')
      if [ "$HYPRGAMEMODE" = "caps:swapescape" ] ; then
          hyprctl keyword input:kb_options ""
          exit
      fi
      hyprctl reload
    '')
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    plugins = [
      pkgs.hyprlandPlugins.hyprgrass
      pkgs.hyprlandPlugins.hyprspace
    ];
  };
}
