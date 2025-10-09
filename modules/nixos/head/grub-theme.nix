{ ... }:
{
  boot.loader.grub.extraFiles."/boot/grub/themes/LORTheme" = ./grub-theme/LORTheme;

  boot.loader.grub.extraConfig = ''
    set theme=/boot/grub/themes/LORTheme/theme.txt
  '';
}


