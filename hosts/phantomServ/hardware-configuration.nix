{ pkgs, lib, ... }: {
  boot.kernelPackages = pkgs.linuxPackages_latest;
  services.openssh.enable = true;
  documentation.enable = false;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  networking.useDHCP = lib.mkDefault true;
  services.qemuGuest.enable = true;
  virtualisation = {
    cores = 3;
    memorySize = 3 * 2024;
    diskSize = 16 * 1024;
    forwardPorts = [
      { from = "host"; host.port = 2222; guest.port = 22; }
      { from = "host"; host.port = 8123; guest.port = 8123; }
      { from = "host"; host.port = 8096; guest.port = 8096; }
      { from = "host"; host.port = 9696; guest.port = 9696; }
      { from = "host"; host.port = 8989; guest.port = 8989; }
      { from = "host"; host.port = 7878; guest.port = 7878; }
      { from = "host"; host.port = 8787; guest.port = 8787; }
      { from = "host"; host.port = 8112; guest.port = 8112; }
    ];
  };
}
