{ config, lib, pkgs, ... }:
# A real local chatbot, not just CLI commands: a llama.cpp server running
# gemma3:4b, opened as its own app via a private Firefox window pointed at
# the server's built-in chat UI. Everything stays on this machine.
#
# GPU: uses pkgs.unstable.llama-cpp (nixpkgs-unstable) with Vulkan enabled,
# offloading all layers to the Arc iGPU on this Meteor Lake chip. Getting
# here took real debugging -- three different backends were tried and two
# were broken on this exact machine:
#   - ollama-vulkan (stable nixpkgs): hangs indefinitely on every request,
#     even with num_gpu:0 forcing CPU-only execution. The Vulkan build
#     itself is at fault, not GPU offload as a concept.
#   - llama-cpp from stable nixpkgs (build 6981): loads and runs fast, but
#     any request that goes through the chat template (i.e. anything using
#     /v1/chat/completions, on CPU or GPU) comes back as garbage from the
#     first token -- raw non-chat completions were fine, so this is a
#     chat-template/special-token bug in that specific old build.
#   - llama-cpp from nixpkgs-unstable (build 10408, ~3400 commits newer):
#     works correctly on both counts. Verified end-to-end with real
#     sensitive sample text: coherent, correct answers, ~2.7s warm / ~11s
#     cold on a 4B model, fully GPU-offloaded (Vulkan0 in llama.cpp's own
#     device log).
#
# No retention: the server only holds conversation state in memory for the
# lifetime of a request (no --slot-save-path, so nothing is ever written to
# disk), and it binds to 127.0.0.1 only. The chat UI itself keeps its
# message list in the browser tab's local storage, which is why this is
# launched as a private-browsing window every time -- closing it discards
# that storage completely, same guarantee a normal browsing session
# wouldn't give you.
let
  cfg = config.ai.privatellm;
  port = 8090;

  model = pkgs.fetchurl {
    url = "https://huggingface.co/bartowski/google_gemma-3-4b-it-GGUF/resolve/main/google_gemma-3-4b-it-Q4_K_M.gguf";
    hash = "sha256-SZYDAkJYOkCqFR/5P0nteHrIwl5BIMOuRYiy4qfRrpQ=";
  };

  llamaCpp = pkgs.unstable.llama-cpp.override { vulkanSupport = true; };
in
{
  options.ai.privatellm.enable = lib.mkEnableOption "Local, no-retention chatbot (llama.cpp + gemma3, GPU-accelerated)";

  config = lib.mkIf cfg.enable {
    home.packages = [
      (pkgs.writeShellApplication {
        name = "privatellm-chat";
        text = ''
          exec ${config.programs.firefox.finalPackage}/bin/firefox --private-window "http://127.0.0.1:${toString port}"
        '';
      })

      # Paste a long conversation in (clipboard or stdin); it's split into
      # chunks and fed through the local server one at a time, maintaining
      # a running bulleted digest so nothing gets dropped even when the
      # whole thing wouldn't fit in one context window. Never touches
      # disk except the final digest, which goes to stdout + clipboard --
      # same "print/copy, don't persist" shape as everything else here.
      (pkgs.writeShellApplication {
        name = "privatellm-digest";
        runtimeInputs = [ pkgs.curl pkgs.jq pkgs.wl-clipboard pkgs.libnotify ];
        text = ''
          chunk_chars=4800  # ~1200 tokens; leaves headroom in the 16384-token
                             # context for the growing digest + response.

          system_prompt='You maintain a running bulleted digest of a long business
          conversation between cofounders. You are given the CURRENT DIGEST (may be
          empty) and the NEXT PORTION of the conversation. Merge in every new
          important business item: decisions, numbers, deadlines, action items,
          risks, commitments, strategy. Never drop an existing bullet unless this
          new portion clearly supersedes or corrects it, in which case update it in
          place. Keep every concrete fact exactly as stated -- names, amounts,
          dates, companies. Do NOT anonymize or generalize facts. Only clean up
          the phrasing: strip casual tone, filler, jokes, and swearing, and write
          each bullet as clean neutral prose. Ignore anything with no business
          substance. Respond with ONLY the complete updated digest as a bulleted
          list, nothing else.'

          if [ -t 0 ]; then
            input="$(wl-paste 2>/dev/null || true)"
          else
            input="$(cat)"
          fi

          if [ -z "$input" ]; then
            notify-send "privatellm-digest" "Nothing to process (clipboard/stdin was empty)."
            exit 1
          fi

          # Split into chunks on line boundaries, then hard-slice any single
          # line still over the limit so oddly-formatted pastes (no newlines)
          # can't produce one giant unsplit chunk.
          mapfile -t raw_lines <<< "$input"
          chunks=()
          current=""
          for line in "''${raw_lines[@]}"; do
            while [ "''${#line}" -gt "$chunk_chars" ]; do
              chunks+=("''${line:0:$chunk_chars}")
              line="''${line:$chunk_chars}"
            done
            candidate="$current"$'\n'"$line"
            if [ "''${#candidate}" -gt "$chunk_chars" ] && [ -n "$current" ]; then
              chunks+=("$current")
              current="$line"
            else
              current="$candidate"
            fi
          done
          [ -n "$current" ] && chunks+=("$current")

          total="''${#chunks[@]}"
          digest=""
          i=0
          for chunk in "''${chunks[@]}"; do
            i=$((i + 1))
            echo "[$i/$total] processing chunk..." >&2

            user_msg="CURRENT DIGEST:
          ''${digest:-(empty -- this is the first chunk)}

          NEW PORTION:
          $chunk

          Respond with ONLY the complete, updated digest as a bulleted list."

            payload="$(jq -n --arg sys "$system_prompt" --arg content "$user_msg" \
              '{model: "gemma3", messages: [{role: "system", content: $sys}, {role: "user", content: $content}], max_tokens: 4096, stream: false}')"

            response="$(curl -s --max-time 180 "http://127.0.0.1:${toString port}/v1/chat/completions" -d "$payload")"
            new_digest="$(printf '%s' "$response" | jq -r '.choices[0].message.content // empty')"
            finish_reason="$(printf '%s' "$response" | jq -r '.choices[0].finish_reason // empty')"

            if [ -z "$new_digest" ]; then
              echo "error: empty response on chunk $i/$total -- is privatellm-server running? (systemctl --user status privatellm-server)" >&2
              exit 1
            fi
            if [ "$finish_reason" = "length" ]; then
              echo "warning: chunk $i/$total's response hit the token limit and may be truncated" >&2
            fi

            digest="$new_digest"
          done

          printf '%s\n' "$digest"
          printf '%s' "$digest" | wl-copy
          notify-send "privatellm-digest" "Done -- digest copied to clipboard ($total chunks processed)."

          unset input raw_lines chunks current digest new_digest response payload user_msg
        '';
      })
    ];

    xdg.desktopEntries."privatellm-chat" = {
      name = "Private LLM Chat";
      comment = "Local, no-retention chatbot (nothing leaves this machine)";
      icon = "firefox";
      exec = "privatellm-chat";
      categories = [ "Network" "Chat" ];
      terminal = false;
    };

    systemd.user.services.privatellm-server = {
      Unit = {
        Description = "Local-only llama.cpp server for privatellm-chat";
        After = [ "graphical-session-pre.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${llamaCpp}/bin/llama-server -m ${model} -ngl 99 --ctx-size 16384 --host 127.0.0.1 --port ${toString port}";
        Restart = "on-failure";
        StandardOutput = "null";
        StandardError = "null";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
