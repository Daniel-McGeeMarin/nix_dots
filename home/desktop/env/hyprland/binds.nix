{ pkgs, lib, config, secrets, ... }:
let
  playerctl = "${pkgs.playerctl}/bin/playerctl";
  brightnessctl = "${pkgs.brightnessctl}/bin/brightnessctl";
  pactl = "${pkgs.pulseaudio}/bin/pactl";
  hyprWorkspaceCycle = pkgs.writeShellScriptBin "hypr-workspace-cycle" (builtins.readFile ./hypr-workspace-cycle.sh);
  hyprWorkspaceNext = pkgs.writeShellScriptBin "hypr-workspace-next" ''exec "${hyprWorkspaceCycle}/bin/hypr-workspace-cycle" next'';
  hyprWorkspacePrev = pkgs.writeShellScriptBin "hypr-workspace-prev" ''exec "${hyprWorkspaceCycle}/bin/hypr-workspace-cycle" prev'';
in
{
  wayland.windowManager.hyprland = {
    settings = {
      "$mainMod" = "SUPER";

      gesture = [
        "3, left, dispatcher, exec, ${hyprWorkspaceNext}/bin/hypr-workspace-next"
        "3, right, dispatcher, exec, ${hyprWorkspacePrev}/bin/hypr-workspace-prev"
      ];

      bind = [
        "CTRL $mainMod,U,workspace,11"
        "$mainMod SHIFT,U,movetoworkspace,11"
        "SUPER_SHIFT,C,exec,bash -c 'kill -9 $(hyprctl activewindow -j | jq .pid)'"

        # Bluetooth headset toggle
        ''
        $mainMod,M,exec,bash -c '[ "$(bluetoothctl info ${secrets.hypr.bluetoothHeadsetMac} | grep Connected | awk "{print \$2}")" = "yes" ] && bluetoothctl disconnect ${secrets.hypr.bluetoothHeadsetMac} || bluetoothctl connect ${secrets.hypr.bluetoothHeadsetMac}'
        ''

        # Recruiting helpers
        ''$mainMod,U,exec,bash -c "hyprctl dispatch workspace 11 && librewolf --new-window 'https://github.com/vanshb03/Summer2026-Internships?tab=readme-ov-file'"''

        "$mainMod,I,exec,bash ~/MyApps/resume-pipeline/stage1.sh"
        "$mainMod,O,exec,bash ~/MyApps/resume-pipeline/stage2.sh"

        # Quick paste helpers (work credentials)
        ''SUPER,bracketleft,exec,bash -c 'printf "${secrets.hypr.workEmail}" | wl-copy --trim-newline && hyprctl dispatch sendshortcut "CTRL,V,"' ''
        ''SUPER,bracketright,exec,bash -c 'printf "${secrets.hypr.workPassword}" | wl-copy --trim-newline && hyprctl dispatch sendshortcut "CTRL,V,"' ''
        ''SUPER,n,exec,bash -c 'printf "${secrets.hypr.workLinkedinUrl}" | wl-copy --trim-newline && hyprctl dispatch sendshortcut "CTRL,V,"' ''

        "$mainMod,Q,exec,kitty"
        "$mainMod,C,killactive,"
        "CTRL$mainMod,M,exit,"
        "$mainMod,E,exec,xdg-open '/'"
        "$mainMod,W,exec,zen"
        "$mainMod,A,exec,pkill aiclip; aiclip"
        "$mainMod,V,togglefloating,"
        "$mainMod,n,exec,swaync-client --close-latest"
        "$mainMod SHIFT,n,exec,swaync-client -t"
        "$mainMod SHIFT,R,exec,pkill rofi || rofi -show drun"

        # Caelestia global binds
        "$mainMod,R,global,caelestia:launcher"
        "$mainMod,A,global,caelestia:control-center"

        "$mainMod SHIFT, V, exec, mullvad reconnect"
        (lib.mkIf config.programs.rbw.enable "$mainMod,P,exec,pkill rofi || rofi-rbw -a copy")

        # Focus
        "$mainMod,H,movefocus,l"
        "$mainMod,L,movefocus,r"
        "$mainMod,K,movefocus,u"
        "$mainMod,J,movefocus,d"

        # Move window
        "$mainMod SHIFT,H,movewindoworgroup,l"
        "$mainMod SHIFT,L,movewindoworgroup,r"
        "$mainMod SHIFT,K,movewindoworgroup,u"
        "$mainMod SHIFT,J,movewindoworgroup,d"

        # Special workspaces
        "$mainMod,S,togglespecialworkspace,magic"
        "$mainMod SHIFT,S,movetoworkspace,special:magic"
        "$mainMod,T,togglespecialworkspace,todo"
        "SHIFT$mainMod,t,exec,todo"

        # Workspace cycle (1-12 normal; 21 waydroid; 22 xournal++)
        "$mainMod,X,exec,${hyprWorkspaceCycle}/bin/hypr-workspace-cycle toggle"
        "$mainMod SHIFT,X,workspace, 22"
        "$mainMod,mouse_down,exec,${hyprWorkspaceNext}/bin/hypr-workspace-next"
        "$mainMod,mouse_up,exec,${hyprWorkspacePrev}/bin/hypr-workspace-prev"

        "$mainMod,Z,exec,qshot"
        "$mainMod,F,fullscreen,0"
        "CTRL$mainMod,F,fullscreen,1"
        "CTRL$mainMod,F11,fullscreenstate,2"
        "$mainMod,p,pin,"
        "$mainMod SHIFT ,Z,exec,grimblast copy area"
        "$mainMod,G,togglegroup"
        "$mainMod,f1,exec,hyprperf"
        "$mainMod,f2,exec,swapcaps"

        # Workspace numbers
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

        # Move workspace to monitor
        "$mainMod SHIFT, comma,  movecurrentworkspacetomonitor, DP-5"
        "$mainMod SHIFT, comma,  movecurrentworkspacetomonitor, DP-6"
        "$mainMod SHIFT, comma,  movecurrentworkspacetomonitor, DP-7"
        "$mainMod SHIFT, comma,  movecurrentworkspacetomonitor, DP-4"
        "$mainMod SHIFT, comma,  movecurrentworkspacetomonitor, DP-1"
        "$mainMod SHIFT, comma,  movecurrentworkspacetomonitor, DP-2"
        "$mainMod SHIFT, comma,  movecurrentworkspacetomonitor, DP-3"
        "$mainMod SHIFT, period, movecurrentworkspacetomonitor, eDP-1"

        # Dylan's Law
        "$mainMod CTRL SHIFT, P, exec, brave --incognito https://pornhub.com"
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
    };

    extraConfig = ''
      # Corner gesture: toggle rotation
      $rotate = ${hyprWorkspaceCycle}/bin/hypr-workspace-cycle toggle-rotation

      plugin {
        touch_gestures {
          sensitivity = 20.0
          long_press_delay = 400

          hyprgrass-bind = , edge:ru:ld, exec, $rotate
          hyprgrass-bind = , edge:rd:lu, exec, $rotate

          # Swipe: isolated cycle (1-12 only; no cross into magic workspaces)
          hyprgrass-bind = , edge:r:l, exec, ${hyprWorkspaceNext}/bin/hypr-workspace-next
          hyprgrass-bind = , edge:l:r, exec, ${hyprWorkspacePrev}/bin/hypr-workspace-prev

          hyprgrass-bind = , edge:r:lu, exec, ${hyprWorkspaceNext}/bin/hypr-workspace-next
          hyprgrass-bind = , edge:l:ru, exec, ${hyprWorkspacePrev}/bin/hypr-workspace-prev

          hyprgrass-bind = , edge:r:ld, exec, ${hyprWorkspaceNext}/bin/hypr-workspace-next
          hyprgrass-bind = , edge:l:rd, exec, ${hyprWorkspacePrev}/bin/hypr-workspace-prev

          hyprgrass-bindm = , longpress:2, movewindow
          hyprgrass-bindm = , longpress:3, resizewindow
          hyprgrass-bind = , tap:3, exec, ${hyprWorkspaceCycle}/bin/hypr-workspace-cycle toggle

          # 4-finger tap toggles squeekboard
          hyprgrass-bind = , tap:4, exec, sh -c 'pgrep squeekboard >/dev/null || squeekboard & sleep 0.2; busctl --user get-property sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 Visible 2>/dev/null | grep -q true && busctl --user call sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 SetVisible b false || busctl --user call sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 SetVisible b true'
        }
      }
    '';
  };
}
