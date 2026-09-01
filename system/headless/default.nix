{ lib, ... }:
# A machine with no screen that has to stay reachable and stay awake.
#
# The counterpart to system/head. Importing this module is the switch, same rule
# as everywhere else in this repo: a host either is a headless always-on box or
# it is not.
#
# This exists as its own module because all of it used to live inside
# `serv.enable`, next to the blogs and the dashboard. That made "turn off my
# personal web services" and "turn off SSH" the same flag, which on a box with
# no console is a lockout that needs a physical visit to undo. None of what
# follows is a service you host; it is what keeps the machine administrable.
{
  # sshd is the only way in. mkDefault on the settings so a host can tighten
  # them (XiaServer pins PasswordAuthentication itself) without redefining the
  # service.
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = lib.mkDefault false;
      UseDns = true;
      PermitRootLogin = "no";
    };
  };

  # Tailscale is the administrative path, so it is the one interface the
  # firewall trusts wholesale.
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  # A server must never sleep, suspend or hibernate. Disabling the targets is
  # stronger than asking logind not to trigger them: nothing can reach them,
  # including a stray `systemctl suspend`.
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;

  # And the input-driven paths into those targets, for the case where the box
  # does have a lid or a power button attached.
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleSuspendKey = "ignore";
    HandleHibernateKey = "ignore";
    IdleAction = "ignore";
  };
}
