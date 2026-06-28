{ config, pkgs, lib, ... }:
{
  services.home-assistant = {
    extraComponents = [
      # Components required to complete the onboarding
      "esphome"
      "met"
      "radio_browser"
    ];
    config = {
      # Includes dependencies for a basic setup
      # https://www.home-assistant.io/integrations/default_config/
      default_config = { };
    };
  };
  networking.firewall.allowedTCPPorts = lib.mkIf config.services.home-assistant.enable [ 8123 ];
}
