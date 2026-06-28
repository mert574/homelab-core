{ ... }:
{
  # Secrets from the encrypted env, decrypted on each box via sops-nix with the
  # single master age key the bootstrap installs at the path below. One key for
  # every host, so there are no per-host recipients to manage.
  sops.defaultSopsFile = ../../secrets/homelab.enc.env;
  sops.defaultSopsFormat = "dotenv";
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";
}
