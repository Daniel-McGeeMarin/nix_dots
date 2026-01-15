{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.input-remapper
  ];

  services.input-remapper = {
    enable = true;
    enableUdevRules = true;
  };

  security.polkit.enable = true;
}

