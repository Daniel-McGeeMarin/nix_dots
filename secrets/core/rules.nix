# agenix recipients for the mcgeedan.com estate.
#
# Paths are relative to the repository root, because that is where you run
# `agenix`. The root secrets.nix merges this with secrets/graphide/rules.nix.
let
  xiaserver     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINWFmoYiRIbUToYku4tbARtl7W0OLx+lSt2cwV0iSaj1";
  xiaserverUser = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDbmhHJ1xWI+bq3WB9cdjuingSb/XJnSIvFcXZgPGHhU XiaServer@XiaServer";
  all = [ xiaserver xiaserverUser ];
in
{
  # TUNNEL_TOKEN=<token from the Cloudflare dashboard, mcgeedan account>
  "secrets/core/cloudflare-tunnel.age".publicKeys = all;

  # Three independent random signing keys for Authelia.
  "secrets/core/authelia-jwt.age".publicKeys     = all;
  "secrets/core/authelia-session.age".publicKeys = all;
  "secrets/core/authelia-storage.age".publicKeys = all;

  "secrets/core/homarr-env.age".publicKeys          = all;
  "secrets/core/ghost-public-env.age".publicKeys    = all;
  "secrets/core/ghost-private-env.age".publicKeys   = all;
  "secrets/core/ocis-admin-password.age".publicKeys = all;

  # Neither file exists yet, and system/serv/apps.nix stays inert until they do
  # (it guards on builtins.pathExists). These entries have to come first
  # regardless, since agenix takes its recipients from here and refuses to
  # create a file it has no rule for.
  "secrets/core/finance-import-token.age".publicKeys = all;
  "secrets/core/finance-ofx-env.age".publicKeys      = all;
}
