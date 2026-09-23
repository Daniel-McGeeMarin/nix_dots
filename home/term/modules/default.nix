{ lib, pkgs, inputs, flakeAttr ? "", ... }:
{
  imports = [
    ./ai.nix
    # gr/grat/gred and graphide-autoupdate. The module lives in the monolith
    # (nix/home-manager/graphide.nix) and comes in through the same pinned
    # `graphide` input it installs from; the settings are in hosts/*/home.nix.
    inputs.graphide.homeManagerModules.graphide
    ./privatellm.nix
    ./programming
  ];

  # The updater switches this flake's own homeConfigurations entry, with the
  # home-manager this flake is evaluated with rather than whatever is on PATH.
  graphide.autoUpdate.flakeAttr = lib.mkDefault flakeAttr;
  graphide.autoUpdate.homeManagerPackage =
    lib.mkDefault inputs.home-manager.packages.${pkgs.stdenv.hostPlatform.system}.home-manager;
}
