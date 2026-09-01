# agenix rules: which SSH keys may decrypt which .age file.
#
# This file holds no secret values. It exists so `agenix -e <path>` knows who to
# encrypt to, and it must list a path BEFORE that path can be created.
#
# The actual rules live next to the secrets they describe, one file per stack,
# so that secrets/graphide/ is self-contained and can move to another machine
# with system/graphide/. This file just merges them.
(import ./secrets/core/rules.nix) // (import ./secrets/graphide/rules.nix)
