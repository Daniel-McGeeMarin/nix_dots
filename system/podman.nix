{ lib, pkgs, ... }:
# Rootful Podman, plus the timer that keeps every registry-tagged container
# current.
#
# Its own module rather than a block in the host file, and deliberately outside
# both service trees, because both of them need it: `serv` runs the mcgeedan
# containers and `graphide` runs the product stack. It used to be split across
# two places that could not both survive a switch being flipped -- the podman
# settings sat in hosts/XiaServer/configuration.nix, and the auto-update timer
# sat inside serv/apps.nix (the personal site), so turning the personal site off
# would have quietly stopped updating the Graphide API too.
#
# Rootful is the important word. The containers run as root on the host, so
# every `podman` command you type needs sudo to see them; `podman ps` without it
# lists your own rootless containers, which is an empty list.
{
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    # Container-to-container name resolution on the default network. Note that
    # DNS resolving is not the same as being reachable: services inside
    # containers frequently bind 127.0.0.1 and are unreachable from a sibling
    # even though the name resolves.
    defaultNetwork.settings.dns_enabled = true;
  };

  virtualisation.oci-containers.backend = "podman";

  # Pulls a fresh image for every container labelled
  # io.containers.autoupdate = "registry" and restarts it. Containers built on
  # this host carry a localhost/ tag and must set autoUpdate = false, or this
  # fails on every tick trying to pull a tag no registry has.
  systemd.timers.podman-auto-update = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:0/5";
      # NOT Persistent. Same reasoning as the two autobuild timers in
      # system/graphide/{demo,web}.nix: this is a 5-minute poller, so the worst
      # case without Persistent is a 5-minute wait, which is nothing. With it,
      # a `nixos-rebuild switch` that touches this unit's definition can make
      # systemd treat the missing "last fired" record as a missed run and pull
      # + restart every registry-tagged container immediately, inside the
      # switch's own activation window - and switch-to-configuration waits for
      # units it starts to finish. Caught this exact failure mode on the
      # sibling autobuild timers on 2026-09-01; fixing it here before it
      # repeats with a dozen containers pulling at once instead of one build.
      Persistent = false;
    };
  };

  # mkForce because the unit ships with the podman package and its ExecStart
  # points at a podman that is not the one in this closure.
  systemd.services.podman-auto-update = {
    serviceConfig.ExecStart = lib.mkForce "${pkgs.podman}/bin/podman auto-update";
  };
}
