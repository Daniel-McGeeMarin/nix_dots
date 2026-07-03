{ config, lib, ... }:
{
  imports = [ ./network.nix ./auth.nix ./dashboard.nix ./blogs.nix ./ocis.nix ./onlyoffice.nix ];

  options.serv.enable = lib.mkEnableOption "Enable the serv module";

  config = lib.mkIf config.serv.enable {
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = lib.mkDefault false;
        UseDns = true;
        PermitRootLogin = "no";
      };
    };

    # Servers must never sleep, suspend, or hibernate regardless of head mode.
    systemd.targets.sleep.enable = false;
    systemd.targets.suspend.enable = false;
    systemd.targets.hibernate.enable = false;
    systemd.targets.hybrid-sleep.enable = false;

    services.displayManager.gdm.autoSuspend = false;

    services.logind.settings.Login = {
      HandleLidSwitch = "ignore";
      HandleLidSwitchExternalPower = "ignore";
      HandleSuspendKey = "ignore";
      HandleHibernateKey = "ignore";
      IdleAction = "ignore";
    };
  };
}
