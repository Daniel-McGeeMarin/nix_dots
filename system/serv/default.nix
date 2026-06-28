{ config, lib, pkgs, inputs, ... }:
{
  imports = [
    ./home-assistant.nix
    ./media.nix
  ];

  options.serv.enable = lib.mkEnableOption "Enable the serv module";

  config = lib.mkIf config.serv.enable {
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = true;
        UseDns = true;
        PermitRootLogin = "no";
      };
    };
  };
}
