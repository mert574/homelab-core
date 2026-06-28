# Postgres as a NixOS service, kept out of k3s. Apps reach it over the LAN.
# Tuned light for 512MB.
{ config, pkgs, lib, ... }:
{
  imports = [ ../modules/base.nix ../modules/sops.nix ];

  # role passwords, decrypted from the env to files postgres can read.
  sops.secrets."PULSE_DB_PASSWORD".owner = "postgres";
  sops.secrets."DIGARR_DB_PASSWORD".owner = "postgres";

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_18; # latest major; bump with the channel
    enableTCPIP = true;           # listen beyond the unix socket so k3s can reach it

    settings = {
      password_encryption = "scram-sha-256";
      shared_buffers = "128MB";
      work_mem = "8MB";
      max_connections = 50;
    };

    # peer auth locally, password auth from the home LAN only (k3s pods reach us
    # SNAT'd as the node IP, which is in this range)
    authentication = lib.mkForce ''
      local all all peer
      host  all all 192.168.178.0/24 scram-sha-256
    '';

    ensureDatabases = [ "pulse" "digarr" ];
    ensureUsers = [
      { name = "pulse"; ensureDBOwnership = true; }
      { name = "digarr"; ensureDBOwnership = true; }
    ];
  };

  networking.firewall.allowedTCPPorts = [ 5432 ];

  # ensureUsers can't set a password; set the pulse role's from the sops secret.
  systemd.services.postgres-set-password = {
    description = "set role passwords from the sops secrets";
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
    };
    script = ''
      psql=${config.services.postgresql.package}/bin/psql
      $psql -tAc "ALTER ROLE pulse WITH PASSWORD '$(cat ${config.sops.secrets."PULSE_DB_PASSWORD".path})';"
      $psql -tAc "ALTER ROLE digarr WITH PASSWORD '$(cat ${config.sops.secrets."DIGARR_DB_PASSWORD".path})';"
    '';
  };
}
