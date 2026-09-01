# agenix recipients for the Graphide stack.
#
# Paths are relative to the repository root, because that is where you run
# `agenix`. The root secrets.nix merges this with secrets/core/rules.nix, so
# `agenix -e secrets/graphide/api-env.age` works from the top of the repo as
# usual.
#
# Recipients are spelled out here rather than imported from a shared file on
# purpose: this directory is meant to be liftable onto its own machine along
# with system/graphide, and an import one level up would break that. The cost is
# that a host key rotation edits two rules files instead of one. They are public
# keys, so there is nothing to leak by repeating them.
let
  xiaserver     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINWFmoYiRIbUToYku4tbARtl7W0OLx+lSt2cwV0iSaj1";
  xiaserverUser = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDbmhHJ1xWI+bq3WB9cdjuingSb/XJnSIvFcXZgPGHhU XiaServer@XiaServer";
  all = [ xiaserver xiaserverUser ];
in
{
  # TUNNEL_TOKEN=<token from the Cloudflare dashboard, graphide account>
  "secrets/graphide/tunnel.age".publicKeys = all;

  # Postgres credentials, DATABASE_URL, REDIS_URL, SUPABASE_URL, ANTHROPIC_API_KEY.
  # Read by graphide-postgres and graphide-api. See system/graphide/api.nix.
  "secrets/graphide/api-env.age".publicKeys = all;

  # The model provider key handed to every demo pod. Any guest can read this
  # from a pod terminal, so it must be a dedicated key with a low spend cap and
  # never the production one. See system/graphide/demo.nix.
  "secrets/graphide/demo-env.age".publicKeys = all;

  # Fine-grained GitHub PAT, read-only, scoped to monolith + gred + website.
  # Used by both autobuild units to clone the private repos.
  "secrets/graphide/clone-token.age".publicKeys = all;

  # Classic GitHub PAT with read:packages, for `podman login ghcr.io`.
  # See system/graphide/registry.nix.
  "secrets/graphide/ghcr-token.age".publicKeys = all;

  # DATABASE_URL (Supabase, not the local cluster), DISCORD_WEBHOOK_URL,
  # DEMO_BOXES, DEMO_BASE_PORT, DEMO_IDLE_GRACE, ADMIN_GROUP.
  # Contents documented in system/graphide/web.nix.
  #
  # NOT YET CREATED. This entry has to exist before the file can be, since
  # agenix takes its recipients from here and refuses a path it has no rule for.
  "secrets/graphide/web-env.age".publicKeys = all;

  # HMAC key for demo magic links. One line: DEMO_GATE_KEY=<64 hex chars>.
  # See system/graphide/gate.nix. Without this file the boxes 401.
  "secrets/graphide/gate-key.age".publicKeys = all;
}
