{ config, pkgs, lib, ... }:
{
  boot = lib.mkIf config.boot.plymouth.enable {
    initrd.systemd.enable = true;
  };
}
