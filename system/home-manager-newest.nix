{ config, lib, pkgs, ... }:
# A reboot must not roll anyone's home packages back.
#
# Home Manager is switched two ways on these hosts: by `nixos-rebuild switch`
# (the NixOS module, which bakes a home generation into the system) and by a
# standalone `home-manager switch` (`homeswitch`, and on XiaNix ai.autoUpdate
# every morning, onto a newer nixpkgs-unstable). The module's
# home-manager-<user> service also runs at every boot, and it re-activated the
# generation baked into the system: the one from the last nixos-rebuild. So
# after any standalone switch, each boot put the older packages back into
# ~/.nix-profile until the next morning's auto-update moved them forward
# again. Signal Desktop migrates its database forward and refuses to open a
# newer one, so on 2026-10-22 boot swapped 8.31 back to 8.29 and Signal quit
# with "DBVersionFromFutureError: User version is 1830 but the expected
# maximum version is 1800". The same flip-flop restarted the user units whose
# definitions differ between the two generations every morning at 08:00, the
# auto-update unit itself included, mid-activation.
#
# So the service now activates whichever generation came last: the standalone
# profile's current one when that profile was switched after the system
# profile was, the system's own otherwise. `nixos-rebuild switch` updates the
# system profile before it restarts this service, so a rebuild still applies
# its own home generation. `nixos-rebuild test` does not, so after a newer
# standalone switch it leaves the standalone one active.
let
  start = name: user:
    let
      home = config.users.users.${name}.home;
      systemGen = user.home.activationPackage;
    in
    # -l as Home Manager's own wrapper (hm-setup-env) does: activation expects
    # the user's login environment.
    pkgs.writeScript "hm-activate-newest-${name}" ''
      #!${pkgs.bash}/bin/bash -el
      gen=${systemGen}
      for profile in "${home}/.local/state/nix/profiles/home-manager" \
                     "/nix/var/nix/profiles/per-user/${name}/home-manager"; do
        [ -L "$profile" ] || continue
        # stat without -L reads the links themselves: when each was last switched.
        if [ "$(stat -c %Y "$profile")" -gt "$(stat -c %Y /nix/var/nix/profiles/system)" ] \
           && [ -x "$profile/activate" ]; then
          gen=$(readlink -f "$profile")
          echo "standalone home-manager switch is newer than the system; activating $gen"
        fi
        break
      done

      # A standalone generation finds nix-env on PATH rather than having it baked in.
      export PATH="${config.nix.package}/bin:$PATH"
      eval "$(
        XDG_RUNTIME_DIR=''${XDG_RUNTIME_DIR:-/run/user/$UID} systemctl --user show-environment 2> /dev/null \
        | ${pkgs.gnused}/bin/sed -En '/^(DBUS_SESSION_BUS_ADDRESS|DISPLAY|WAYLAND_DISPLAY|XAUTHORITY|XDG_RUNTIME_DIR)=/s/^/export /p'
      )"
      exec "$gen/activate" --driver-version 1
    '';
in
{
  systemd.services = lib.mapAttrs' (name: user:
    lib.nameValuePair "home-manager-${name}" {
      serviceConfig.ExecStart = lib.mkForce "${start name user}";
    }
  ) config.home-manager.users;
}
