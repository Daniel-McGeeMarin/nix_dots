{ pkgs, ... }:
{
  programs.waybar = {
    systemd.enable = false;
    #systemd.target = "graphical-session.target";

    settings = [
      {
        layer = "top";
        outputs = [ "eDP-1" ];
        position = "top";
        mod = "dock";
        height = 40;
        exclusive = true;
        passthrough = false;
        gtk-layer-shell = true;

        modules-left = [
          "custom/left"
          "custom/rofi"
          "backlight"
          "pulseaudio"
          "battery"
          "custom/bluetooth"
          "custom/right"
        ];

        modules-center = [
          "custom/left"
          "hyprland/workspaces"
          "custom/right"
        ];

        modules-right = [
          #"custom/left"
          #"custom/todo1"
          #"custom/right"
          #"custom/left"
          #"custom/todo2"
          #"custom/right"
          #"custom/left"
          #"custom/todo3"
          #"custom/right"
          "custom/left"
          "tray"
          "mpris"
          "clock"
          "custom/right"
        ];

        network = {
          tooltip = true;
          format-wifi = "<span foreground='#FF8B49'> {bandwidthDownBytes}</span> <span foreground='#FF6962'> {bandwidthUpBytes}</span>";
          format-ethernet = "<span foreground='#FF8B49'> {bandwidthDownBytes}</span> <span foreground='#FF6962'> {bandwidthUpBytes}</span>";
          tooltip-format = "Network: <big><b>{essid}</b></big>\nSignal strength: <b>{signaldBm}dBm ({signalStrength}%)</b>\nFrequency: <b>{frequency}MHz</b>\nInterface: <b>{ifname}</b>\nIP: <b>{ipaddr}/{cidr}</b>\nGateway: <b>{gwaddr}</b>\nNetmask: <b>{netmask}</b>";
          format-linked = "󰈀 {ifname} (No IP)";
          format-disconnected = "󰖪";
          tooltip-format-disconnected = "Disconnected";
          interval = 2;
          on-click-right = "~/.config/waybar/network.py";
        };

        temperature = {
          format = "{temperatureC}°C ";
        };

        "custom/rofi" = {
          format = "  {}";
          on-click = "rofi -show drun";
        };

        "hyprland/workspaces" = {
          format = "{icon}";
          disable-scroll = true;
          on-click = "activate";
          all-outputs = true;
          sort-by-number = true;
          format-icons = {
            "1" = "󰖟";
            "2" = "";
            "5" = "";
            "6" = "󰮂";
            "7" = "󰈮";
            "8" = "󰅨";
            "9" = "󰅱";
            "urgent-disabled" = "";
          };
        };

        battery = {
          states = {
            good = 95;
            warning = 30;
            critical = 20;
            "Fuck off Switch off" = 10;
          };
          format = "{icon} {capacity}%";
          format-charging = " {capacity}%";
          format-plugged = " {capacity}%";
          format-alt = "{time} {icon}";
          format-icons = [
            "󰂎"
            "󰁺"
            "󰁻"
            "󰁼"
            "󰁽"
            "󰁾"
            "󰁿"
            "󰂀"
            "󰂁"
            "󰂂"
            "󰁹"
          ];
        };

        pulseaudio = {
          format = "{icon} {volume}";
          format-muted = "󰖁";
          on-click = "pavucontrol -t 3";
          on-click-middle = "~/.config/hypr/scripts/volumecontrol.sh -o m";
          on-scroll-up = "~/.config/hypr/scripts/volumecontrol.sh -o i";
          on-scroll-down = "~/.config/hypr/scripts/volumecontrol.sh -o d";
          tooltip-format = "{icon} {desc} // {volume}%";
          scroll-step = 5;
          format-icons = {
            headphone = "";
            hands-free = "";
            headset = "";
            phone = "";
            portable = "";
            car = "";
            default = [
              ""
              ""
              ""
            ];
          };
        };

        tray = {
          icon-size = 20;
          spacing = 9;
        };

        clock = {
          format = " {:%H:%M}";
          on-click = "~/.config/eww/scripts/toggle_control_center.sh";
        };

        mpris = {
          format = "{player_icon} {dynamic}";
          format-paused = "{status icon} <i>{dynamic}</i>";
          player-icons = {
            "default" = "▶";
            "mpv" = "🎵";
          };
          status-icons = {
            "paused" = "⏸";
          };
          dynamic-len = 48;
          dynamic-order = [
            "artist"
            "title"
            "album"
          ];
        };

        backlight = {
          device = "intel_backlight";
          on-scroll-up = "light -A 7";
          on-scroll-down = "light -U 7";
          format = "{icon} {percent}%";
          format-icons = [
            "󰃞"
            "󰃟"
            "󰃠"
            "󱩎"
            "󱩏"
            "󱩐"
            "󱩑"
            "󱩒"
            "󱩓"
            "󰛨"
          ];
        };

        "custom/bluetooth" = {
          format = "";
          tooltip = true;
          tooltip-format = "Open Bluetooth Manager";
          on-click = "blueman-manager";
          interval = "once";
        };

        #"custom/todo1" = {
        #  format = "<span color='#ff6f61'>Sch:</span> <span color='#ddeeff'>{}</span>";
        #  interval = 30;
        #  exec = "if [ -s ~/Documents/todo/SchoolTodo.md ]; then head -n 1 ~/Documents/todo/SchoolTodo.md | cut -c1-15; else echo '-'; fi";
        #  on-click = "kitty -T TODO -e nvim ~/Documents/todo/SchoolTodo.md";
        #  signal = 8;
        #  markup = "pango";
        #};

        #"custom/todo2" = {
        #  format = "<span color='#f6c500'>Lin:</span> <span color='#ddeeff'>{}</span>";
        #  interval = 30;
        #  exec = "if [ -s ~/Documents/todo/LinuxTodo.md ]; then head -n 1 ~/Documents/todo/LinuxTodo.md | cut -c1-15; else echo '-'; fi";
        #  on-click = "kitty -T TODO -e nvim ~/Documents/todo/LinuxTodo.md";
        #  signal = 8;
        #  markup = "pango";
        #};

        #"custom/todo3" = {
        #  format = "<span color='#65d487'>Per:</span> <span color='#ddeeff'>{}</span>";
        #  interval = 30;
        #  exec = "if [ -s ~/Documents/todo/PersonalTodo.md ]; then head -n 1 ~/Documents/todo/PersonalTodo.md | cut -c1-15; else echo '-'; fi";
        #  on-click = "kitty -T TODO -e nvim ~/Documents/todo/PersonalTodo.md";
        #  signal = 8;
        #  markup = "pango";
        #};

        "custom/left" = {
          format = " ";
          interval = "once";
          tooltip = false;
        };

        "custom/right" = {
          format = " ";
          interval = "once";
          tooltip = false;
        };
      }
    ];

    style = builtins.readFile (./. + "/style.css");
  };
}

