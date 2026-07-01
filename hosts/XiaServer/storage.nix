{ pkgs, ... }:
{
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.package = pkgs.zfsUnstable;
  boot.zfs.requestEncryptionCredentials = false;
}
