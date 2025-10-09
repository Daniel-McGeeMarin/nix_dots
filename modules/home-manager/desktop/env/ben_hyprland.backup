{ pkgs, lib, inputs, config, osConfig, ... }:

let
  playerctl = "${pkgs.playerctl}/bin/playerctl";
  brightnessctl = "${pkgs.brightnessctl}/bin/brightnessctl";
  pactl = "${pkgs.pulseaudio}/bin/pactl";
  socat = "${pkgs.socat}/bin/socat";
  hyprctl = "${pkgs.hyprland}/bin/hyprctl";
in
{
  imports = [
    wm/rofi
    wm/hyprpaper.nix
    wm/waybar
  ];
  config = lib.mkIf osConfig.programs.hyprland.enable {
    programs.rofi.enable = true;
    services.hyprpaper.enable = true;
    programs.waybar.enable = true;
    xdg = {
      desktopEntries."org.gnome.Settings" = {
        name = "Settings";
        comment = "Gnome Control Center";
        icon = "org.gnome.Settings";
        exec = "env XDG_CURRENT_DESKTOP=gnome ${pkgs.gnome-control-center}/bin/gnome-control-center";
        categories = [ "X-Preferences" ];
        terminal = false;
      };
    };
    home.sessionVariables = {
      WLR_NO_HARDWARE_CURSORS = "1";
      XCURSOR_SIZE = "48";
      NIXOS_OZONE_WL = "1";
    };
    home.packages = [
      #
      pkgs.wlsunset
      pkgs.swaynotificationcenter
      pkgs.grimblast
      pkgs.ydotool
      pkgs.wlr-randr
      pkgs.networkmanagerapplet
      pkgs.playerctl
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
              dispatch resizewindowpixel exact 20% 50%, address:0x$\{args[0]}; \
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
      pkgs.grim
      pkgs.slurp
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
      settings = {
        monitor = [
          ",preferred,auto,1.56667"
          "DP-2,preferred,auto,1.6"
        ];
        exec-once = [
          "nmcli radio wifi off && nmcli radio wifi on" # wifi doesn't work without this.
          "bwfloat"
          "swaync"
          "nm-applet"
          "${pkgs.wlsunset}/wlsunset -l 39.103119 -L -84.512016 -t 0 -g 0.7"
          "${pkgs.plasma5Packages.kdeconnect-kde}/bin/kdeconnect-indicator"
        ];
        input = {
          kb_layout = "us";
          kb_options = "caps:swapescape";

          touchpad = {
            natural_scroll = true;
            disable_while_typing = false;
          };
        };

        general = with config.colorScheme.palette; {
          gaps_in = 8;
          gaps_out = 16;
          border_size = 2;
          "col.active_border" = "rgba(${base08}ee) rgba(${base0A}ee) 45deg";
          "col.inactive_border" = "rgba(${base03}aa)";
          layout = "master";
          allow_tearing = false;
        };

        decoration = with config.colorScheme.palette; {

          rounding = 10;

          blur = {
            enabled = true;
            size = 3;
            passes = 1;
          };

          shadow = {
            enabled = true;
            range = 4;
            render_power = 3;
            color = "rgba(${base01}ee)";
          };
        };

        animations = {
          enabled = lib.mkDefault true;
          bezier = "myBezier,0.05,0.9,0.1,1.05";

          animation = [
            "windows,1,7,myBezier"
            "windowsOut,1,7,default,popin 80%"
            "border,1,10,default"
            "borderangle,1,8,default"
            "fade,1,7,default"
            "workspaces,1,6,default"
          ];
        };

        dwindle = {
          pseudotile = true;
          preserve_split = true;
        };

        gestures = {
          workspace_swipe = true;
          workspace_swipe_forever = true;
        };

        misc = {
          force_default_wallpaper = -1;
          enable_swallow = false;
          swallow_regex = "^(Alacritty|kitty|footclient|foot)$";
        };

        windowrule =
          let
            f = regex: "float, class:^(${regex})$";
            w = s: r: "workspace ${toString s} silent, ${r}";
          in
          [
            (f "org.gnome.Calculator")
            (f "org.gnome.Nautilus")
            (f "org.pulseaudio.pavucontrol")
            (f "nm-connection-editor")
            (f "org.gnome.Settings")
            (f "org.gnome.design.Palette")
            (f "Color Picker")
            (f "xdg-desktop-portal")
            (f "xdg-desktop-portal-gnome")
            (f "com.github.Aylur.ags")
            (w 5 "title:^(Signal)$")
            (w 8 "class:^(steam)(.*)$")
            (w 8 "class:^(org.prismlauncher.PrismLauncher)$")
            "float,title:(Bitwarden)$"
          ];
        layerrule = [
          "animation slide top, ^(rofi)$"
          "animation slide top, ^(waybar)$"
        ];

        "$mainMod" = "SUPER";

        bind = [
          #
          "$mainMod,Q,exec,kitty"
          "$mainMod,C,killactive,"
          "CTRLSHIFT$mainMod,C,exit,"
          "$mainMod,E,exec,xdg-open '/'"
          "$mainMod,W,exec,xdg-open 'http://'"
          "$mainMod,A,exec,pkill aiclip; aiclip"
          "$mainMod,V,togglefloating,"
          "$mainMod,n,exec,swaync-client --close-latest"
          "$mainMod SHIFT,n,exec,swaync-client -t"
          "$mainMod,R,exec,pkill rofi || rofi -show drun"
          "$mainMod SHIFT, V, exec, mullvad reconnect"
          (lib.mkIf config.programs.rbw.enable "$mainMod,P,exec,pkill rofi || rofi-rbw -a copy")
          "$mainMod,H,movefocus,l"
          "$mainMod,L,movefocus,r"
          "$mainMod,K,movefocus,u"
          "$mainMod,J,movefocus,d"
          "$mainMod SHIFT,H,movewindoworgroup,l"
          "$mainMod SHIFT,L,movewindoworgroup,r"
          "$mainMod SHIFT,K,movewindoworgroup,u"
          "$mainMod SHIFT,J,movewindoworgroup,d"
          "$mainMod,S,togglespecialworkspace,magic"
          "$mainMod SHIFT,S,movetoworkspace,special:magic"
          "$mainMod,T,togglespecialworkspace,todo"
          "SHIFT$mainMod,t,exec,todo"
          "$mainMod,mouse_down,workspace,e+1"
          "$mainMod,mouse_up,workspace,e-1"
          "CTRLSHIFT$mainMod,S,exec,qshot"
          "$mainMod,F11,fullscreen,0"
          "$mainMod,M,fullscreen,1"
          "CTRL$mainMod,F11,fullscreenstate,2"
          "$mainMod,p,pin,"
          "$mainMod CTRL,s,exec,grimblast copy area"
          "$mainMod,b,exec,pkill waybar || waybar"
          "$mainMod,G,togglegroup"
          "$mainMod,f1,exec,hyprperf"
          "$mainMod,f2,exec,swapcaps"
          "$mainMod,1,workspace,1"
          "$mainMod,2,workspace,2"
          "$mainMod,3,workspace,3"
          "$mainMod,4,workspace,4"
          "$mainMod,5,workspace,5"
          "$mainMod,6,workspace,6"
          "$mainMod,7,workspace,7"
          "$mainMod,8,workspace,8"
          "$mainMod,9,workspace,9"
          "$mainMod,0,workspace,10"
          "$mainMod,comma,focusmonitor,+1"
          "$mainMod,period,focusmonitor,-1"
          "$mainMod SHIFT,1,movetoworkspacesilent,1"
          "$mainMod SHIFT,2,movetoworkspacesilent,2"
          "$mainMod SHIFT,3,movetoworkspacesilent,3"
          "$mainMod SHIFT,4,movetoworkspacesilent,4"
          "$mainMod SHIFT,5,movetoworkspacesilent,5"
          "$mainMod SHIFT,6,movetoworkspacesilent,6"
          "$mainMod SHIFT,7,movetoworkspacesilent,7"
          "$mainMod SHIFT,8,movetoworkspacesilent,8"
          "$mainMod SHIFT,9,movetoworkspacesilent,9"
          "$mainMod SHIFT,0,movetoworkspacesilent,10"
          "$mainMod SHIFT,comma,movewindow,mon:+1"
          "$mainMod SHIFT,period,movewindow,mon:-1"
          "$mainMod ALT,1,changegroupactive,1"
          "$mainMod ALT,2,changegroupactive,2"
          "$mainMod ALT,3,changegroupactive,3"
          "$mainMod ALT,4,changegroupactive,4"
          "$mainMod ALT,5,changegroupactive,5"
          "$mainMod ALT,6,changegroupactive,6"
          "$mainMod ALT,7,changegroupactive,7"
          "$mainMod ALT,8,changegroupactive,8"
          "$mainMod ALT,9,changegroupactive,9"
          "$mainMod ALT,0,changegroupactive,10"
          "$mainMod SHIFT,<,exec, ${playerctl} previous"
          "$mainMod SHIFT,>,exec, ${playerctl} next"
        ];
        bindle = [
          ",XF86MonBrightnessUp,   exec, ${brightnessctl} set +5%; devbright"
          ",XF86MonBrightnessDown, exec, ${brightnessctl} set  5%-; devbright"
          ",XF86AudioRaiseVolume,  exec, ${pactl} set-sink-volume @DEFAULT_SINK@ +5%"
          ",XF86AudioLowerVolume,  exec, ${pactl} set-sink-volume @DEFAULT_SINK@ -5%"
          "CTRL $mainMod,H,resizeactive,-16 0"
          "CTRL $mainMod,L,resizeactive,16 0"
          "CTRL $mainMod,K,resizeactive,0 -16"
          "CTRL $mainMod,J,resizeactive,0 16"
          "SHIFT$mainMod,J,moveactive,0 16"
          "SHIFT$mainMod,K,moveactive,0 -16"
          "SHIFT$mainMod,H,moveactive,-16 0"
          "SHIFT$mainMod,L,moveactive,16 0"
        ];
        bindl = [
          ",XF86AudioPlay,    exec, ${playerctl} play-pause"
          ",XF86AudioStop,    exec, ${playerctl} pause"
          ",XF86AudioPause,   exec, ${playerctl} pause"
          ",XF86AudioPrev,    exec, ${playerctl} previous"
          ",XF86AudioNext,    exec, ${playerctl} next"
          ",XF86AudioMicMute, exec, ${pactl} set-source-mute @DEFAULT_SOURCE@ toggle"
        ];
        # plugins = [
        #   pkgs.hyprlandPlugins.hyprexpo
        # ];

        bindm = [
          "$mainMod,mouse:272,movewindow"
          "$mainMod,mouse:273,resizewindow"
        ];

        master = {
          new_on_top = false;
        };
        debug = {
          disable_scale_checks = true;
        };
        xwayland = {
          force_zero_scaling = true;
        };
      };
    };
  };
}
