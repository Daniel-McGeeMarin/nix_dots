# Put the board on the TV plugged into this Pi.
#
# Hardware-only: this is imported by sd-image.nix, never by sim.nix -- the
# qemu VM has no display and no GPU, so the sim stays a pure headless server
# and only the real Pi grows a screen.
#
# The stack:
#   cage      a minimal Wayland compositor that runs exactly one app
#             fullscreen on tty1 (NixOS ships services.cage for this)
#   chromium  the kiosk browser, run with the same flags the monolith board
#             launcher uses. cog (lighter WPE WebKit) was the first choice
#             for a 1 GB box, but it was removed from nixpkgs 25.11 (depended
#             on unmaintained libraries). Chromium is heavier resident, but
#             it is the engine the board is developed against and it is in
#             the aarch64 binary cache; zram absorbs the memory pressure.
#             If the Pi turns out to OOM under it, the lighter swap is a
#             webkit2gtk browser like `surf`.
#
# Not yet wired: audio. The scrum alarm makes a chime, which needs ALSA/HDMI
# audio set up on the Pi; the board is visually complete without it. Follow-up.
{ config, lib, pkgs, ... }:

let
  cfg = config.hackerpi.kiosk;
  boardUrl = "http://127.0.0.1:8420";
in
{
  options.hackerpi.kiosk.enable =
    lib.mkEnableOption "the on-device TV kiosk" // { default = true; };

  config = lib.mkIf cfg.enable {
    # The vc4 KMS driver, so the mainline kernel exposes a DRM device
    # (/dev/dri/card0) for cage to render on. Without this overlay the Pi
    # only has a firmware framebuffer, which Wayland cannot use, and the TV
    # stays black even though the box is up. gpu_mem gives the GPU enough
    # to composite at 1080p. Appended under the image's [all] section.
    sdImage.populateFirmwareCommands = lib.mkAfter ''
      {
        echo ""
        echo "# hackerpi kiosk: KMS/GL driver + GPU memory for the Wayland seat"
        echo "dtoverlay=vc4-kms-v3d"
        echo "gpu_mem=128"
      } >> firmware/config.txt
    '';

    # Mesa (v3d) for GL rendering on the vc4.
    hardware.graphics.enable = true;

    # cage auto-starts on tty1 as this user and runs the board fullscreen.
    # A normal (not system) user so logind gives it a graphical seat.
    users.users.kiosk = {
      isNormalUser = true;
      # No password and no keys: this account exists only to own the kiosk
      # session on the console. Remote entry is the xia account over ssh.
      hashedPassword = "!";
    };

    # A wrapper rather than a long inline string: cage.program is interpolated
    # into an ExecStart, and keeping the flags in one script makes them
    # legible and quotable. --ozone-platform=wayland makes chromium a native
    # Wayland client under cage; the rest mirror the board's own launcher --
    # a single app window, no first-run prompts, and autoplay allowed so the
    # scrum alarm can sound once audio is wired.
    services.cage = {
      enable = true;
      user = "kiosk";
      program = lib.getExe (pkgs.writeShellScriptBin "hackerboard-kiosk" ''
        exec ${pkgs.chromium}/bin/chromium \
          --ozone-platform=wayland \
          --kiosk --start-fullscreen \
          --autoplay-policy=no-user-gesture-required \
          --noerrdialogs --disable-infobars \
          --disable-session-crashed-bubble \
          --disable-features=TranslateUI,ChromeWhatsNewUI,MediaRouter \
          --check-for-update-interval=31536000 \
          --password-store=basic \
          ${boardUrl}
      '');
    };

    # cage's session waits for a screen and for the board's port to answer;
    # ordering it after the service means the first paint is the board, not a
    # connection-refused page it then has to be told to reload.
    systemd.services."cage-tty1" = {
      after = [ "hackerboard.service" ];
      wants = [ "hackerboard.service" ];
    };
  };
}
