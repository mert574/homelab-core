# cloudflared: the Cloudflare tunnel, locally-managed so all ingress lives here in
# code, not the dashboard. One tunnel serves every public hostname across both
# zones (pulsepager.com and mert574.dev): Pulse via the Cilium Gateway, plus the
# mert574.dev services below. Admin UIs (*arr, qBittorrent, digarr, etc.) stay
# LAN-only on purpose; the admin surfaces we do expose (Proxmox, ccflare) sit
# behind Cloudflare Access — see DEPLOY.md. Add a DNS route per hostname with
# `cloudflared tunnel route dns homelab <hostname>` (or the dashboard).
{ config, pkgs, lib, ... }:
{
  imports = [ ../modules/base.nix ../modules/sops.nix ];
  networking.interfaces.eth0.ipv4.addresses = [{ address = "192.168.178.103"; prefixLength = 24; }];

  # Tunnel credentials JSON from `cloudflared tunnel create` (see DEPLOY.md).
  sops.secrets."cloudflared-creds" = {
    format = "binary";
    sopsFile = ../../secrets/cloudflared.creds.enc;
  };

  services.cloudflared = {
    enable = true;
    # attr name = the tunnel UUID from `cloudflared tunnel create`
    tunnels."c281773f-0119-43ca-b5fb-b09d39230c42" = {
      credentialsFile = config.sops.secrets."cloudflared-creds".path;
      default = "http_status:404";
      ingress = {
        # --- pulsepager.com: both hostnames go to the Cilium Gateway LB; the k3s
        # HTTPRoutes split by host: app.pulsepager.com -> the Pulse app (SPA +
        # /api), pulsepager.com -> the docs-site.
        "app.pulsepager.com" = "http://192.168.178.200:80";
        "pulsepager.com" = "http://192.168.178.200:80";

        # --- mert574.dev: public, app-level auth only.
        "media.mert574.dev" = "http://192.168.178.110:8096";    # Jellyfin
        "requests.mert574.dev" = "http://192.168.178.110:5055"; # Jellyseerr
        "garage.mert574.dev" = "http://192.168.178.109:3900";   # Garage S3 API
        # Vaultwarden: its own auth guards it (do NOT add Cloudflare Access here —
        # the Access login page breaks the Bitwarden clients). ws rides the same port.
        "pw.mert574.dev" = "http://192.168.178.112:8000";       # Vaultwarden

        # --- mert574.dev admin surfaces: keep these behind Cloudflare Access
        # (email/SSO gate at the edge), since they'd otherwise be open to the
        # internet. Proxmox serves HTTPS with a self-signed cert, so skip origin
        # TLS verification (the tunnel is the encrypted hop; the LAN leg is trusted).
        "proxmox.mert574.dev" = {
          service = "https://192.168.178.100:8006";
          originRequest.noTLSVerify = true;
        };
        "ccflare.mert574.dev" = "http://192.168.178.111:8080";
      };
    };
  };
}
