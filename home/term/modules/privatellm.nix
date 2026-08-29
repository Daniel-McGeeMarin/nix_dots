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
