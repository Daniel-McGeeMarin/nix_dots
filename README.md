## NixOS System Config

This flake contains my personal NixOS + Home Manager configuration.

### Secrets

- This repo expects a local `secrets.nix` at the repo root.
- `secrets.nix` is **not** tracked in git (see `.gitignore`) and must be created by each user.
- It is used for mildly sensitive values such as:
  - Bluetooth MACs
  - Convenience quick‑paste strings (emails, URLs, low‑stakes passwords)
  - Account identifiers for some tools (e.g. feed reader accounts)

Example skeleton you can adapt:

```nix
{
  hypr = {
    bluetoothHeadsetMac = "00:11:22:33:44:55";
    workEmail          = "you@example.com";
    workPassword       = "change-me";
    workLinkedinUrl    = "https://www.linkedin.com/in/your-handle/";
  };

  feeds = {
    ocnewsUrl   = "https://your-cloud.example.com";
    ocnewsLogin = "your-login";
  };
}
```

Do **not** commit your real `secrets.nix` to any public repo.
