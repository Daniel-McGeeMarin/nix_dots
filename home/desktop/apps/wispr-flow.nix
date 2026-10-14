{ config, lib, pkgs, inputs, ... }:
# Wispr Flow -- voice dictation (github:wispr-flow-linux/wispr-flow-linux).
# Wispr ships only macOS and Windows builds; this unofficial port repackages
# the Windows installer's Electron app and adds a clean-room Rust helper that
# types the transcript into the focused window. Sign in with the normal Wispr
# account inside the app.
#
# The port's derivation never downloads the proprietary installer itself, so
# it is fetched here, from Wispr's own CDN, by the URL and SHA-256 in the
# port's scripts/setup/installer-pin.sh. Reading the pin out of the same input
# keeps the installer and the derivation's patches in step: bump with
#   nix flake update wispr-flow
# The linux sqlite addons are pinned below by hand (see nativeModules).
#
# Permissions it needs are already on for XiaNix, no extra system config:
#   /dev/uinput writable (text injection)  -- hardware.uinput.enable via head.gaming
#   /dev/input/event* readable (push-to-talk) -- xia is in the `input` group
#   wl-clipboard (paste on Wayland)        -- home/desktop/default.nix
# `wispr-flow --doctor` checks all of them.
let
  src = inputs.wispr-flow;
  system = pkgs.stdenv.hostPlatform.system;

  pin = builtins.readFile "${src}/scripts/setup/installer-pin.sh";
  pinned = name: builtins.head (builtins.match ".*\n${name}='([^']*)'.*" pin);

  installer = pkgs.fetchurl {
    name = "wispr-flow-setup-${pinned "WISPR_VERSION"}.exe";
    url = pinned "WISPR_INSTALLER_URL";
    sha256 = pinned "WISPR_INSTALLER_SHA256";
  };

  # The port's nix/wispr-flow.nix applies only the first two patches its own
  # scripts/build-linux.sh applies (helper-resolver, mac-gates), then runs
  # verify-patches.sh, which demands the markers of all of them, so the Nix
  # build fails as "half-patched". Run the rest here, in build-linux.sh's
  # order, before the asar is repacked. Drop this once upstream's derivation
  # applies them itself (the build then fails on a patch run twice).
  patch = script: target: ''bash ${src}/scripts/patches/${script} ${target}'';
  missingPatches = ''
    ${lib.concatMapStrings (p: patch p ''"$main_bundle"'' + "\n") [
      "helper-env.sh"
      "linux-window-frame.sh"
      "linux-hub-focusable.sh"
      "linux-deeplink.sh"
      "linux-early-singleton.sh"
      "linux-disable-pill-drag.sh"
      "linux-main-shortcut-defaults.sh"
      "linux-xdg-data-dir.sh"
      "linux-autostart.sh"
    ]}
    ${patch "linux-renderer-chrome.sh" "asar-contents/.webpack/renderer/hub/index.js"}
    for renderer in asar-contents/.webpack/renderer/*/index.js; do
      grep -qF 'platform?.isWindows' "$renderer" || continue
      ${patch "linux-renderer-treat-as-windows.sh" ''"$renderer"''}
    done
  '';
  anchor = "# Stage the unpacked native-module tree";

  # The port's derivation also keeps the installer's Windows sqlite addons
  # (its NATIVE-MODULE NOTE says DB features merely "stay broken"), but the
  # main process loads node_sqlite3 at startup, so the app dies before any
  # window with "invalid ELF header" and the launch looks like a hang. Its
  # repack also passes --unpack '**/*.node', which @electron/asar matches
  # against nothing, so every .node stays packed inside app.asar. Swap in the
  # prebuilt linux addons that build-linux.sh uses (github:wispr-flow-linux/
  # native-modules, built against the same V8 patch the input pins) and repack
  # with build-linux.sh's '*.node'. The hashes are that release's SHA256SUMS;
  # if a flake update moves the port to a new tag, the assert below fails
  # instead of shipping addons built for a different patch or ABI.
  nativeTag = "native-v1";
  nativeModule = name: hash: pkgs.fetchurl {
    url = "https://github.com/wispr-flow-linux/native-modules/releases/download/${nativeTag}/${name}-x86_64.node";
    sha256 = hash;
  };
  nativeModules = {
    better_sqlite3 = nativeModule "better_sqlite3" "a26c6fec70bb6d31c38609491b0391b8eadf3d9c2cc584d54f1601857e090e3f";
    node_sqlite3 = nativeModule "node_sqlite3" "c9bd0419f77efb3b5d3a691fda04e265f740ad8dc195f0b56003cdeac92e9a34";
  };
  repack = "asar pack asar-contents stage/app.asar --unpack '**/*.node'";
  nativeRel = ".webpack/main/native_modules/build/Release";
  linuxRepack = ''
    ${lib.concatStrings (lib.mapAttrsToList (mod: file: ''
      install -Dm644 ${file} asar-contents/${nativeRel}/${mod}.node
    '') nativeModules)}
    asar pack asar-contents stage/app.asar --unpack '*.node'
    ${lib.concatStrings (lib.mapAttrsToList (mod: file: ''
      install -Dm644 ${file} stage/app.asar.unpacked/${nativeRel}/${mod}.node
      [[ "$(head -c4 stage/app.asar.unpacked/${nativeRel}/${mod}.node | od -An -tx1 | tr -d ' \n')" == 7f454c46 ]] \
        || { echo "${mod}.node is not a linux ELF after repack" >&2; exit 1; }
    '') nativeModules)}
  '';

  wispr-flow = (src.packages.${system}.wispr-flow.override { installerExe = installer; }).overrideAttrs (old: {
    buildPhase =
      assert lib.assertMsg (lib.hasInfix anchor old.buildPhase)
        "wispr-flow.nix: the port's buildPhase changed; re-check the missing-patches splice";
      assert lib.assertMsg (lib.hasInfix repack old.buildPhase)
        "wispr-flow.nix: the port's asar repack line changed; re-check the native-module swap";
      assert lib.assertMsg (lib.trim (builtins.readFile "${src}/native-modules-version.txt") == nativeTag)
        "wispr-flow.nix: the port moved to new native modules; update nativeTag and the hashes from that release's SHA256SUMS";
      builtins.replaceStrings [ anchor repack ] [ (missingPatches + anchor) linuxRepack ] old.buildPhase;
  });

  # The glibc FHS wrapper is the port's recommended output on NixOS (Electron
  # wants /lib64/ld-linux). pkgs.unfree because it inherits the app's unfree meta.
  wispr-flow-fhs = pkgs.unfree.callPackage "${src}/nix/fhs.nix" { inherit wispr-flow; };
in
{
  home.packages = [ wispr-flow-fhs ];
}
