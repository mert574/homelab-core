# Garage: S3-compatible object storage + static website serving in one box. Apps
# push build assets over S3; Garage serves them as websites. Shared infra used by
# things beyond the cluster, so it's a dedicated LXC, always on.
{ config, pkgs, lib, ... }:
{
  imports = [ ../modules/base.nix ../modules/sops.nix ];
  networking.interfaces.eth0.ipv4.addresses = [{ address = "192.168.178.109"; prefixLength = 24; }];

  # sops-nix can't extract individual keys from a dotenv file — it writes the
  # *entire* decrypted env to every secret path (see postgres.nix). So keep the
  # env as one root-only secret and pull garage's values out into an
  # EnvironmentFile below (garage reads GARAGE_RPC_SECRET / GARAGE_ADMIN_TOKEN
  # from the environment; the nix-cache and blog CI S3 keys feed garage-setup.sh).
  sops.secrets."homelab-env" = { };  # -> /run/secrets/homelab-env, root:root 0400

  services.garage = {
    enable = true;
    package = pkgs.garage;
    # GARAGE_RPC_SECRET / GARAGE_ADMIN_TOKEN come from here (extracted from the
    # sops env by garage-secrets.service below). systemd reads it as root, and
    # the `garage` CLI wrapper sources it too, so admin commands get the secret.
    environmentFile = "/run/garage/env";
    settings = {
      metadata_dir = "/var/lib/garage/meta";
      data_dir = "/var/lib/garage/data";
      db_engine = "lmdb";
      replication_factor = 1; # single node

      rpc_bind_addr = "[::]:3901";
      rpc_public_addr = "127.0.0.1:3901";

      # S3 API, for apps to push assets
      s3_api = {
        api_bind_addr = "[::]:3900";
        s3_region = "eu-central";
      };

      # Static website serving. Each site is its own bucket whose global alias is
      # the site's domain (bucket `app.pulsepager.com`, bucket `othersite.io`, ...),
      # so any number of unrelated domains are served by Host match.
      #
      # Garage binds loopback-only here: the Caddy below owns the public web port
      # (3902) and proxies to this, adding the SPA 404->index.html(200) fallback
      # for SPA hosts. cloudflared / the Cilium Gateway still target :3902 (Caddy).
      s3_web = {
        bind_addr = "127.0.0.1:3912";
        # garage requires root_domain whenever s3_web is set. Buckets are still
        # matched by their global alias (the full domain) regardless of this; it
        # just additionally enables <bucket>.web.garage.internal style hosting.
        root_domain = ".web.garage.internal";
        index = "index.html";
      };

      admin = {
        api_bind_addr = "127.0.0.1:3903";
        # token supplied via GARAGE_ADMIN_TOKEN in the EnvironmentFile above
      };
    };
  };

  # SPA fallback layer, in front of Garage's web port. A single-page app served
  # from a bucket needs every unknown path (client-side routes like /login) to
  # return index.html with 200 so the router can boot. Garage (v1.3.x) can serve
  # a website error-document, but only with the original 404 status -- there's no
  # way to make it 200. So Caddy owns the public web port (3902), Garage moved to
  # a loopback port (3912 above), and Caddy serves each SPA host with a
  # try_files-style 404 -> /index.html (200) fallback. Every other host
  # (nix-cache, the docs site, the blog) is passed straight through, so their
  # 404s stay real 404s -- important for the Nix substituter especially.
  #
  # Caddy (over nginx/HAProxy) because `handle_response @404` is a first-class way
  # to turn an upstream 404 into a 200 that refetches a different object, it keeps
  # the client Host by default (Garage matches the bucket by Host), and it streams
  # responses (nix-cache nars) without extra tuning.
  #
  # Adding a new SPA is one line: append its Host to `spaHosts`. Everything else
  # (bucket, alias, website flag, cloudflared route) is unchanged.
  services.caddy = let
    garageWeb = "127.0.0.1:3912";
    spaHosts = [ "app.pulsepager.com" ];
    # Per-SPA site: try the real object; on a 404, rewrite to /index.html and
    # refetch -- Garage returns it with 200, so the SPA router boots. Host is
    # preserved (Caddy's default) so Garage still selects the bucket by Host.
    spaVhost = host: lib.nameValuePair "http://${host}:3902" {
      extraConfig = ''
        reverse_proxy ${garageWeb} {
          @notfound status 404
          handle_response @notfound {
            rewrite * /index.html
            reverse_proxy ${garageWeb}
          }
        }
      '';
    };
  in {
    enable = true;
    globalConfig = "auto_https off"; # plain HTTP on :3902; TLS is Cloudflare's job
    # NB: the `http://` scheme on every site address is required, not cosmetic --
    # a schemeless `host:3902` is still treated as HTTPS even with auto_https off,
    # and Caddy then 400s plain HTTP with "sent an HTTP request to an HTTPS server".
    virtualHosts = {
      # Catch-all: every non-SPA host streams straight to Garage, 404s stay real.
      "http://:3902".extraConfig = "reverse_proxy ${garageWeb}";
    } // lib.listToAttrs (map spaVhost spaHosts);
  };

  networking.firewall.allowedTCPPorts = [ 3900 3902 ]; # S3 + web (Caddy fronts 3902)

  # Pull garage's four values out of the whole-env sops secret into a small
  # root-only EnvironmentFile, stripping the dotenv KEY="value" quotes so both
  # systemd and the `garage` CLI get clean values. Runs before garage starts.
  systemd.services.garage-secrets = {
    description = "extract garage's secrets from the sops env into an EnvironmentFile";
    before = [ "garage.service" "garage-setup.service" ];
    requiredBy = [ "garage.service" "garage-setup.service" ];
    path = [ pkgs.coreutils ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    script = ''
      envfile=${config.sops.secrets."homelab-env".path}
      install -d -m 0755 /run/garage
      umask 077
      : > /run/garage/env.tmp
      while IFS= read -r line; do
        case "$line" in
          GARAGE_RPC_SECRET=*|GARAGE_ADMIN_TOKEN=*|NIX_CACHE_S3_ACCESS_KEY=*|NIX_CACHE_S3_SECRET_KEY=*|BLOG_S3_ACCESS_KEY=*|BLOG_S3_SECRET_KEY=*)
            key=''${line%%=*}; val=''${line#*=}
            val=''${val%\"}; val=''${val#\"}   # strip the dotenv KEY="value" quotes
            printf '%s=%s\n' "$key" "$val" >> /run/garage/env.tmp ;;
        esac
      done < "$envfile"
      chmod 0400 /run/garage/env.tmp
      mv /run/garage/env.tmp /run/garage/env
    '';
  };

  # Set up Garage in code instead of by hand: layout + the nix-cache bucket + the
  # CI write key, via scripts/garage-setup.sh (idempotent, re-runs safely on every
  # boot). Secrets come from the EnvironmentFile (garage-secrets.service).
  systemd.services.garage-setup = {
    description = "Set up Garage layout, buckets and keys";
    after = [ "garage.service" "garage-secrets.service" ];
    requires = [ "garage.service" "garage-secrets.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.garage pkgs.gnugrep pkgs.gawk pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      EnvironmentFile = "/run/garage/env";
      ExecStart = "${pkgs.bash}/bin/bash ${../../scripts/garage-setup.sh}";
    };
  };
}
