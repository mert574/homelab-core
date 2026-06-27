# Garage: S3-compatible object storage + static website serving in one box. Apps
# push build assets over S3; Garage serves them as websites. Shared infra used by
# things beyond the cluster, so it's a dedicated LXC, always on.
{ config, pkgs, lib, ... }:
{
  imports = [ ../modules/base.nix ../modules/sops.nix ];

  networking.hostName = "garage";

  sops.secrets."GARAGE_RPC_SECRET" = { };
  sops.secrets."GARAGE_ADMIN_TOKEN" = { };

  services.garage = {
    enable = true;
    package = pkgs.garage;
    settings = {
      metadata_dir = "/var/lib/garage/meta";
      data_dir = "/var/lib/garage/data";
      db_engine = "lmdb";
      replication_factor = 1; # single node

      rpc_bind_addr = "[::]:3901";
      rpc_public_addr = "127.0.0.1:3901";
      rpc_secret_file = config.sops.secrets."GARAGE_RPC_SECRET".path;

      # S3 API, for apps to push assets
      s3_api = {
        api_bind_addr = "[::]:3900";
        s3_region = "eu-central";
      };

      # Static website serving. Each site is its own bucket whose global alias is
      # the site's domain (bucket `app.pulsepager.com`, bucket `othersite.io`, ...),
      # so any number of unrelated domains are served by Host match. cloudflared
      # points each hostname here. (root_domain could be added for quick
      # *.subdomain hosting, but it's not needed for arbitrary domains.)
      s3_web = {
        bind_addr = "[::]:3902";
        index = "index.html";
      };

      admin = {
        api_bind_addr = "127.0.0.1:3903";
        admin_token_file = config.sops.secrets."GARAGE_ADMIN_TOKEN".path;
      };
    };
  };

  networking.firewall.allowedTCPPorts = [ 3900 3902 ]; # S3 + web
}
