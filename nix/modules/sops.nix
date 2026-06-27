{ ... }:
{
  # Secrets from the encrypted env, decrypted on the box via sops-nix using an age
  # key derived from the host's SSH key. After first boot, add the host's age key
  # (ssh-to-age) as a recipient in ../../.sops.yaml and re-encrypt.
  sops.defaultSopsFile = ../../secrets/homelab.enc.env;
  sops.defaultSopsFormat = "dotenv";
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
}
