{ ... }:
{
  boot.loader = {
    grub = {
      enable = true;
      efiSupport = true;
      useOSProber = true;

      # UEFI systems must use nodev, not a block device
      device = "nodev";

      timeout = 5;                 # seconds before default entry boots
      configurationLimit = 10;     # number of generations kept in the menu
      default = 0;                 # boot the first entry by default
    };

    efi.canTouchEfiVariables = true;
  };
}

