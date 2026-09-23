{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-flatpak = {
      url = "github:gmodena/nix-flatpak";
    };
    caelestia-shell = {
      # Pinned to a release tag, and deliberately NOT following
      # nixpkgs-unstable. It used to follow, and ai-cli-autoupdate re-pins
      # nixpkgs-unstable daily (to keep claude-code/codex current), so every
      # tick changed caelestia's inputs and nix recompiled quickshell and the
      # shell (C++/Qt, ~10+ min at full CPU) for no benefit. With its own
      # nixpkgs it rebuilds only when this tag is bumped by hand.
      # Releases land roughly every 3 weeks; bump with
      #   nix flake lock --override-input caelestia-shell github:caelestia-dots/shell/vX.Y.Z
      url = "github:caelestia-dots/shell/v2.5.0";
    };

    nixvim = {
      url = "github:nix-community/nixvim/nixos-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Hello, electron was pinned manually because there was no build when you
    # used it before, remember to unpin eventually if things are not working there.
    # nixpkgs@03c7292 (2026-06-24) has a Hydra cache miss for electron-41.7.2.
    # This commit (2026-06-09) has electron-41.7.1 which IS cached.
    # To unpin: remove this input, remove overlay-electron-pin, run nix flake lock.
    nixpkgs-electron-pin.url = "github:NixOS/nixpkgs/8a6fd288ce1b6f52fa0038397f36608f64743d5a";

    graphide = {
      # git+ssh, not `github:`: the repo is private and the GitHub *API*
      # fetcher `github:` uses needs an access token in nix.conf, which this
      # machine deliberately does not have. SSH reuses the key git already
      # authenticates with. Still a GitHub-hosted, revision-locked input --
      # NOT the local ~/Documents/startup/Graphide/monolith checkout, whose
      # branch state changes constantly and isn't what should end up
      # installed system-wide.
      url = "git+ssh://git@github.com/graphideHQ/monolith";
      # Deliberately NO inputs.nixpkgs.follows. graphide keeps its own tested
      # nixpkgs pin independent of this flake's, so the installed gr/grat/gred
      # is exactly what graphide's own dev shell and CI built and tested.
    };

    # The same repo again, for the home-manager module only
    # (homeManagerModules.graphide). `graphide` above is pinned to a RELEASE
    # commit by graphide-autoupdate, and gred refuses a tarball older than the
    # tree it is evaluated in, so the module cannot ride on that input without
    # waiting for a release. Update it on its own: nix flake update graphide-tools.
    graphide-tools.url = "git+ssh://git@github.com/graphideHQ/monolith";
  };

  outputs = { self, nixpkgs, home-manager, nixpkgs-unstable, caelestia-shell, nixvim, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      secrets = import (builtins.getEnv "HOME" + "/nixos/local.nix");

      overlay-unstable = final: prev: {
        unstable = nixpkgs-unstable.legacyPackages.${system};
      };
      overlay-unfree = final: prev: {
        unfree = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
      };
      overlay-unstable-unfree = final: prev: {
        unstable = prev.unstable // {
          unfree = import nixpkgs-unstable {
            inherit system;
            config.allowUnfree = true;
          };
        };
      };
      # See nixpkgs-electron-pin input above for explanation.
      overlay-electron-pin = final: prev: {
        electron_41 = inputs.nixpkgs-electron-pin.legacyPackages.${system}.electron_41;
      };
      # The hackerboard: `nix run .#dashboard` from anywhere in this repo.
      # `pkgs.lix` to match `nix.package` on both hosts -- see dashboard.nix.
      dashboard = import ./dashboard.nix { inherit pkgs; nix = pkgs.lix; };
    in
    rec {
      packages.${system}.dashboard = dashboard;
      apps.${system}.dashboard = { type = "app"; program = "${dashboard}/bin/dashboard"; };

      nixosConfigurations.XiaNix = nixpkgs.lib.nixosSystem rec {
        specialArgs = { inherit inputs secrets; };
        modules = [
          ({ config, pkgs, ... }: {
            # added just for illogical dots
            nixpkgs.config.allowUnfree = true;


            nixpkgs.overlays = [
              overlay-unfree
              overlay-unstable
              overlay-unstable-unfree
              overlay-electron-pin
            ];
          })
          inputs.agenix.nixosModules.default
          ./hosts/XiaNix/configuration.nix
        ];
      };
      homeConfigurations.XiaNix = home-manager.lib.homeManagerConfiguration {
        extraSpecialArgs = { inherit inputs secrets; flakeAttr = "XiaNix"; };
        inherit pkgs;
        modules = [
          ({ config, pkgs, ... }: {
            nixpkgs.config.allowUnfree = true;
            nixpkgs.overlays = [ overlay-unfree overlay-unstable overlay-unstable-unfree overlay-electron-pin ];
          })
          ./hosts/XiaNix/home.nix
        ];
      };
      nixosConfigurations.XiaServer = nixpkgs.lib.nixosSystem rec {
        specialArgs = { inherit inputs secrets; };
        modules = [
          ({ config, pkgs, ... }: { nixpkgs.overlays = [ overlay-unfree overlay-unstable overlay-unstable-unfree overlay-electron-pin ]; })
          inputs.agenix.nixosModules.default
          ./hosts/XiaServer/configuration.nix
        ];
      };
      homeConfigurations.XiaServer = home-manager.lib.homeManagerConfiguration {
        extraSpecialArgs = { inherit inputs secrets; flakeAttr = "XiaServer"; };
        inherit pkgs;
        modules = [
          ({ config, pkgs, ... }: {
            nixpkgs.config.allowUnfree = true;
            nixpkgs.overlays = [ overlay-unfree overlay-unstable overlay-unstable-unfree overlay-electron-pin ];
          })
          ./hosts/XiaServer/home.nix
        ];
      };
    };
}
