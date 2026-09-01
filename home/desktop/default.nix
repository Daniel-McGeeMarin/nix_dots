{ config, lib, pkgs, inputs, osConfig, ... }:
# The graphical half of the user environment: compositor, browsers, GUI apps,
# Flatpaks, theming.
#
# There is no `desktop.enable`. A host either imports this tree or it does not,
# which is the same rule system/head follows. The flag it replaces was leaky by
# construction - it had to be repeated in every file below, and the three that
# forgot it (hyprland, rice.nix, the media CLI tools) meant a host with
# desktop.enable = false still installed a compositor.
#
# nix-flatpak is imported here rather than one level up because Flatpak is only
# ever used for GUI applications.
{
  imports = [
    ./apps
    ./env
    ./modules
    ./rice.nix
    inputs.nix-flatpak.homeManagerModules.nix-flatpak
  ];

  config = {

    services.flatpak.packages = [
      # ── Desktop tools ─────────────────────────────────────────────────────────
      "com.github.tchx84.Flatseal"          # flatpak permissions manager
      "io.missioncenter.MissionCenter"       # system monitor
      "net.cozic.joplin_desktop"             # notes
      "md.obsidian.Obsidian"                 # notes (sandboxed — use Flatseal to restrict to ~/Documents)
      # ── Comms ─────────────────────────────────────────────────────────────────
      "app.openbubbles.OpenBubbles"          # iMessage client (needs an OpenBubbles/BlueBubbles server)
      # ── Media ─────────────────────────────────────────────────────────────────
      "org.qbittorrent.qBittorrent"
    ];

    home.packages = with pkgs; [
      # ── Browsers & editors ────────────────────────────────────────────────────
      brave
      vscodium
      unstable.unfree.code-cursor

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
      inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.signal-desktop
      element-desktop
      unstable.unfree.zoom-us                # remote control only works in an X11 session

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
