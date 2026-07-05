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
      # so any number of unrelated domains are served by Host match. cloudflared
      # points each hostname here.
      s3_web = {
        bind_addr = "[::]:3902";
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

  networking.firewall.allowedTCPPorts = [ 3900 3902 ]; # S3 + web

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
