{ pkgs, ... }:
{
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.package = pkgs.zfs_unstable;
  boot.zfs.requestEncryptionCredentials = false;
}
