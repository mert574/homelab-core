# cloudflared: the Cloudflare tunnel, locally-managed so all ingress lives here in
# code, not the dashboard. Routes Pulse (via the Cilium Gateway) and the
# user-facing media apps. Admin UIs (*arr, qBittorrent, digarr, etc.) stay LAN-only
# on purpose; put them behind Cloudflare Access if you ever need them remote.
{ config, pkgs, lib, ... }:
{
  imports = [ ../modules/base.nix ../modules/sops.nix ];

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
        # Both hostnames go to the Cilium Gateway LB; the k3s HTTPRoutes split by
        # host: app.pulsepager.com -> the Pulse app (SPA + /api), pulsepager.com ->
        # the docs-site. Media apps stay LAN-only (.internal), not exposed here.
        "app.pulsepager.com" = "http://192.168.178.200:80";
        "pulsepager.com" = "http://192.168.178.200:80";
      };
    };
  };
}
