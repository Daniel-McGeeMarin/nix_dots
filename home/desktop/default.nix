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
      "md.obsidian.Obsidian"                 # notes (sandboxed — use Flatseal to restrict to ~/Documents)
      # ── Media ─────────────────────────────────────────────────────────────────
      "org.qbittorrent.qBittorrent"
    ];

    home.packages = with pkgs; [
      # ── Browsers & editors ────────────────────────────────────────────────────
      brave
      vscodium

      # ── System & desktop ──────────────────────────────────────────────────────
      brightnessctl
      wl-clipboard
      blueberry                              # bluetooth manager GUI
      wlr-randr                              # display management (wlroots)
      wlsunset                               # blue light filter (any Wayland compositor)
      networkmanagerapplet                   # network manager system tray

      # ── Audio ─────────────────────────────────────────────────────────────────
      (lib.mkIf ((osConfig.services or { }).pipewire.enable or false) helvum)       # PipeWire patchbay GUI
      (lib.mkIf ((osConfig.services or { }).pipewire.pulse.enable or false) pavucontrol) # PulseAudio volume control

      # ── Media control ─────────────────────────────────────────────────────────
      playerctl                              # MPRIS media player control
      syncplay                               # synchronized media playback

      # ── Communications ────────────────────────────────────────────────────────
      signal-desktop
      element-desktop

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
