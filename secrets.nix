let
  xiaserver     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINWFmoYiRIbUToYku4tbARtl7W0OLx+lSt2cwV0iSaj1";
  xiaserverUser = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDbmhHJ1xWI+bq3WB9cdjuingSb/XJnSIvFcXZgPGHhU XiaServer@XiaServer";
in {
  "secrets/cloudflare-tunnel.age".publicKeys    = [ xiaserver xiaserverUser ];
  "secrets/authelia-jwt.age".publicKeys        = [ xiaserver xiaserverUser ];
  "secrets/authelia-session.age".publicKeys    = [ xiaserver xiaserverUser ];
  "secrets/authelia-storage.age".publicKeys    = [ xiaserver xiaserverUser ];
  "secrets/homarr-env.age".publicKeys           = [ xiaserver xiaserverUser ];
  "secrets/ghost-public-env.age".publicKeys     = [ xiaserver xiaserverUser ];
  "secrets/ghost-private-env.age".publicKeys    = [ xiaserver xiaserverUser ];
  "secrets/ocis-admin-password.age".publicKeys  = [ xiaserver xiaserverUser ];
  "secrets/graphide-api-env.age".publicKeys     = [ xiaserver xiaserverUser ];
  "secrets/ghcr-token.age".publicKeys           = [ xiaserver xiaserverUser ];
}
