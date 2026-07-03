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

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Hello, electron was pinned manually because there was no build when you
    # used it before, remember to unpin eventually if things are not working there.
    # nixpkgs@03c7292 (2026-06-24) has a Hydra cache miss for electron-41.7.2.
    # This commit (2026-06-09) has electron-41.7.1 which IS cached.
    # To unpin: remove this input, remove overlay-electron-pin, run nix flake lock.
    nixpkgs-electron-pin.url = "github:NixOS/nixpkgs/8a6fd288ce1b6f52fa0038397f36608f64743d5a";
  };

  outputs = { self, nixpkgs, home-manager, nixpkgs-unstable, caelestia-shell, nixvim, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      secrets = import (builtins.getEnv "HOME" + "/nixos/secrets.nix");

      overlay-unstable = final: prev: {
        unstable = import nixpkgs-unstable.legacyPackages.${system};
      };
      overlay-unfree = final: prev: {
        unfree = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
      };
      overlay-unstable-unfree = final: prev: {
        unstable.unfree = import nixpkgs-unstable {
          inherit system;
          config.allowUnfree = true;
        };
      };
      # See nixpkgs-electron-pin input above for explanation.
      overlay-electron-pin = final: prev: {
        electron_41 = inputs.nixpkgs-electron-pin.legacyPackages.${system}.electron_41;
      };
    in
    rec {
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
        extraSpecialArgs = { inherit inputs secrets; };
        inherit pkgs;
        modules = [
          inputs.zen-browser.homeModules.default
          ({ config, pkgs, ... }: {
            nixpkgs.config.allowUnfree = true;
            nixpkgs.overlays = [ overlay-unfree overlay-unstable overlay-unstable-unfree overlay-electron-pin ];
          })
          ./hosts/XiaNix/home.nix
        ];
      };
      nixosConfigurations.XiaServer = nixpkgs.lib.nixosSystem rec {
        # XiaServer uses agenix for secrets, not secrets.nix — pass empty set so
        # the flake builds cleanly under sudo (where HOME is unset).
        specialArgs = { inherit inputs; secrets = {}; };
        modules = [
          ({ config, pkgs, ... }: { nixpkgs.overlays = [ overlay-unfree overlay-unstable overlay-unstable-unfree overlay-electron-pin ]; })
          inputs.agenix.nixosModules.default
          { home-manager.sharedModules = [ inputs.zen-browser.homeModules.default ]; }
          ./hosts/XiaServer/configuration.nix
        ];
      };
      homeConfigurations.XiaServer = home-manager.lib.homeManagerConfiguration {
        extraSpecialArgs = { inherit inputs; secrets = {}; };
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
