{ config, lib, pkgs, ... }:
# Fully local, no-retention LLM tools for handling sensitive text: llmsum
# (summarize) and llmwash (rewrite into a generic/safe version). Everything
# stays on this machine — Ollama binds to 127.0.0.1 only, every call is
# stateless (no server-side session/history), and the wrapper scripts never
# write the prompt or response to disk; they go clipboard/stdin -> HTTP ->
# clipboard/stdout only.
#
# CPU, not GPU: this laptop's Meteor Lake NPU has no mature llama.cpp/Ollama
# backend, and pkgs.ollama-vulkan (Arc iGPU offload) was tested here and
# hangs indefinitely on every request on this hardware/driver combo — even
# with num_gpu:0 forcing CPU-only execution, so it's the Vulkan build itself
# at fault, not GPU offload specifically. Plain CPU pkgs.ollama was verified
# working: gemma3:4b answers a real prompt in ~15s cold / ~2.5s warm, which
# is fast enough for this tool's actual job (short-to-medium message
# rewriting), so there's no reason to chase the broken GPU path.
let
  cfg = config.ai.privatellm;
  model = "gemma3:4b";
  port = 11434;

  systemPromptSummarize = ''
    You summarize text concisely and neutrally. Preserve the key facts,
    decisions, and action items. Do not add commentary, opinions, or
    information that is not present in the text. Respond with ONLY the
    summary, no preamble.
  '';

  systemPromptWash = ''
    You rewrite text into a generic, safe version. Remove or generalize
    anything identifying or sensitive: names, companies, exact amounts,
    dates, locations, account/reference numbers, credentials, and other
    specifics. Preserve the core intent and any action being requested,
    phrased generically. Respond with ONLY the rewritten text, no preamble
    or explanation.
  '';

  mkTool = name: systemPrompt:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [ pkgs.curl pkgs.jq pkgs.wl-clipboard pkgs.libnotify ];
      text = ''
        if [ -t 0 ]; then
          input="$(wl-paste --no-newline 2>/dev/null || true)"
        else
          input="$(cat)"
        fi

        if [ -z "$input" ]; then
          notify-send "${name}" "Nothing to process (clipboard/stdin was empty)."
          exit 1
        fi

        payload="$(jq -n --arg model "${model}" --arg sys ${lib.escapeShellArg systemPrompt} --arg content "$input" \
          '{model: $model, stream: false, messages: [{role: "system", content: $sys}, {role: "user", content: $content}]}')"

        response="$(curl -s --max-time 90 "http://127.0.0.1:${toString port}/api/chat" -d "$payload")"
        result="$(printf '%s' "$response" | jq -r '.message.content // empty')"

        if [ -z "$result" ]; then
          notify-send "${name}" "No response - is the privatellm daemon running? (systemctl --user status ollama-privatellm)"
          exit 1
        fi

        printf '%s' "$result" | wl-copy
        notify-send "${name}" "Done, result copied to clipboard."
        printf '%s\n' "$result"

        unset input payload response result
      '';
    };
in
{
  options.ai.privatellm.enable = lib.mkEnableOption "Local-only, no-retention LLM tools (llmsum, llmwash) backed by Ollama";

  config = lib.mkIf cfg.enable {
    home.packages = [
      pkgs.ollama
      (mkTool "llmsum" systemPromptSummarize)
      (mkTool "llmwash" systemPromptWash)
    ];

    # Runs only on 127.0.0.1 (Ollama's default bind). Output is sent to
    # /dev/null rather than the journal so nothing Ollama itself logs about
    # a request can end up persisted on disk, regardless of Ollama's own
    # logging verbosity.
    systemd.user.services.ollama-privatellm = {
      Unit = {
        Description = "Local-only Ollama daemon for privatellm (llmsum/llmwash)";
        After = [ "graphical-session-pre.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.ollama}/bin/ollama serve";
        Environment = [ "OLLAMA_HOST=127.0.0.1:${toString port}" ];
        Restart = "on-failure";
        StandardOutput = "null";
        StandardError = "null";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
