{ lib, config, pkgs, ... }:
{
  # LG Gram pen remapping support (Wayland / Hyprland)

  config = {
    # Install input-remapper tools (GUI + CLI)
    environment.systemPackages = [
      pkgs.input-remapper
    ];

    # Enable the system daemon so the GUI can connect
    services.input-remapper = {
      enable = true;
      enableUdevRules = true;
    };

    # Required for pkexec / policykit authentication
    security.polkit.enable = true;
  };
}

