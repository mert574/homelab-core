# cloudflared: the Cloudflare tunnel, locally-managed so all ingress lives here in
# code, not the dashboard. Routes Pulse (via the Cilium Gateway) and the
# user-facing media apps. Admin UIs (*arr, qBittorrent, digarr, etc.) stay LAN-only
# on purpose; put them behind Cloudflare Access if you ever need them remote.
{ config, pkgs, lib, ... }:
{
  imports = [ ../modules/base.nix ../modules/sops.nix ];

  networking.hostName = "cloudflared";

  # Tunnel credentials JSON from `cloudflared tunnel create` (see DEPLOY.md).
  sops.secrets."cloudflared-creds" = {
    format = "binary";
    sopsFile = ../../secrets/cloudflared.creds.enc;
  };

  services.cloudflared = {
    enable = true;
    # attr name = the tunnel UUID from `cloudflared tunnel create`
    tunnels."REPLACE-tunnel-uuid" = {
      credentialsFile = config.sops.secrets."cloudflared-creds".path;
      default = "http_status:404";
      ingress = {
        # Pulse SPA + API via the Cilium Gateway LB IP (from the .200-.220 pool)
        "app.pulsepager.com" = "http://192.168.178.200:80"; # the pinned Gateway LB IP
        # user-facing media apps only (they have their own auth). Pick hostnames.
        "watch.example.com" = "http://192.168.178.110:8096"; # jellyfin
        "requests.example.com" = "http://192.168.178.110:5055"; # jellyseerr
      };
    };
  };
}
