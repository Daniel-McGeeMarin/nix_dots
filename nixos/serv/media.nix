{ config, pkgs, lib, ... }:
{
  options.serv.media.enable = lib.mkEnableOption "Enable media";
  config = lib.mkIf config.serv.media.enable
    {
      users.groups.media.members = [ "prowlarr" "radarr" "sonarr" "readarr" "deluge" "jellyfin" ];
      services.jellyfin = {
        openFirewall = true;
        enable = true;
        dataDir = "/srv/media";
      };
      systemd.tmpfiles.rules = [
        "d /srv/media 0775 jellyfin media"
        "d /srv/media/movies 0775 jellyfin media"
        "d /srv/media/tv 0775 jellyfin media"
        "d /srv/media/anime 0775 jellyfin media"
        "d /srv/media/music 0775 jellyfin media"
        "d /srv/media/books 0775 jellyfin media"
        "d /srv/media/downloads 0775 jellyfin media"
      ];
      services.prowlarr = {
        enable = true;
        openFirewall = true;
      };
      services.radarr = {
        enable = true;
        openFirewall = true;
      };
      services.sonarr = {
        enable = true;
        openFirewall = true;
      };
      services.readarr = {
        enable = true;
        openFirewall = true;
      };
      services.deluge = {
        enable = true;
        web = {
          enable = true;
          openFirewall = true;
        };
      };
      services.flaresolverr.enable = true;
    };
}
