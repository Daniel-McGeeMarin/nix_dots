{ pkgs, config, inputs, lib, osConfig, ... }:

{
  # To escape bashisms use ''${}
  home.packages = with pkgs; [
    bat eza bc tree curl jq gcc cgdb valgrind gnumake appimage-run
  ];

  programs.zsh = {
    completionInit = "";
    enable = true;
    history = {
      extended = true;
      ignoreAllDups = true;
      ignoreSpace = true;
      path = "$HOME/.local/share/zsh/history";
      save = 10000;
      size = 10000;
    };
    enableCompletion = true;
    defaultKeymap = "viins";
    shellAliases = {
      
      #Mine
      fixaudio = "sudo ~/nixos/modules/nixos/head/lg-gram-audio.sh";
      pys = "source ./venv/bin/activate";
      flvim = "nvim $(fzf)";
      fl = "nvim $(fzf)";
      sch = "cd ~/Documents/school/";
      c = "cd ~/.config/";
      p = "cd ~/Documents/Projects";
      d = "cd ~/Documents";
      m = "cd ~/MyApps/";
      #sudo = "doas";
      sudoedit = "doas rnano";
      n = "cd ~/nixos/";
      apps="librewolf --no-remote --profile ~/.librewolf/default-kiosk &";      tethering = "sudo iptables -t mangle -A POSTROUTING -j TTL --ttl-set 65";

      #Bens

      nixswitch = "st=\"$(date +%s)\"; sudo nixos-rebuild switch --flake $HOME/nixos/#XiaNix --cores 8 && notify-send 'updated' \"Took: $(($(date +%s)-$st))s\"";
      homeswitch = "st=\"$(date +%s)\"; home-manager switch --flake $HOME/nixos/#XiaNix --cores 8&& notify-send 'updated' \"Took: $(($(date +%s)-$st))s\"";
      nixtest = "st=\"$(date +%s)\"; sudo nixos-rebuild test --fast --flake $HOME/nixos/#XiaNix --cores 8 && notify-send 'updated' \"Took: $(($(date +%s)-$st))s\"";
      nixwatch = "cd ~/nixos && dirwatch nixtest";
      homewatch = "cd ~/nixos && dirwatch homeswitch";
      powerinfo = "upower -i /org/freedesktop/UPower/devices/battery_BAT1";
      cat = "bat";
      neofetch = "fastfetch";
      ls = "eza --icons=auto";
      vpnexit = lib.mkIf osConfig.services.mullvad-vpn.enable "mullvad split-tunnel add \$$";
      hexdec = "printf '%x\n' \$1";
    };



    initExtra = /*bash*/ ''
            [[ -f $HOME/.p10k.zsh ]] && source $HOME/.p10k.zsh

            # Caelestia terminal theming for new terminals (kitty)
            if [[ -o interactive ]] && [[ -z "$TMUX" ]]; then
              [[ -f "$HOME/.local/state/caelestia/sequences.txt" ]] && cat "$HOME/.local/state/caelestia/sequences.txt" 2>/dev/null
            fi
                      


            rn() {${pkgs.coreutils}/bin/shuf -i 1-$1 -n 1} # Random number
        
        
                    # Command history interactive fzf
            his() {
              emulate -L zsh -o no_aliases
              local cmd
              cmd=$(fc -ln 1 | fzf --height 40% --reverse --prompt='history> ') || return
              print -S -- "$cmd"
              eval -- "$cmd"
            }

            # Upload to 0x0.st
            0x0() { curl -F"file=@$1" https://0x0.st }

            # Directory picker using fzf
            fcd () {
              emulate -L zsh -o no_aliases
              local dir
              dir=$(
                { find . \( \
                  -path './.local/share/waydroid' -o \
                  -path './.local/share/waydroid/*' -o \
                  -path '*/.git' -o \
                  -path '*/node_modules' -o \
                  -path '*/.cache' -o \
                  -path '*/__pycache__' -o \
                  -path '*/venv' -o \
                  -path '*/env' \) -prune -o \
                  -type d -not -path '.' -print 2>/dev/null; } \
                | sed 's|^\./||' | awk '{print length, $0}' | sort -n -k1,1 | cut -d' ' -f2- \
                | fzf --height 40% --reverse --prompt='subdir> ' --tiebreak=length,index
              ) || return
              cd -- "$dir"
              print -P "%F{green}➜ %f$PWD"
            }

            # App launchers




            cursor() { appimage-run "$HOME/MyApps/Cursor/Cursor-2.4.35-x86_64.AppImage" >/dev/null 2>&1 &}
            bb() { "$HOME/MyApps/bluebubbles-linux-x86_64/bluebubbles" >/dev/null 2>&1 &! }
            emu() { "$HOME/MyApps/sudachi-linux-v1.0.14/sudachi" >/dev/null 2>&1 &! }


            flatrun() {
              if ! command -v fzf >/dev/null 2>&1; then
                echo "fzf is required."
                return 1
              fi

              local selection
              selection=$(flatpak list --app --columns=application,name | \
                          fzf --prompt="Open flatpak: " --delimiter=$'\t' --with-nth=2)
              [[ -z "$selection" ]] && return 0

              local appid
              appid=$(echo "$selection" | cut -f1)

              nohup flatpak run "$appid" >/dev/null 2>&1 & disown
              pkill -P $PPID
            }

            # Compile & run C
            crun() {
              [ -z "$1" ] && { echo "usage: crun file.c [args]"; return 2; }
              local src="$1"; shift
              local out="/tmp/$(basename ''${src%.*})"
              gcc -std=c11 -O0 -g -Wall -Wextra -Wpedantic "$src" -o "$out" && "$out" "$@"
            }

          # Makefile runner with debugging modes
          mrun() {
            if [ -z "$1" ]; then
              echo "usage: mrun [-g|-v] target [args]"
              return 2
            fi
            local mode="normal"
            if [ "$1" = "-g" ] || [ "$1" = "-v" ]; then
              mode="$1"; shift
            fi
            local target="$1"; shift
            make "$target" || return $?
            if [ -x "./$target" ]; then
              case "$mode" in
                -g) cgdb "./$target" --args "$@" ;;
                -v) valgrind "./$target" "$@" ;;
                *)  "./$target" "$@" ;;
              esac
            else
              echo "Built target '$target' (no matching executable)."
            fi
          }

          # Arch chroot helper
          boot() {
            sudo bash -c '
              cryptsetup luksOpen /dev/nvme0n1p2 root &&
              mount /dev/mapper/root /mnt &&
              mount /dev/nvme0n1p10 /mnt/boot &&
              arch-chroot /mnt
            '
          }

          # Search text and open file at selected line in nvim
          ff() {
            emulate -L zsh -o no_aliases
            local query="''${1:-.}"
            local result

            result=$(
              rg --line-number --no-heading --color=always "$query" \
                | fzf --ansi --delimiter ':' \
                      --height 80% --reverse --prompt='find> ' \
                      --preview 'bat --color=always --style=numbers --line-range=:500 {1} \
                        | rg --color=always --context=2 --ignore-case --pretty "'"$query"'" || true' \
                      --preview-window=right:70%:wrap
            ) || return

            local file=$(echo "$result" | cut -d':' -f1)
            local line=$(echo "$result" | cut -d':' -f2)

            if [[ -n "$file" ]]; then
              nvim "+$line" "$file"
            fi
          }








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

}
