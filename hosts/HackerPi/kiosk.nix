# Put the board on the TV plugged into this Pi.
#
# Hardware-only: this is imported by sd-image.nix, never by sim.nix -- the
# qemu VM has no display and no GPU, so the sim stays a pure headless server
# and only the real Pi grows a screen.
#
# The stack is deliberately the lightweight one, because this is a 1 GB Pi 3
# that is ALSO running the server the browser is pointing at:
#   cage   a minimal Wayland compositor that runs exactly one app fullscreen
#          on tty1 (NixOS ships services.cage for precisely this)
#   cog    the WPE WebKit single-page kiosk browser -- far smaller resident
#          than Chromium, which matters when the API + a browser share 1 GB
#
# If cog ever mis-renders the board (it is a modern engine, so it should be
# fine -- SSE, grid, CSS custom properties all supported), the fallback is to
# point `program` at Chromium instead; see the commented line below. Chromium
# is the engine the board is developed against, at a real memory cost here.
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

    services.cage = {
      enable = true;
      user = "kiosk";
      program = "${pkgs.cog}/bin/cog ${boardUrl}";
      # Chromium fallback (swap the line above for this if cog mis-renders):
      # program = ''${pkgs.chromium}/bin/chromium --kiosk --start-fullscreen \
      #   --autoplay-policy=no-user-gesture-required --noerrdialogs \
      #   --disable-infobars --disable-session-crashed-bubble ${boardUrl}'';
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
