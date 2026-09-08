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
      url = "github:caelestia-dots/shell";
      # Share the single unstable nixpkgs so caelestia only builds its own
      # components (quickshell, cef, the shell) instead of pulling a whole
      # separate nixpkgs + toolchain.
      inputs.nixpkgs.follows = "nixpkgs-unstable";
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

    # The Graphide monorepo, for baking the hackerboard into the HackerPi
    # image. flake = false keeps monolith's own (enormous) input set out of
    # this lock file -- we import hackerboard/nix/ as a plain expression.
    # git+file because the repo is private and the checkout is already here;
    # `nix flake lock --update-input monolith` re-pins to its current HEAD.
    monolith = {
      url = "git+file:///home/xia/Documents/startup/Graphide/monolith";
      flake = false;
    };
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
      dashboard = import ./dashboard.nix { inherit pkgs; };
    in
    rec {
      packages.${system} = {
        dashboard = dashboard;
        # nix build .#hackerpi-vm -> ./result/bin/run-hackerpi-vm
        hackerpi-vm = nixosConfigurations.HackerPiSim.config.system.build.vm;
      };
      apps.${system}.dashboard = { type = "app"; program = "${dashboard}/bin/dashboard"; };
      # The dd-able .img for the real Pi (needs aarch64 binfmt on the builder).
      packages.aarch64-linux.hackerpi-image = nixosConfigurations.HackerPi.config.system.build.sdImage;

      # HackerPi: the Raspberry Pi 3B that serves the hackerboard. Two builds
      # of the same modules -- real aarch64 hardware and an x86 qemu sim; see
      # hosts/HackerPi/configuration.nix. No overlays on purpose: they
      # hardcode x86_64, and nothing here needs them. No home-manager either;
      # the box has no interactive user environment worth managing.
      nixosConfigurations.HackerPi = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [
          ./hosts/HackerPi/configuration.nix
          ./hosts/HackerPi/sd-image.nix
        ];
      };
      nixosConfigurations.HackerPiSim = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [
          ./hosts/HackerPi/configuration.nix
          ./hosts/HackerPi/sim.nix
        ];
      };

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
