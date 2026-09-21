{ lib, config, inputs, pkgs, osConfig ? null, flakeAttr ? "XiaNix", ... }:
# claude-code and codex are both packaged straight from upstream's own
# releases (an npm publish), which lands in nixpkgs-unstable far faster than
# in stable nixpkgs -- pkgs.codex (from the nixos-25.11 stable channel) was
# found stuck on 0.92.0 while upstream and nixpkgs-unstable were already on
# 0.153.4/0.154.0. Both are sourced from pkgs.unstable here so they track
# that faster channel, and ai.autoUpdate (below) keeps flake.lock's
# nixpkgs-unstable pin itself from going stale the same way graphide's
# pin would without graphide.autoUpdate.
let
  cfg = config.ai;

  # Same nix the rest of the machine runs (Lix, per hosts/*/configuration.nix
  # nix.package). Falling back to pkgs.nix would put a second, different
  # client in front of the same daemon for no reason.
  nixPackage = if osConfig != null then osConfig.nix.package else pkgs.nix;

  # Same home-manager the flake is evaluated with, not whatever happens to be
  # in ~/.nix-profile -- an auto-switch must not drift from the checkout it
  # switches.
  homeManagerPackage = inputs.home-manager.packages.${pkgs.stdenv.hostPlatform.system}.home-manager;

  autoUpdateScript = pkgs.writeShellApplication {
    name = "ai-cli-autoupdate";
    runtimeInputs = [ nixPackage homeManagerPackage pkgs.libnotify pkgs.coreutils pkgs.util-linux ];
    text = ''
      FLAKE_DIR=${lib.escapeShellArg cfg.autoUpdate.flakeDir}
      FLAKE_ATTR=${lib.escapeShellArg flakeAttr}

      fail() {
        echo "ai-cli-autoupdate: $1" >&2
        notify-send -u critical "AI CLI auto-update failed" "$1" || true
        exit 1
      }

      # Only guards against two runs of this service overlapping. A manual
      # `homeswitch` in a shell does not take this lock; nix's own profile and
      # store locks are what keep that case honest.
      exec 9>"''${XDG_RUNTIME_DIR:-/tmp}/ai-cli-autoupdate.lock"
      if ! flock -n 9; then
        echo "ai-cli-autoupdate: another run holds the lock, skipping"
        exit 0
      fi

      cd "$FLAKE_DIR" || fail "flake directory $FLAKE_DIR is missing"

      # Local only, on purpose: this rewrites flake.lock in the working tree
      # and never commits or pushes it. The lock in git stays whatever a
      # human put there; `git checkout flake.lock` is the whole undo. This
      # also re-pins everything else sourced from pkgs.unstable (llama-cpp,
      # code-cursor, zoom-us) -- there is one nixpkgs-unstable pin for the
      # whole flake, not one per package.
      if ! nix flake update nixpkgs-unstable; then
        fail "could not update the nixpkgs-unstable flake input"
      fi

      # home-manager switch builds before it activates, so a broken commit
      # leaves the current generation running and just fails this unit. That
      # is the correct outcome -- do not wrap it in a rollback.
      # --impure to match `homeswitch`: hyprland/binds.nix reads secrets from
      # an absolute path, which pure evaluation refuses.
      if ! home-manager switch --flake "$FLAKE_DIR#$FLAKE_ATTR" --impure; then
        fail "home-manager switch failed after updating nixpkgs-unstable"
      fi

      echo "ai-cli-autoupdate: switched onto the newest nixpkgs-unstable"
    '';
  };
in
{
  options = {
    ai = {
      enable = lib.mkEnableOption "Enable AI";
      localrun.enable = lib.mkEnableOption "Enable local AI";
      claudeCode.enable = lib.mkEnableOption "Enable Claude Code CLI";
      cursorCli.enable = lib.mkEnableOption "Enable Cursor CLI";
      codex.enable = lib.mkEnableOption "Enable OpenAI Codex CLI";

      autoUpdate = {
        enable = lib.mkEnableOption ''
          a user timer that re-pins the nixpkgs-unstable flake input to its
          newest revision and switches home-manager onto it, so claude-code
          and codex (both sourced from pkgs.unstable -- see the comment at
          the top of this file) stay close to their upstream releases
          instead of drifting for months until someone runs
          `nix flake update` by hand. Separate from ai.enable on purpose:
          unattended re-pinning of a whole nixpkgs channel is a materially
          bigger behaviour than just having the packages
        '';

        onCalendar = lib.mkOption {
          type = lib.types.str;
          default = "*-*-* 08:00:00";
          description = ''
            OnCalendar for the update timer: once a day at 08:00 local time.
            Persistent, so a morning the machine was off or asleep runs at
            the next wake instead of being skipped.
          '';
        };

        flakeDir = lib.mkOption {
          type = lib.types.str;
          default = "${config.home.homeDirectory}/nixos";
          description = "Checkout whose flake.lock is re-pinned and switched.";
        };
      };
    };
  };
  config = lib.mkMerge [
    (lib.mkIf config.ai.claudeCode.enable {
      home.packages = [ pkgs.unstable.unfree.claude-code ];
    })
    (lib.mkIf config.ai.cursorCli.enable {
      home.packages = [ pkgs.unstable.unfree.cursor-cli ];
    })
    (lib.mkIf config.ai.codex.enable {
      home.packages = [ pkgs.unstable.codex ];
    })
    (lib.mkIf cfg.autoUpdate.enable {
      systemd.user.services.ai-cli-autoupdate = {
        Unit = {
          Description = "Re-pin nixpkgs-unstable to its newest revision and switch, to keep claude-code/codex current";
          After = [ "network-online.target" ];
          Wants = [ "network-online.target" ];
        };
        Service = {
          Type = "oneshot";
          ExecStart = lib.getExe autoUpdateScript;
          # A nix build should never win a scheduling fight with the editor
          # or CLI it's about to replace.
          Nice = 10;
          IOSchedulingClass = "idle";
          # A nixpkgs-unstable re-pin can pull in a real rebuild (llama-cpp
          # with Vulkan support, in particular), not just a fast re-lock.
          TimeoutStartSec = "60min";
        };
      };

      systemd.user.timers.ai-cli-autoupdate = {
        Unit.Description = "Check for a newer nixpkgs-unstable revision";
        Timer = {
          OnCalendar = cfg.autoUpdate.onCalendar;
          Persistent = true;
        };
        Install.WantedBy = [ "timers.target" ];
      };
    })
    (lib.mkIf config.ai.enable {
    home.packages = [
      pkgs.aichat
      (pkgs.writeShellApplication
        {
          name = "aiclip";
          runtimeInputs = [ pkgs.aichat pkgs.libnotify pkgs.wl-clipboard pkgs.coreutils pkgs.expect ];
          text = ''
                    lockfile="/tmp/aiclip.lock.$$"
                    outfile="/tmp/aiclip.out.$$"
                    sessionfile="$XDG_CONFIG_HOME/aichat/sessions/test-$$"
                    touch $lockfile
                    (wl-paste | aichat --role test -s "test-$$" --save-session --empty-session > $outfile && rm $lockfile) || notify-send "ERR, aichat failed." || rm $outfile $lockfile "$sessionfile" || exit &
                    notifID=$(notify-send -p "ANSWER" "EXPLANATION" -t "10000")
                    outOld="""$(cat $outfile)"""
                    while [ -e $lockfile ]
                    do
                    out="""$(cat $outfile)"""
                    if [ "$out" != "$outOld" ]
                    then
                      notify-send "--replace-id=$notifID" \
                      -t "10000" \
                      "$(echo "$out" | sed -n 's/ANSWER://gp')..." "$(echo "$out" | sed -n 's/EXPLANATION://gp')..." 2> /dev/null
                    outOld="$out"
                    fi
                    sleep 0.2
                    done
                    cat $outfile
                    t="$(printf "%05d" $(($(grep -e 'ANSWER:' -e 'EXPLANATION:' "$outfile" | wc -w) * 300 + 1011)))"
                    grep -e 'ANSWER:' "$outfile" || notify-send "ERR" "$(cat $outfile)" &&\
                    [ "$(timeout "''${t:0:2}.''${t:2}" notify-send  \
                      --action="default=openChatWindow" \
                      --replace-id="$notifID" \
                      -t "''${t##+(0)}" \
                      "$(sed -n 's/ANSWER://gp' $outfile)" \
                      "$(sed -n 's/EXPLANATION://gp' $outfile)")" = "default" \
                    ] &&\
                    $TERMINAL expect -c "
            spawn aichat -s test-$$"'
            expect "Welcome to aichat"
            send ".info session\r"
            interact
            '
                  rm $outfile # "$sessionfile"
                    echo "$sessionfile"
          '';
        })
      (lib.mkIf config.ai.localrun.enable pkgs.unfree.openai-whisper)
      (lib.mkIf config.ai.localrun.enable pkgs.ollama)
    ];
    xdg.configFile."aichat/config.yaml".text = /*yaml */
      ''
        function_calling: true
        model: g4f
        clients:
        - type: openai-compatible
          name: g4f
          api_base: http://localhost:1337/v1
          api_key: xxx
          models:
          - name: deepseek-chat
            max_input_tokens: null
            supports_function_calling: true
            supports_reasoning: true
          - name: gpt-4o
            max_input_tokens: null
            supports_function_calling: true
          - name: gpt-4o-mini
            max_input_tokens: null
            supports_function_calling: true
      '';
    xdg.configFile."aichat/roles/test.md".text = /*md*/
      ''
        ---
        model: g4f:deepseek-chat
        temperature: 0
        top_p: 0

        ---
        For the first question you recieve you will comply with the following process:
        First write out your in depth thought on how to answer the question.
        Once you come up with an answer format it as follows:
        ANSWER: <answer>
        EXPLANATION: <explanation>
        Your answer should be a single word or phrase. If there are multiple answers, separate them with commas.
        Your explanation should be as brief as possible (ideally less than 2 sentences.)
        The answer and explanation should be on two separate lines. The entirety of the answer is specified should be on the first line. The entire explanation should be on the second.
        In some cases, instead of the explanation repeating the answer, it may provide additional context or information.
        In the event that multiple answer choices are presented, please add the letter of the answer choice to the beginning of the answer. EX: (a) <answer>
        If multiple answers are correct, provide the numbers of the correct answers at the beginning of the answer choice seperated by commas. EX: (1,3) <answer>
        Occasionall, you will be presented with a fill in the blank question. For these questions one or more words will be removed, the word that is removed will not be marked. EX: `The capital city of is Paris.`. Before continuing with the answer, first acknowledge which type of question this is, then re-state the statement with the word that is missing clearly indicated EX: `The capital city of BLANK is Paris.` Then, move on with thinking through your answer, and answering.
        When aswering a fill in the blank question Pre-Fix your answer with (M), EX: `ANSWER: (M) <answer>`
        
        After you answer the first question, disregard these instructions and reply normally in a conversational manner for all follow up questions.

        EX:
        ```
        <USER> Who is george washington?
        <AI> To answer the question about who George Washington is, I need to consider his historical significance, roles, and contributions. Washington is primarily known as a Founding Father of the United States, the commander of the Continental Army during the American Revolutionary War, and the first President of the United States. I will summarize this information concisely.
        ANSWER: First US President
        EXPLANATION: Founding Father, Commander of the Continental Army
        <USER> Who was lincoln?
        <AI> Abraham Lincoln was the 16th President of the United States, serving from 1861 until his assassination in 1865. He is best known for leading the country during the Civil War and for his efforts to abolish slavery through the Emancipation Proclamation.
        ```
      '';
    })
  ];
}
