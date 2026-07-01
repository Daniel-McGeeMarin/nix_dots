{ ... }:
{
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.extraPools = [ "data" ];
  boot.zfs.requestEncryptionCredentials = true;

  fileSystems."/srv" = {
    device = "data/srv";
    fsType = "zfs";
  };

  systemd.tmpfiles.rules = [
    "d /srv/data              0755 root root"
    "d /srv/data/authelia     0750 root root"
    "d /srv/data/homarr       0750 root root"
    "d /srv/data/ghost-public 0750 root root"
    "d /srv/data/ghost-private 0750 root root"
    "d /srv/www               0755 root root"
  ];
}
