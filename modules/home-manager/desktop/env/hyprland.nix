{ pkgs, lib, inputs, config, osConfig, secrets, ... }:

let
  playerctl = "${pkgs.playerctl}/bin/playerctl";
  brightnessctl = "${pkgs.brightnessctl}/bin/brightnessctl";
  pactl = "${pkgs.pulseaudio}/bin/pactl";
  socat = "${pkgs.socat}/bin/socat";
  hyprctl = "${pkgs.hyprland}/bin/hyprctl";
  jq = "${pkgs.jq}/bin/jq";
  # Modular isolated workspace cycle — see wm/hypr-workspace-cycle.sh
  hyprWorkspaceCycle = pkgs.writeShellScriptBin "hypr-workspace-cycle" (builtins.readFile ./wm/hypr-workspace-cycle.sh);
  hyprWorkspaceNext = pkgs.writeShellScriptBin "hypr-workspace-next" ''exec "${hyprWorkspaceCycle}/bin/hypr-workspace-cycle" next'';
  hyprWorkspacePrev = pkgs.writeShellScriptBin "hypr-workspace-prev" ''exec "${hyprWorkspaceCycle}/bin/hypr-workspace-cycle" prev'';
in
{
  imports = [
    wm/rofi
    wm/hyprpaper.nix
    wm/waybar
    wm/hypridle.nix
  ];


  #config = lib.mkIf osConfig.programs.hyprland.enable {
  config = {
  programs.rofi.enable = true;
    
    # not needed with caelestia
    services.hyprpaper.enable = false;
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
     
      #HYPRCURSOR_SIZE = "48"; # 3 things here to fix a mouse issue back at home
      # GBM_BACKEND = "nvidia-drm";
      #__GLX_VENDOR_LIBRARY_NAME = "nvidia";
      


      NIXOS_OZONE_WL = "1";
    };
    home.packages = [
      hyprWorkspaceNext
      hyprWorkspacePrev
      #
      #pkgs.nwg-launchers
      #pkgs.nwg-look
      inputs.nixpkgs-unstable.legacyPackages.${pkgs.system}.nwg-drawer
      pkgs.papirus-icon-theme


      pkgs.wtype
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
      plugins = [
        pkgs.hyprlandPlugins.hyprgrass
        #inputs.nixpkgs-unstable.legacyPackages.${pkgs.system}.hyprlandPlugins.hyprspace
        pkgs.hyprlandPlugins.hyprspace
        #hycov.packages.${pkgs.system}.hycov

      ];
      settings = {
        monitor = [
          # these 2 are my normal confi at uni 
          "eDP-1,preferred,auto,1.5"
          #"DP-2,preferred,auto,1,mirror,eDP-1"
          #config at home by plugging pc to dongle to hdmi
          
          #"eDP-1,disable"
          "DP-5,preferred,auto,1.5"





        ];
        exec-once = [



          "systemctl --user restart xdg-desktop-portal.service"

          

          #"waybar"
          "nmcli radio wifi off && nmcli radio wifi on" # wifi doesn't work without this.
          "bwfloat"
          #"swaync"
          "nm-applet"

          #"fcitx5 -d --replace"

          #"wvkbd-mobintl --hidden"
          "squeekboard"  
          "signal-desktop"
          "nwg-drawer -r -wm hyprland -ovl -c 4 -is 60 -spacing 40 -nocats"


          "kitty --class StartupTerm"

          
          
          ''bash -c '[ "$(cat /sys/class/power_supply/AC0/online 2>/dev/null)" = "1" ] && filen-desktop' ''

          "${pkgs.wlsunset}/wlsunset -l 39.103119 -L -84.512016 -t 0 -g 0.7"
          "${pkgs.plasma5Packages.kdeconnect-kde}/bin/kdeconnect-indicator"

          
          "sleep 4 && brave"

          # Magic workspace: waydroid + xournal++ (toggle with mainmod+X or 4-finger hold)
          "sleep 5 && waydroid show-full-ui"
          "sleep 6 && flatpak run com.github.xournalpp.xournalpp"
        ];
        input = {
          kb_layout = "us";
          kb_options = "caps:swapescape";


          follow_mouse = 1;
          accel_profile = "flat";
          force_no_accel = 1;
          sensitivity = 0.8;
          scroll_factor = 0.6;

          touchpad = {
            natural_scroll = true;
            disable_while_typing = false;
            drag_lock = 2;
            scroll_factor = 0.5;
          };
        };

        #if cursor is being wierd
        cursor = {
          no_hardware_cursors = 1; # don’t use HW cursors
        };

        general = with config.colorScheme.palette; {
          gaps_in = 6; # 8
          gaps_out = 10; # 16
          border_size = 2;
          
          "col.active_border" = "rgba(e6e6e6cc) rgba(d0d0d0aa) 45deg";

          #"col.active_border" = "rgba(${base08}ee) rgba(${base0A}ee) 45deg";
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


          ### WAYDROID (magic workspace 21) ###
          "fullscreen, class:^(Waydroid)$"
          "fullscreen, class:^(waydroid\\..+)$"
          "workspace 21 silent, class:^(Waydroid)$"
          "workspace 21 silent, class:^(waydroid\\..+)$"


          ### Generic rules ###
          "suppressevent maximize, class:.*"
          "nofocus,class:^$,title:^$,xwayland:1,floating:1,fullscreen:0,pinned:0"

          ### Virtual Keyboard (Squeekboard) ###
          (f "sm.puri.Squeekboard")
          "pin,class:^(sm.puri.Squeekboard)$"
          "nofocus,class:^(sm.puri.Squeekboard)$"
          "size 100% 35%,class:^(sm.puri.Squeekboard)$"
          "move 0 65%,class:^(sm.puri.Squeekboard)$"
          "stayfocused,class:^(sm.puri.Squeekboard)$"

          ### Dan Window Rules ###
          (f "org.gnome.Calculator")
          (f "org.gnome.Nautilus")
          (f "org.pulseaudio.pavucontrol")
          "pin,class:^(org\\.pulseaudio\\.pavucontrol)$"
          "noanim,class:^(pavucontrol)$"
          (f "nm-connection-editor")
          (f "org.gnome.Settings")
          (f "org.gnome.design.Palette")
          (f "Color Picker")
          (f "xdg-desktop-portal")
          (f "xdg-desktop-portal-gnome")
          (f "com.github.Aylur.ags")
          "float,title:^(Bitwarden)$"
          (f "blueman-manager")
          "pin,class:^(blueman-manager)$"
          "noanim,class:^(blueman-manager)$"
          "size 100 300,class:^(blueman-manager)$"


          ### modern match main window ###
          "tile, title:^(?=.*Modern)(?=.*vs).*$"
          "focusonactivate 1, title:^(?=.*Modern)(?=.*vs).*$"

          ### related popups ###
          "float, title:^(?=.*Modern)(?=.*vs)(?!magic: the gathering online).*$"
          "focusonactivate 1, title:^(?=.*Modern)(?=.*vs)(?!magic: the gathering online).*$"


          # TODO window scratchpad
          "float,title:^(TODO)$"
          "size 600 800,title:^(TODO)$"
          "pin,title:^(TODO)$"
          "center,title:^(TODO)$"
          "noanim,title:^(TODO)$"

          ### Magic workspace 22 (xournal++) ###
          "workspace 22 silent, class:^(com\\.github\\.xournalpp\\.xournalpp)$"
          "workspace 22 silent, class:^(Xournalpp)$"
          "workspace 22 silent, class:^(xournalpp)$"

          ### Workspace assignments ###
          (w 5 "title:^(Signal)$")
          (w 6 "class:^(steam)$")
          (w 6 "class:.*steam_app.*")
          (w 6 "class:^(org\\.prismlauncher\\.PrismLauncher)$")
          "workspace special:magic silent,class:^(Joplin)$"
          (w 2 "title:^(Steam Input On-screen Keyboard)$")
          (w 9 "class:^(chromium-browser)$")

          ### Resume-pipeline floating chat ###
            #"float,class:^(brave-chat\\.openai\\.com__chat-Default)$"
            #"size 1000 700,class:^(brave-chat\\.openai\\.com__chat-Default)$"
            #"center,class:^(brave-chat\\.openai\\.com__chat-Default)$"




          ### Original rules ###
          (w 8 "class:^(steam)(.*)$")
          "float,title:(Bitwarden)$"
          (w 2 "class:^(StartupTerm)$")
        ];
        layerrule = [
          "animation slide top, ^(rofi)$"
          "animation slide top, ^(waybar)$"
        ];

        "$mainMod" = "SUPER";

        bind = [

          "$mainMod,D,exec,nwg-drawer -open"


          "$mainMod, TAB, overview:toggle, "
          
          "CTRL $mainMod,U,workspace,11"
          "CTRL $mainMod,U,workspace,11"
          "$mainMod SHIFT,U,movetoworkspace,11"
          "SUPER_SHIFT,C,exec,bash -c 'kill -9 $(hyprctl activewindow -j | jq .pid)'"
          
          ''
          $mainMod,M,exec,bash -c '[ "$(bluetoothctl info ${secrets.hypr.bluetoothHeadsetMac} | grep Connected | awk "{print \$2}")" = "yes" ] && bluetoothctl disconnect ${secrets.hypr.bluetoothHeadsetMac} || bluetoothctl connect ${secrets.hypr.bluetoothHeadsetMac}'
          ''

          # recruiting helpers
          ''$mainMod,U,exec,bash -c "hyprctl dispatch workspace 11 && librewolf --new-window 'https://github.com/vanshb03/Summer2026-Internships?tab=readme-ov-file'"''



          "$mainMod,I,exec,bash ~/MyApps/resume-pipeline/stage1.sh"
          "$mainMod,O,exec,bash ~/MyApps/resume-pipeline/stage2.sh"

          # quick paste helpers
          ''
          SUPER,bracketleft,exec,bash -c 'printf "${secrets.hypr.workEmail}" | wl-copy --trim-newline && hyprctl dispatch sendshortcut "CTRL,V,"'
          ''
          ''
          SUPER,bracketright,exec,bash -c 'printf "${secrets.hypr.workPassword}" | wl-copy --trim-newline && hyprctl dispatch sendshortcut "CTRL,V,"'
          ''
          
          ''
          SUPER,n,exec,bash -c 'printf "${secrets.hypr.workLinkedinUrl}" | wl-copy --trim-newline && hyprctl dispatch sendshortcut "CTRL,V,"'
          ''




          #"ALT,C,exec,bash -c 'if hyprctl activewindow -j | grep -q LibreWolf; then ydotool key 29:1 17:1 17:0 29:0; fi'" # Alt+C → Ctrl+W
          #"ALT,Q,exec,bash -c 'if hyprctl activewindow -j | grep -q LibreWolf; then ydotool key 29:1 20:1 20:0 29:0; fi'" # Alt+Q → Ctrl+T
          #"CTRL SHIFT,C,exec,bash -c 'if hyprctl activewindow -j | grep -q LibreWolf; then ydotool key 29:1 46:1 46:0 29:0; fi'"

          #joke module for Dylan I pray an employer never sees this ;-;
          "$mainMod CTRL SHIFT, P, exec, brave --incognito https://pornhub.com"

          "$mainMod,Q,exec,kitty"
          "$mainMod,C,killactive,"
          "CTRL$mainMod,M,exit,"
          "$mainMod,E,exec,xdg-open '/'"
          "$mainMod,W,exec,brave"

          #"$mainMod,W,exec,xdg-open 'http://'"
          "$mainMod,A,exec,pkill aiclip; aiclip"
          "$mainMod,V,togglefloating,"
          "$mainMod,n,exec,swaync-client --close-latest"
          "$mainMod SHIFT,n,exec,swaync-client -t"
          "$mainMod SHIFT,R,exec,pkill rofi || rofi -show drun"

          "$mainMod,R,global,caelestia:launcher"
          "$mainMod,A,global,caelestia:control-center"
          #"$mainMod,N,global,caelestia:dashboard"



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
          # Magic workspaces 21 (waydroid) + 22 (xournal++) — only via Super+X or 4-finger hold
          "$mainMod,X,exec,${hyprWorkspaceCycle}/bin/hypr-workspace-cycle toggle"
          "$mainMod,T,togglespecialworkspace,todo"
          "SHIFT$mainMod,t,exec,todo"
          "$mainMod,mouse_down,exec,${hyprWorkspaceNext}/bin/hypr-workspace-next"
          "$mainMod,mouse_up,exec,${hyprWorkspacePrev}/bin/hypr-workspace-prev"
          "$mainMod,Z,exec,qshot"
          "$mainMod,F,fullscreen,0"
          "CTRL$mainMod,F,fullscreen,1"
          "CTRL$mainMod,F11,fullscreenstate,2"
          "$mainMod,p,pin,"
          "$mainMod SHIFT ,Z,exec,grimblast copy area"
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
          #"$mainMod,comma,focusmonitor,+1"
          #"$mainMod,period,focusmonitor,-1"
          "$mainMod SHIFT,1,movetoworkspace,1"
          "$mainMod SHIFT,2,movetoworkspace,2"
          "$mainMod SHIFT,3,movetoworkspace,3"
          "$mainMod SHIFT,4,movetoworkspace,4"
          "$mainMod SHIFT,5,movetoworkspace,5"
          "$mainMod SHIFT,6,movetoworkspace,6"
          "$mainMod SHIFT,7,movetoworkspace,7"
          "$mainMod SHIFT,8,movetoworkspace,8"
          "$mainMod SHIFT,9,movetoworkspace,9"
          "$mainMod SHIFT,0,movetoworkspace,10"
          
          
          "$mainMod SHIFT, comma,  movecurrentworkspacetomonitor, DP-5"
          "$mainMod SHIFT, comma,  movecurrentworkspacetomonitor, DP-6"
          "$mainMod SHIFT, comma,  movecurrentworkspacetomonitor, DP-7"
          "$mainMod SHIFT, comma,  movecurrentworkspacetomonitor, DP-4"



          "$mainMod SHIFT, period, movecurrentworkspacetomonitor, eDP-1"



          #"$mainMod SHIFT,comma,movewindow,mon:+1"
          #"$mainMod SHIFT,period,movewindow,mon:-1"
          #"$mainMod ALT,1,changegroupactive,1"
          #"$mainMod ALT,2,changegroupactive,2"
          #"$mainMod ALT,3,changegroupactive,3"
          #"$mainMod ALT,4,changegroupactive,4"
          #"$mainMod ALT,5,changegroupactive,5"
          #"$mainMod ALT,6,changegroupactive,6"
          #"$mainMod ALT,7,changegroupactive,7"
          #"$mainMod ALT,8,changegroupactive,8"
          #"$mainMod ALT,9,changegroupactive,9"
          #"$mainMod ALT,0,changegroupactive,10"
          #"$mainMod SHIFT,<,exec, ${playerctl} previous"
          #"$mainMod SHIFT,>,exec, ${playerctl} next"


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
      extraConfig = ''

      # Define the monitor name
      $screen = eDP-1

      # Normal (your current) spacing
      $gaps_in_normal = 6
      $gaps_out_normal = 10
      $border_normal = 2

      # Vertical "almost no space"
      $gaps_in_vertical = 1
      $gaps_out_vertical = 1
      $border_vertical = 1

      # Waydroid target sizes for your panel (2880x1800)
      $waydroid_landscape = 2880x1800
      $waydroid_portrait  = 1800x2880

      # Toggle rotate + gaps/border + Waydroid relayout
      $rotate = hyprctl monitors -j | ${pkgs.jq}/bin/jq -e ".[] | select(.name == \"$screen\" and .transform == 0)" > /dev/null && \
        ( \
          hyprctl keyword monitor "$screen,preferred,auto,2,transform,1" && \
          hyprctl keyword input:touchdevice:transform 1 && \
          hyprctl keyword input:tablet:transform 1 && \
          hyprctl keyword general:gaps_in "$gaps_in_vertical" && \
          hyprctl keyword general:gaps_out "$gaps_out_vertical" && \
          hyprctl keyword general:border_size "$border_vertical" && \
          sudo -n /run/current-system/sw/bin/waydroid shell wm size "$waydroid_portrait" && \
          sudo -n /run/current-system/sw/bin/waydroid shell wm density reset \
        ) || \
        ( \
          hyprctl keyword monitor "$screen,preferred,auto,1.5,transform,0" && \
          hyprctl keyword input:touchdevice:transform 0 && \
          hyprctl keyword input:tablet:transform 0 && \
          hyprctl keyword general:gaps_in "$gaps_in_normal" && \
          hyprctl keyword general:gaps_out "$gaps_out_normal" && \
          hyprctl keyword general:border_size "$border_normal" && \
          sudo -n /run/current-system/sw/bin/waydroid shell wm size "$waydroid_landscape" && \
          sudo -n /run/current-system/sw/bin/waydroid shell wm density reset \
        )


      plugin {
            touch_gestures {
              sensitivity = 20.0
              long_press_delay = 400

              hyprgrass-bind = , edge:ru:ld, exec, $rotate
              hyprgrass-bind = , edge:rd:lu, exec, $rotate

              # swipe: isolated cycle (1–12 only, 13↔14 only; no cross)
              hyprgrass-bind = , edge:r:l, exec, ${hyprWorkspaceNext}/bin/hypr-workspace-next
              hyprgrass-bind = , edge:l:r, exec, ${hyprWorkspacePrev}/bin/hypr-workspace-prev

              hyprgrass-bind = , edge:r:lu, exec, ${hyprWorkspaceNext}/bin/hypr-workspace-next
              hyprgrass-bind = , edge:l:ru, exec, ${hyprWorkspacePrev}/bin/hypr-workspace-prev

              hyprgrass-bind = , edge:r:ld, exec, ${hyprWorkspaceNext}/bin/hypr-workspace-next
              hyprgrass-bind = , edge:l:rd, exec, ${hyprWorkspacePrev}/bin/hypr-workspace-prev

              #hyprgrass-bind = , edge:u:d, overview:toggle
              #hyprgrass-bind = , edge:d:u, exec, nwg-drawer -open

              hyprgrass-bindm = , longpress:2, movewindow
              hyprgrass-bindm = , longpress:3, resizewindow
              hyprgrass-bind = , longpress:4, exec, ${hyprWorkspaceCycle}/bin/hypr-workspace-cycle toggle

              # tap with 3 fingers toggles squeekboard
              hyprgrass-bind = , tap:3, exec, sh -c 'pgrep squeekboard >/dev/null || squeekboard & sleep 0.2; busctl --user get-property sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 Visible 2>/dev/null | grep -q true && busctl --user call sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 SetVisible b false || busctl --user call sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 SetVisible b true'
            }
          } 
      '';

    };
  };
}
