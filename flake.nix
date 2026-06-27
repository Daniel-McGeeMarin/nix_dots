{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-master.url = "github:nixos/nixpkgs/master";
    nix-flatpak = {
      url = "github:gmodena/nix-flatpak";
    };
    nix-colors.url = "github:misterio77/nix-colors";
    gBar.url = "github:scorpion-26/gBar";
    xremap-flake.url = "github:xremap/nix-flake";
    hyprland = {
      url = "github:hyprwm/Hyprland";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    firefox-css-hacks = { url = "github:MrOtherGuy/firefox-csshacks"; flake = false; };
    fcitx5-gruvbox = { url = "github:ayamir/fcitx5-gruvbox"; flake = false; };
    hypr-darkwindow = {
      url = "github:micha4w/Hypr-DarkWindow/v0.44.0";
      inputs.hyprland.follows = "hyprland";
    };
    gruvbox-wallpapers = { url = "github:AngelJumbo/gruvbox-wallpapers"; flake = false; };
    gruvbox-kvantum = { url = "github:isouravgope/Gruvbox-Kvantum"; flake = false; };
    patched-sddm-sugar-dark = {
      url = "github:BenMac31/sddm-sugar-dark";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, home-manager, nixpkgs-master, nixpkgs-unstable, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      overlay-master = final: prev: {
        master = import nixpkgs-master.legacyPackages.${system};
      };
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
      overlay-master-unfree = final: prev: {
        master.unfree = import nixpkgs-master {
          inherit system;
          config.allowUnfree = true;
        };
      };
    in
    rec {
      nixosConfigurations.nixBlade = nixpkgs.lib.nixosSystem rec {
        specialArgs = { inherit inputs; };
        modules = [
          ({ config, pkgs, ... }: {
            nixpkgs.overlays = [
              overlay-unfree
              overlay-master
              overlay-master-unfree
              overlay-unstable
              overlay-unstable-unfree
              (final: prev: {
                sddm-sugar-dark = prev.sddm-sugar-dark.overrideAttrs {
                  src = inputs.patched-sddm-sugar-dark;
                };
              })
            ];
          })
          ./hosts/nixBlade/configuration.nix
        ];
      };
      homeConfigurations.nixBlade = home-manager.lib.homeManagerConfiguration {
        extraSpecialArgs = { inherit inputs; };
        inherit pkgs;
        modules = [
          ({ config, pkgs, ... }: { nixpkgs.overlays = [ overlay-unfree overlay-unstable overlay-unstable-unfree overlay-master overlay-master-unfree ]; })
          ./hosts/nixBlade/home.nix
        ];
      };
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem rec {
        specialArgs = { inherit inputs; };
        modules = [
          ({ config, pkgs, ... }: { nixpkgs.overlays = [ overlay-unfree overlay-master overlay-master-unfree overlay-unstable overlay-unstable-unfree ]; })
          ./hosts/phantomServ/configuration.nix
        ];
      };
      homeConfigurations.nixos = home-manager.lib.homeManagerConfiguration {
        extraSpecialArgs = { inherit inputs; };
        inherit pkgs;
        modules = [
          ({ config, pkgs, ... }: { nixpkgs.overlays = [ overlay-unfree overlay-unstable overlay-unstable-unfree overlay-master overlay-master-unfree ]; })
          ./hosts/phantomServ/home.nix
        ];
      };
    };
}
