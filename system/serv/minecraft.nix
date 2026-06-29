{ config, lib, pkgs, ... }:
{
  options.serv.minecraft.enable = lib.mkEnableOption "Enable Minecraft server";
  config = lib.mkIf config.serv.minecraft.enable {
    users.users.mcserver = {
      isNormalUser = true;
      shell = pkgs.bash;
      group = "mcserver";
      description = "Minecraft server user";
    };
    users.groups.mcserver = { };

    networking.firewall.allowedTCPPorts = [ 25565 ];
    networking.firewall.allowedUDPPorts = [ 24454 ];

    systemd.services.minecraft-server = {
      description = "Minecraft server in screen session";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      path = with pkgs; [ jdk21 udev ];
      environment = {
        JAVA_HOME = "${pkgs.jdk21.home}";
        LD_LIBRARY_PATH = lib.makeLibraryPath [ pkgs.udev ];
      };
      serviceConfig = {
        User = "mcserver";
        Group = "mcserver";
        WorkingDirectory = "/var/lib/mc/server";
        ExecStart = "${pkgs.screen}/bin/screen -DmS minecraft ${pkgs.bash}/bin/bash /var/lib/mc/server/run.sh";
        Restart = "always";
        RestartSec = 10;
      };
    };
  };
}
