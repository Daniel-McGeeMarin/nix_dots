# The real-hardware leaf: aarch64, bootable SD/USB image for the Pi 3B.
#
# Build (needs aarch64 emulation on the build host -- see binfmt in
# hosts/XiaNix/configuration.nix):
#   nix build .#packages.aarch64-linux.hackerpi-image
# The result is an uncompressed .img; write it with dd. It is a ~3 GB image
# that expands its root partition to fill the card on first boot (the
# sd-image module ships that hook), so a 32 GB stick ends up ~29 GB free.
{ config, lib, pkgs, inputs, ... }:

{
  imports = [ "${inputs.nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix" ];

  nixpkgs.hostPlatform = "aarch64-linux";

  sdImage = {
    imageBaseName = "hackerpi";
    # xz under qemu emulation takes longer than the build; dd cares only
    # about the raw image anyway.
    compressImage = false;
  };

  # Wi-Fi. The PSK is NOT here -- it would end up world-readable in the nix
  # store and committed to git. wpa_supplicant reads it at runtime from
  # /var/lib/wifi-secrets (shape: `psk_home=<the password>`), which the
  # provisioning step writes onto the flashed stick along with the deploy
  # key. No file, no Wi-Fi -- ethernet keeps working regardless.
  networking.wireless = {
    enable = true;
    secretsFile = "/var/lib/wifi-secrets";
    networks."xVx_RogMoggers42_xVx".pskRaw = "ext:psk_home";
  };

  # brcmfmac firmware for the Pi's Wi-Fi/BT chip.
  hardware.enableRedistributableFirmware = true;
}
