# HackerPi -- a Raspberry Pi 3B that serves the hackerboard to the LAN.
#
# This host deliberately does NOT import ../../system: that tree assumes an
# x86 EFI machine (grub.nix sets systemd-boot unconditionally) and carries a
# desktop-sized package set. A 1 GB Pi gets a self-contained config instead,
# and the few estate patterns worth having (key-only sshd, tailscale as the
# admin path) are restated here rather than inherited.
#
# The same module set backs two flake outputs:
#   HackerPi     aarch64, plus ./sd-image.nix  -> the real image for the Pi
#   HackerPiSim  x86_64,  plus ./sim.nix       -> a qemu VM for testing
# Everything in this file is shared; anything hardware- or VM-specific lives
# in those two leaves.
{ config, lib, pkgs, ... }:

let
  # One list, everyone who administers Graphide machines. Mirrors the
  # adminKeys list in monolith/nix/hosts/XiaServer/default.nix -- if a key
  # changes there, change it here too.
  adminKeys = [
    # Ben (greencheetah)
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQChQYMz+Q2dzTLTISmBlFHPUDRAzvupt3Sw/u2fpjZXjM3VLVU/VFq8gjmMMVVKTJBXUHwbdJiiNzvx0CobBYYXz5dMjV5Q3dubC2iikS70CX1M13n1yFzIebMsL8vTQaM/g5g0Sg9woAW8b74uWH5r6h6xmXOR7tfFi8m2tDmIllpRxXe49G9Hcmr4NQaHs3hb/A/31JTFjJDTvFqRN9BNUYgC4OR51FNFRsj2TZ8ecaYsSTcFioRG4jBYpU6URbFHLVrs3C5g9Fh8LKW6ISSd3G9XFnEYYXFAp0C8SiEZR02VYvU61N68IeDRikscjQ1JOm8r2HKGhi+Nv4Mc22qxPrpn4bg4jbAPzwms2OTX2rkI6ghZYhzXYOHzqszqe+J7bPXUdHmDLzXIb1mTNy9dAU1FY3UqbCUXb4Hqx0CjvTzbCE7R8ME537qfy0QkvtjLFek9Azh36iKzGnH7rVdmKQuzShVkYCnUqItPViamm7Py1Rbv1HPO7X4eIrsy2vc= greencheetah@fedora"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKKNM6M/MulxMZa+FPfL3yLJKk2vmU+xxxYOmNpJg3WF benjamin.m@voxitec.com"
    # Dan
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEXdgXkjZZe0PQute6iiEDpKGrZQ7VlP7+nUXkzodE8s xia@XiaNix"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGHu7KxjsSDuVfKhSwbCe8GxGJP1Y4Oo4JMwnEJpu3Um gram-key"
  ];
in
{
  imports = [ ./hackerboard.nix ];

  networking.hostName = "hackerpi";
  time.timeZone = "America/Los_Angeles";

  # Key-only, no root, no passwords anywhere. mutableUsers = false means the
  # image cannot grow a password out of band either -- the SSH keys below are
  # the only way in, which is the point for a box that holds company data and
  # sits on a shelf where anyone can pick it up. (What this does NOT protect
  # against is someone reading the SD card directly; there's no disk
  # encryption, a headless Pi has nowhere to type a passphrase at boot.)
  users.mutableUsers = false;
  users.users.xia = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = adminKeys;
  };
  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };
  # Slow brute-force probes down even on a LAN; costs nothing.
  services.fail2ban.enable = true;

  networking.firewall = {
    enable = true;
    # 22 admin, 8420 the board. Nothing else listens on purpose.
    allowedTCPPorts = [ 22 8420 ];
  };

  # The admin path from anywhere, same as the rest of the estate. Ships
  # unauthenticated; `sudo tailscale up` once on the running box enrolls it.
  services.tailscale.enable = true;
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  # hackerpi.local for the browsers that will open the board.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
    };
  };

  # 1 GB of RAM. The board itself is light, but the on-device web rebuild
  # (vite) and nix evaluation both spike past what's left -- compressed swap
  # is the difference between "slow" and "OOM-killed".
  zramSwap.enable = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  # Updates leave old web bundles behind; a 32 GB stick still fills eventually.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  environment.systemPackages = with pkgs; [ git vim htop ];

  system.stateVersion = "25.11";
}
