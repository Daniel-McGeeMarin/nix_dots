{ pkgs, config, inputs, lib, osConfig, ... }:

{
  # To escape bashisms use ''${}
  home.packages = with pkgs; [
    bat
    eza
    bc
  ];
  programs.zsh = {
    completionInit = "";
    enable = true;
    history = {
      extended = true;
      ignoreAllDups = true;
      ignoreSpace = true;
      path = "$HOME/.local/share/zsh/history";
    };
    enableCompletion = false;
    defaultKeymap = "viins";
    shellAliases = {
      nixswitch = "st=\"$(date +%s)\"; sudo nixos-rebuild switch --flake $HOME/nixos/#nixBlade --cores 6 && notify-send 'updated' \"Took: $(($(date +%s)-$st))s\"";
      homeswitch = "st=\"$(date +%s)\"; home-manager switch --flake $HOME/nixos/#nixBlade --cores 6&& notify-send 'updated' \"Took: $(($(date +%s)-$st))s\"";
      nixtest = "st=\"$(date +%s)\"; sudo nixos-rebuild test --fast --flake $HOME/nixos/#nixBlade --cores 6 && notify-send 'updated' \"Took: $(($(date +%s)-$st))s\"";
      nixwatch = "cd ~/nixos && dirwatch nixtest";
      homewatch = "cd ~/nixos && dirwatch homeswitch";
      powerinfo = "upower -i /org/freedesktop/UPower/devices/battery_BAT1";
      cat = "bat";
      neofetch = "fastfetch";
      ls = "eza --icons=auto";
      vpnexit = lib.mkIf osConfig.services.mullvad-vpn.enable "mullvad split-tunnel add \$$";
      hexdec = "printf '%x\n' \$1";
    };
    initExtraBeforeCompInit = /*bash*/ ''
            # Set the root name of the plugins files (.txt and .zsh) antidote will use.
      zsh_plugins=''${ZDOTDIR:-~}/.zsh_plugins

      # Ensure the .zsh_plugins.txt file exists so you can add plugins.
      [[ -f ''${zsh_plugins}.txt ]] || touch ''${zsh_plugins}.txt

      # Lazy-load antidote from its functions directory.
      fpath=(${pkgs.antidote}/share/antidote/functions $fpath)
      autoload -Uz antidote

      # Generate a new static file whenever .zsh_plugins.txt is updated.
      if [[ ! ''${zsh_plugins}.zsh -nt ''${zsh_plugins}.txt ]]; then
        antidote bundle <''${zsh_plugins}.txt >|''${zsh_plugins}.zsh
      fi

      # Source your static plugins file.
      source ''${zsh_plugins}.zsh
    '';
    initExtra = /*bash*/ ''
            source $HOME/.p10k.zsh
            rn() {${pkgs.coreutils}/bin/shuf -i 1-$1 -n 1} # Random number
            dechex() {echo "$(
        (16#$1))"} # Decimal to Hex
            stopwatch() { local counter=0; while :; do printf "\\r%03d" "$counter"; tput el; counter=$((counter + 1)); sleep 1; done }
            bindec() {echo "$((2#$1))"} # Binary to Decimal
            binhex() {echo "obase=16; ibase=2; ''${(U)1}" | bc} # Binary to Hex
            hexbin() {echo "obase=2; ibase=16; ''${(U)1}" | bc} # Hex to Binary
            getip() { ${pkgs.curl}/bin/curl -s https://json.geoiplookup.io/"$1" | ${pkgs.jq}/bin/jq '.ip, .city, .isp' }
            0x0() { curl -F"file=@$1" https://0x0.st }
            genpas() {tr -dc A-Za-z0-9 </dev/urandom | head -c $1; echo}
            timer() {
              function usage() {
                echo "Usage: timer <seconds> <minutes> <hours>"
                echo "  seconds: Optional number of seconds (default 0)"
                echo "  minutes: Optional number of minutes (default 0)"
                echo "  hours: Optional number of hours (default 0)"
                return 1
              }
                    
              # Read input values
              local sec="''${1:-0}"
              local min="''${2:-0}"
              local hour="''${3:-0}"
      
              # Validate input values
              [[ "$sec" =~ ^[0-9]+$ ]] && [[ "$min" =~ ^[0-9]+$ ]] && [[ "$hour" =~ ^[0-9]+$ ]] || usage || return 1
      
              # Calculate total time in seconds
              local total_seconds=$((sec + min * 60 + hour * 3600))
      
              echo "Starting timer for $hour hours, $min minutes, and $sec seconds."
      
              while [ $total_seconds -gt 0 ]; do
                printf "\rTime remaining: %02d:%02d:%02d" $((total_seconds / 3600)) $(((total_seconds / 60) % 60)) $((total_seconds % 60))
                sleep 1
                total_seconds=$((total_seconds - 1))
              done
                    
              # Sound alert when the timer finishes
              printf "\nTime's up!\n"
              while true; do mpv ~/.local/share/sounds/Ping.ogg; sleep 0.25; done # Avoid echoing new lines by using `tput bel` for the beep
            }
            std() {
            echo 'echo """' > /tmp/out
              (`rep $1 $2`; ls) | xargs -n 1 nl -s$' ' -w1 |\
                  awk '{if ($2 ~ /^[0-9]+$/) for(i=0; i<$2; i++) print $0; else print $0}' |\
                  sed 's/^([0-9]*) [0-9]* /\1 /g' |\
                  sed '/^[0-9]* .*[0-9].*/!p' |\
                  shuf -n 1 >> /tmp/out
                  echo '"""' >> /tmp/out
            zsh /tmp/out
            nvim `awk 'NR == 2 {print $2}' /tmp/out` +`awk 'NR == 2 {print $1}' /tmp/out`
            }
            gitrestore() {
            git log --diff-filter = D - -summary | grep delete | awk '{
              print $4}' | fzf -m | while read -r file; do
              commit = "$(git log --diff-filter=D --name-only --pretty=format:"%H " | awk -v file="$file " '/./{p = p $0 "\n "}/^$/{if(p ~ file) print p; p = " "} END{if(p ~ file) print p}' | head -n 1)"
                git
                restore - -source="$commit^" -- "$file"
              done
              }

              rep() {for i in $(seq 1 $2);
              do echo "$1"; done}

              dirwatch() {
              while [ true ]; do
              local a="$(\ls -l -R)"
                if [ "$a" != "$b" ];
              then
              eval "$@"
              local b="$a"
                echo "Waiting for next update"
                fi
                sleep 3
                done
                }
                nix-shell-unstable() {
                echo """
      { pkgs ? import <nixpkgs> {} }:
      let
        unstable = import <nixos-unstable> {};
      in
      pkgs.mkShell {
        nativeBuildInputs = [
          unstable.$1
        ];
      }
      """ > /tmp/nix-shell-unstable.nix
                shift
                nix-shell /tmp/nix-shell-unstable.nix $@
                }
                swap() {
                local a=$1
                local b=$2
                local tmp=$(mktemp)
                mv $a $tmp
                mv $b $a
                mv $tmp $b
                }
    '';
  };
  home.file.".zsh_plugins.txt".text = ''
    jeffreytse/zsh-vi-mode
    zsh-users/zsh-autosuggestions
    zdharma-continuum/fast-syntax-highlighting kind:defer
    romkatv/powerlevel10k
  '';
}
