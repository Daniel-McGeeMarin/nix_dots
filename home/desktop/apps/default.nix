{ config, lib, pkgs, inputs, osConfig, ... }:
{
  imports = [
    ./firefox.nix
    ./foot.nix
    ./kitty.nix
    ./mpv.nix
    ./ncmpcpp.nix
    ./orca.nix
    ./paseo.nix
    ./signal-desktop.nix
    ./wispr-flow.nix
    ./wlctl.nix
    ./zathura.nix
  ];

  config = {

    programs = {
      foot.enable = lib.mkDefault true;
      kitty.enable = lib.mkDefault true;
      zathura.enable = lib.mkDefault true;
      mpv.enable = lib.mkDefault true;
    };

    xdg.mimeApps.defaultApplications = {
      "text/html" = "firefox.desktop";
      "x-scheme-handler/http" = "firefox.desktop";
      "x-scheme-handler/https" = "firefox.desktop";
      # grail:// links (the company sidebar's customers, mail and chats) open
      # the place in grail. grail.desktop is hand-made in
      # ~/.local/share/applications: it runs grail through gred-rs/mail/run,
      # which loads the libraries its window needs.
      "x-scheme-handler/grail" = "grail.desktop";
    };
  };
}
