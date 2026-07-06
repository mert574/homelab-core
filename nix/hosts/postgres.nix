# Postgres as a NixOS service, kept out of k3s. Apps reach it over the LAN.
# Tuned light for 512MB.
{ config, pkgs, lib, ... }:
{
  imports = [ ../modules/base.nix ../modules/sops.nix ];
  networking.interfaces.eth0.ipv4.addresses = [{ address = "192.168.178.102"; prefixLength = 24; }];

  # The homelab secrets live in one dotenv file. sops-nix only extracts single
  # keys from yaml/json — for dotenv (and binary/ini) it writes the *entire*
  # decrypted file to the secret path, ignoring the key (see decryptSecret in
  # sops-install-secrets). So a per-key `sops.secrets."PULSE_DB_PASSWORD"` would
  # hand postgres the whole env (pve root password, ssh keys, every app secret).
  # Instead keep the file root-only and pull the two role passwords out below.
  sops.secrets."homelab-env" = { };  # -> /run/secrets/homelab-env, root:root 0400

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

    ensureDatabases = [ "pulse" "activepieces" ];
    ensureUsers = [
      { name = "pulse"; ensureDBOwnership = true; }
      { name = "activepieces"; ensureDBOwnership = true; }
    ];
  };

  networking.firewall.allowedTCPPorts = [ 5432 ];

  # ensureUsers can't set a password; set the pulse role password from
  # the sops env. Runs as root (to read the root-only secret) and shells out to
  # psql via runuser so local peer auth still sees the postgres user. The value
  # is passed as a psql variable and interpolated with :'pw', which quotes and
  # escapes it safely — so a password with quotes/backslashes can't break out of
  # the statement (the old '$(cat …)' form did, hence the boot failure).
  # Must also wait on postgresql-setup.service (the unit NixOS uses to actually
  # apply ensureUsers/ensureDatabases), not just postgresql.service being up --
  # otherwise this can race setup and ALTER a role that doesn't exist yet on a
  # fresh boot (seen on the first activepieces deploy: postgresql.service was
  # "active" but the activepieces role hadn't been created yet).
  systemd.services.postgres-set-password = {
    description = "set role passwords from the sops secrets";
    after = [ "postgresql.service" "postgresql-setup.service" ];
    requires = [ "postgresql.service" "postgresql-setup.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      envfile=${config.sops.secrets."homelab-env".path}
      psql=${config.services.postgresql.package}/bin/psql
      runuser=${pkgs.util-linux}/bin/runuser

      set_pw() {
        local role="$1" var="$2" line val
        line="$(${pkgs.gnugrep}/bin/grep -m1 "^$var=" "$envfile")" \
          || { echo "postgres-set-password: $var not found in env" >&2; exit 1; }
        val="''${line#$var=}"
        val="''${val%\"}"; val="''${val#\"}"   # strip the dotenv KEY="value" quotes
        printf "ALTER ROLE %s WITH PASSWORD :'pw';\n" "$role" \
          | "$runuser" -u postgres -- "$psql" -v pw="$val" -f -
      }
      set_pw pulse PULSE_DB_PASSWORD
      set_pw activepieces ACTIVEPIECES_DB_PASSWORD
    '';
  };
}
