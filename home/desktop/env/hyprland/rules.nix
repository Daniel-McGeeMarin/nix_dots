{ ... }:
let
  f = regex: "float, class:^(${regex})$";
  w = s: r: "workspace ${toString s} silent, ${r}";
in
{
  wayland.windowManager.hyprland.settings = {
    windowrule = [
      ### Buffer Terms (invisible, parked on workspaces 13-15) ###
      "workspace 13 silent, class:^(BufferTerm1)$"
      "workspace 14 silent, class:^(BufferTerm2)$"
      "workspace 15 silent, class:^(BufferTerm3)$"
      "nofocus, class:^(BufferTerm.*)$"
      "size 0 0, class:^(BufferTerm.*)$"
      "move 0 0, class:^(BufferTerm.*)$"
      "noinitialfocus, class:^(BufferTerm.*)$"

      ### Waydroid (magic workspace 21) ###
      "fullscreen, class:^(Waydroid)$"
      "fullscreen, class:^(waydroid\\..+)$"
      "workspace 21 silent, class:^(Waydroid)$"
      "workspace 21 silent, class:^(waydroid\\..+)$"

      ### Nixswitch terminal ###
      "float, class:^(nixswitch-term)$"
      "size 700 90, class:^(nixswitch-term)$"
      "move 1200 10, class:^(nixswitch-term)$"
      "pin, class:^(nixswitch-term)$"

      ### AppAssistDesktop job browser (external Brave window) ###
      # AppAssistDesktop launches Brave with --class=AppAssistJobBrowser and
      # drives it via CDP. Position/resize is dispatched from the app on every
      # resize/move; these rules take care of the compositor chrome so the
      # Brave window sits seamlessly over the app's center panel.
      "float, class:^(AppAssistJobBrowser)$"
      "noborder, class:^(AppAssistJobBrowser)$"
      "noshadow, class:^(AppAssistJobBrowser)$"
      "noanim, class:^(AppAssistJobBrowser)$"
      "noinitialfocus, class:^(AppAssistJobBrowser)$"
      # Setup window (spawned via the "Browser Setup" button) is a regular
      # Brave with full chrome — user installs/logs into Simplify there.
      "float, class:^(AppAssistJobBrowserSetup)$"

      ### Generic ###
      "suppressevent maximize, class:.*"
      "nofocus,class:^$,title:^$,xwayland:1,floating:1,fullscreen:0,pinned:0"

      ### Virtual Keyboard (Squeekboard) ###
      (f "sm.puri.Squeekboard")
      "pin,class:^(sm.puri.Squeekboard)$"
      "nofocus,class:^(sm.puri.Squeekboard)$"
      "size 100% 35%,class:^(sm.puri.Squeekboard)$"
      "move 0 65%,class:^(sm.puri.Squeekboard)$"
      "stayfocused,class:^(sm.puri.Squeekboard)$"

      ### Floating windows ###
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

      ### Modern match (MTG Online) ###
      "tile, title:^(?=.*Modern)(?=.*vs).*$"
      "focusonactivate 1, title:^(?=.*Modern)(?=.*vs).*$"
      "float, title:^(?=.*Modern)(?=.*vs)(?!magic: the gathering online).*$"
      "focusonactivate 1, title:^(?=.*Modern)(?=.*vs)(?!magic: the gathering online).*$"

      ### TODO scratchpad ###
      "float,title:^(TODO)$"
      "size 600 800,title:^(TODO)$"
      "pin,title:^(TODO)$"
      "center,title:^(TODO)$"
      "noanim,title:^(TODO)$"

      ### Workspace assignments ###
      (w 5 "title:^(Signal)$")
      (w 6 "class:^(steam)$")
      (w 6 "class:.*steam_app.*")
      (w 6 "class:^(org\\.prismlauncher\\.PrismLauncher)$")
      "workspace special:magic silent,class:^(Joplin)$"
      (w 2 "title:^(Steam Input On-screen Keyboard)$")
      (w 9 "class:^(chromium-browser)$")
      (w 8 "class:^(steam)(.*)$")
      "float,title:(Bitwarden)$"
      (w 2 "class:^(StartupTerm)$")
    ];

    layerrule = [
      "animation slide top, ^(rofi)$"
    ];
  };
}
