{ ... }:
# Resource ceilings for the desktop.
#
# Heavy AI-agent workloads on long uptimes filled the 126 GB root filesystem to
# 95%: /tmp alone reached 20 GB across 6530 entries, and a single wide build
# (scancode with 22 workers, ~700 MB each) once left 310 MB of RAM free and made
# the machine unusable. Nothing here changes behaviour under normal load — it
# only bounds things that previously had no bound.
#
# Deliberately host-scoped rather than living in system/default.nix, which
# XiaServer also imports: an OOM killer that reaches for the largest process
# would target podman containers there.
{
  # /tmp is a real directory on the root ext4 volume, not a tmpfs, so on a
  # multi-day uptime nothing ever reclaimed it.
  boot.tmp.cleanOnBoot = true;

  systemd.tmpfiles.rules = [
    # Browser-automation profiles leaked by agent runs; 14 had accumulated at
    # ~120 MB each. Nothing cleans these up on its own.
    "R! /tmp/puppeteer_dev_firefox_profile-* - - - 1d"

    # The gred fork checkout. Every entry point defaults to /tmp/vscode-src
    # (gred-patch-dev, apply-patches.sh, apply-branding.sh), but the tree is
    # 3 GB and holds uncommitted work, so it lives on /home and /tmp only holds
    # a symlink. tmpfiles processes parents before children, so this is
    # recreated after cleanOnBoot empties /tmp. Keeps the documented workflow
    # working unchanged while keeping the bytes off root.
    "L /tmp/vscode-src - - - - /home/xia/.cache/graphide/vscode-src"
  ];

  # Compressed swap in RAM, at higher priority than the disk partition, so
  # paging stops landing on the SSD (1.1 TB written in 5.6 days). memoryPercent
  # bounds the device's uncompressed capacity, not the RAM it consumes — zstd
  # runs about 3:1, so a 7.5 GB device costs roughly 2.5 GB of real memory.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 25;
  };

  # Shed the largest offender instead of freezing when memory runs out. The
  # interactive session is protected; build tooling and browsers go first.
  services.earlyoom = {
    enable = true;
    freeMemThreshold = 5;
    freeSwapThreshold = 10;
    enableNotifications = true;
    extraArgs = [
      "--avoid"
      "^(cursor|Hyprland|quickshell|systemd|sshd|zsh|kitty|pipewire|wireplumber)$"
      "--prefer"
      "^(scancode|python3\\.[0-9]+|node|esbuild|tsc|go|rustc|cc1plus|firefox)$"
    ];
  };
}
