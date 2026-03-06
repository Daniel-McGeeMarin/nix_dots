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
    hycov={
      url = "github:DreamMaoMao/hycov";
      inputs.hyprland.follows = "hyprland";
    };
    hyprgrass = {
      url = "github:horriblename/hyprgrass";
      inputs.hyprland.follows = "hyprland"; # IMPORTANT
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

    # Nixpkgs fork with Howdy module + package
    nixpkgs-howdy = {
      url = "github:fufexan/nixpkgs/howdy";
      flake = false;
    };

    # Local secrets; kept out of VCS. See README.
    secrets = {
      url = "path:/home/xia/nixos/secrets.nix";
      flake = false;
    };

    caelestia-shell = {
    # We are adding the version tag 'v1.4.2' to the end of the URL
    url = "github:caelestia-dots/shell"; 
      #inputs.nixpkgs.follows = "nixpkgs-unstable";
  };    
 
  };

  outputs = { self, nixpkgs, home-manager, nixpkgs-master, nixpkgs-unstable, caelestia-shell, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      secrets = import inputs.secrets;

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
      nixosConfigurations.XiaNix = nixpkgs.lib.nixosSystem rec {
        specialArgs = { inherit inputs secrets; };
        modules = [
          ({ config, pkgs, ... }: {
            # added just for illogical dots
            nixpkgs.config.allowUnfree = true;


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
          ./hosts/XiaNix/configuration.nix
        ];
      };
      homeConfigurations.XiaNix = home-manager.lib.homeManagerConfiguration {
        extraSpecialArgs = { inherit inputs secrets; };
        inherit pkgs;
        modules = [
          
          ({ config, pkgs, ... }: { nixpkgs.overlays = [ overlay-unfree overlay-unstable overlay-unstable-unfree overlay-master overlay-master-unfree ]; })
	  ./hosts/XiaNix/home.nix
        ];
      };
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem rec {
        specialArgs = { inherit inputs secrets; };
        modules = [
          ({ config, pkgs, ... }: { nixpkgs.overlays = [ overlay-unfree overlay-master overlay-master-unfree overlay-unstable overlay-unstable-unfree ]; })
          ./hosts/phantomServ/configuration.nix
        ];
      };
      homeConfigurations.nixos = home-manager.lib.homeManagerConfiguration {
        extraSpecialArgs = { inherit inputs secrets; };
        inherit pkgs;
        modules = [
          ({ config, pkgs, ... }: { nixpkgs.overlays = [ overlay-unfree overlay-unstable overlay-unstable-unfree overlay-master overlay-master-unfree ]; })
          ./hosts/phantomServ/home.nix
        ];
      };
    };
}
