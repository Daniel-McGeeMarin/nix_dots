{ ... }:
let
  themeDir = ./grub-theme/LORTheme;

  recurse = path:
    builtins.concatLists (map (file:
      let full = "${path}/${file}";
      in if (builtins.readDir full) ? type && (builtins.readDir full).type == "directory"
         then recurse full
         else [ full ]
    ) (builtins.attrNames (builtins.readDir path)));

  allFiles = recurse themeDir;
in
{
  boot.loader.grub.extraFiles =
    builtins.listToAttrs (map (f: {
      name = "/boot/grub/themes/LORTheme" + builtins.replaceStrings [ (toString themeDir) ] [ "" ] f;
      value = f;
    }) allFiles);

  boot.loader.grub.extraConfig = ''
    set theme=/boot/grub/themes/LORTheme/theme.txt
  '';
}

