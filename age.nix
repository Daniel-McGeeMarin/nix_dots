let
  xiaserver = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINWFmoYiRIbUToYku4tbARtl7W0OLx+lSt2cwV0iSaj1";
in {
  "secrets/cloudflare-tunnel.age".publicKeys    = [ xiaserver ];
  "secrets/authelia-jwt.age".publicKeys         = [ xiaserver ];
  "secrets/authelia-session.age".publicKeys     = [ xiaserver ];
  "secrets/authelia-storage.age".publicKeys     = [ xiaserver ];
  "secrets/ghost-public-env.age".publicKeys     = [ xiaserver ];
  "secrets/ghost-private-env.age".publicKeys    = [ xiaserver ];
}
