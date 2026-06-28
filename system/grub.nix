{ ... }:
{
  boot.loader = {
    grub = {
      enable = true;
      efiSupport = true;
      useOSProber = true;
      device = "nodev";
      configurationLimit = 10;
      default = 0;
      theme = ./grub-theme/LORTheme;
    };

    efi.canTouchEfiVariables = true;
    timeout = 5;
  };
}
