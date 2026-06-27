{pkgs, lib, config, inputs, ...}:
{
  specialisation = {
    onTheGo.configuration = {
      system.nixos.tags = [ "onTheGo" ];
      virtualisation = {
        docker.enable = false;
        waydroid.enable = false;
      };
      home-manager = { 
        users."greencheetah" = import ../home-manager/onTheGo.nix;
      };
      boot = {
        extraModprobeConfig = ''
          blacklist nouveau
          options nouveau modeset=0
          btusb
          options iwlwifi power_save=1
          options iwlwifi uapsd_disable=0
          options iwlmvm power_scheme=3
          '';
        blacklistedKernelModules = [ "nouveau" "nvidia" "nvidia_drm" "nvidia_modeset" "btusb" "bluetooth" "uvcvideo" ];
        kernelParams = [
          "pcie_aspm.policy=powersupersave"
        ];
      };

      services = {
        udev.extraRules = ''
# Remove NVIDIA USB xHCI Host Controller devices, if present
          ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x0c0330", ATTR{power/control}="auto", ATTR{remove}="1"
# Remove NVIDIA USB Type-C UCSI devices, if present
          ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x0c8000", ATTR{power/control}="auto", ATTR{remove}="1"
# Remove NVIDIA Audio devices, if present
          ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x040300", ATTR{power/control}="auto", ATTR{remove}="1"
# Remove NVIDIA VGA/3D controller devices
          ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x03[0-9]*", ATTR{power/control}="auto", ATTR{remove}="1"
          '';
        power-profiles-daemon.enable = false;
        tlp = {
          enable = true;
          settings = {
            CPU_SCALING_GOVERNOR_ON_AC = "performance";
            CPU_SCALING_GOVERNOR_ON_BAT = "powersupersave";

            CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
            CPU_ENERGY_PERF_POLICY_ON_AC = "performance";

            CPU_MIN_PERF_ON_AC = 0;
            CPU_MAX_PERF_ON_AC = 100;
            CPU_MIN_PERF_ON_BAT = 0;
            CPU_MAX_PERF_ON_BAT = 20;
          };
        };
      };
      powerManagement.powertop.enable = true;
    };
  };
}
