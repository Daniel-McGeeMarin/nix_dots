# The simulation leaf: the same system as x86_64 inside qemu, sized like the
# Pi (1 GB RAM), so the whole stack -- sshd, firewall, the board service, the
# updater -- can be exercised on the laptop before an image ever touches
# hardware.
#
#   nix build .#hackerpi-vm && ./result/bin/run-hackerpi-vm
#
#   ssh -p 2222 xia@localhost         # same keys as the real box
#   curl http://localhost:8420/health # the board
#
# The VM keeps its disk state in ./hackerpi.qcow2 next to where it is run;
# delete that file for a factory-fresh boot.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ (modulesPath + "/virtualisation/qemu-vm.nix") ];

  nixpkgs.hostPlatform = "x86_64-linux";

  virtualisation = {
    memorySize = 1024; # the Pi 3B's 1 GB, so memory pressure is honest
    cores = 4;
    graphics = false;
    diskSize = 8192;
    forwardPorts = [
      { from = "host"; host.port = 2222; guest.port = 22; }
      { from = "host"; host.port = 8420; guest.port = 8420; }
    ];
  };
}
