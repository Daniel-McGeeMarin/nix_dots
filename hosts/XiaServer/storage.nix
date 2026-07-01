{ pkgs, ... }:
{
  boot.kernelPackages = pkgs.linuxPackages_6_6;
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.requestEncryptionCredentials = false;
}
