{ lib, pkgs, config, ... }:
{
  environment.systemPackages = [
  pkgs.unfree.cudatoolkit
  pkgs.unfree.cudaPackages.cuda_cudart
  ];
  nixpkgs.config.cudaSupport = true;

  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
  };
  services.xserver.videoDrivers = ["nvidia"];

  hardware.nvidia = {

    modesetting.enable = true;

    prime = {
      # sync.enable = true;
      amdgpuBusId = "PCI:100:0:0";
      nvidiaBusId = "PCI:01:0:0";
      offload = {
        enable = false;
        enableOffloadCmd = false;
      };
    };
    powerManagement.enable = false;
    powerManagement.finegrained = false;

    open = false;

    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.beta;
  };
}
