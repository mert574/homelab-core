# Vaultwarden: self-hosted, Bitwarden-compatible password manager (the Rust
# server, `services.vaultwarden` in nixpkgs). It's the least-disposable service
# here, so it lives in its own always-on LXC and stays out of k3s — a cluster
# rebuild never touches the vault. State (SQLite DB + attachments + RSA keys)
# lives under /var/lib/bitwarden_rs and survives nixos-rebuild.
#
# Public at https://pw.mert574.dev through the cloudflared tunnel (Cloudflare
# terminates TLS; the LAN leg is plain HTTP on :8000). Clients authenticate with
# Vaultwarden's own auth, so — unlike proxmox/ccflare — it is NOT behind
# Cloudflare Access: the Access login page breaks the Bitwarden mobile/browser
# API clients. Registration is closed; invite yourself from /admin (see DEPLOY.md).
{ config, pkgs, lib, ... }:
{
  imports = [ ../modules/base.nix ../modules/sops.nix ];
  networking.interfaces.eth0.ipv4.addresses = [{ address = "192.168.178.112"; prefixLength = 24; }];

  # ADMIN_TOKEN is a secret, so it must not go through services.vaultwarden.config
  # (that lands in the world-readable nix store). Keep the whole homelab env as one
  # root-only sops secret and pull ADMIN_TOKEN out into a clean EnvironmentFile
  # below — the garage.nix / postgres.nix pattern, since sops-nix can't extract a
  # single key from a dotenv file (it writes the entire decrypted file otherwise).
  sops.secrets."homelab-env" = { };  # -> /run/secrets/homelab-env, root:root 0400

  services.vaultwarden = {
    enable = true;
    dbBackend = "sqlite";                     # self-contained; one dir to back up
    environmentFile = "/run/vaultwarden/env"; # ADMIN_TOKEN, from vaultwarden-secrets below
    config = {
      DOMAIN = "https://pw.mert574.dev";
      # Listen on all interfaces so the cloudflared LXC (.103) can reach us over
      # the LAN. WebSocket notifications ride this same port (Vaultwarden serves
      # them inline), and the tunnel forwards ws upgrades, so there's no separate
      # port to open.
      ROCKET_ADDRESS = "0.0.0.0";
      ROCKET_PORT = 8000;
      # It's on the public internet: keep open registration off. Invite your own
      # email once from the /admin panel (DEPLOY.md); invited users can then
      # register even with this false. Flip to true only for a first-run account.
      SIGNUPS_ALLOWED = false;
      # Don't reveal whether an email has an account.
      SHOW_PASSWORD_HINT = false;
    };
  };

  networking.firewall.allowedTCPPorts = [ 8000 ];

  # Pull ADMIN_TOKEN out of the whole-env sops secret into a small root-only
  # EnvironmentFile, stripping the dotenv KEY="value" quotes. Ordered before
  # vaultwarden starts. Mirrors garage-secrets in garage.nix.
  systemd.services.vaultwarden-secrets = {
    description = "extract vaultwarden's ADMIN_TOKEN from the sops env into an EnvironmentFile";
    before = [ "vaultwarden.service" ];
    requiredBy = [ "vaultwarden.service" ];
    path = [ pkgs.coreutils pkgs.gnugrep ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    script = ''
      envfile=${config.sops.secrets."homelab-env".path}
      install -d -m 0755 /run/vaultwarden
      umask 077
      line="$(grep -m1 '^VAULTWARDEN_ADMIN_TOKEN=' "$envfile")" \
        || { echo "vaultwarden-secrets: VAULTWARDEN_ADMIN_TOKEN not found in env" >&2; exit 1; }
      val="''${line#VAULTWARDEN_ADMIN_TOKEN=}"
      val="''${val%\"}"; val="''${val#\"}"   # strip the dotenv KEY="value" quotes
      printf 'ADMIN_TOKEN=%s\n' "$val" > /run/vaultwarden/env.tmp
      chmod 0400 /run/vaultwarden/env.tmp
      mv /run/vaultwarden/env.tmp /run/vaultwarden/env
    '';
  };
}
