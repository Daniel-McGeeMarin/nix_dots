{ pkgs, config, ... }:
{
  boot.supportedFilesystems = [ "zfs" ];
  boot.extraModulePackages = [ config.boot.kernelPackages.zfs_unstable ];
  boot.kernelModules = [ "zfs" ];
  boot.zfs.requestEncryptionCredentials = false;
}
