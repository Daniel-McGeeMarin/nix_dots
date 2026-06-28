{ config, lib, pkgs, osConfig, ... }:
{
  options.desktop.enable = lib.mkEnableOption "Enable desktop";

  imports = [
    ./apps
    ./env
    ./modules
  ];

  config = lib.mkIf config.desktop.enable {

    services.flatpak.packages = [
      # ── Desktop tools ─────────────────────────────────────────────────────────
      "com.github.tchx84.Flatseal"          # flatpak permissions manager
      "io.missioncenter.MissionCenter"       # system monitor
      "net.cozic.joplin_desktop"             # notes
      # ── Media ─────────────────────────────────────────────────────────────────
      "org.qbittorrent.qBittorrent"
    ];

    home.packages = with pkgs; [
      # ── System & desktop ──────────────────────────────────────────────────────
      brightnessctl
      wl-clipboard
      blueberry                              # bluetooth manager GUI
      wlr-randr                              # display management (wlroots)
      wlsunset                               # blue light filter (any Wayland compositor)
      networkmanagerapplet                   # network manager system tray

      # ── Notifications & media control ─────────────────────────────────────────
      swaynotificationcenter                 # notification daemon (swaync)
      playerctl                              # MPRIS media player control

      # ── Communications ────────────────────────────────────────────────────────
      signal-desktop

      # ── Media creation & viewing ──────────────────────────────────────────────
      obs-studio
      audacity
      gimp
      inkscape
      sxiv
      mokuro                                   # manga OCR → HTML with text overlay

      # ── Office & productivity ─────────────────────────────────────────────────
      speedcrunch
      (texlive.combine {
        inherit (texlive)
          scheme-small
          collection-latexrecommended
          collection-latexextra
          collection-fontsrecommended
          collection-mathscience
          collection-bibtexextra;
      })
      libreoffice-qt
      hunspell
      anki-bin
    ];
  };
}
