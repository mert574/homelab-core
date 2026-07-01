# ccflare: a multi-account proxy in front of Anthropic/OpenAI. It load-balances
# requests across several Claude (and OpenAI) accounts and records request history
# + analytics, exposing a dashboard and the proxy on :8080. Point a client at
# http://ccflare.internal:8080 and it fans out over the accounts you add.
#
# ccflare is a Bun monorepo, not packaged in nixpkgs and with no release artifact,
# so we fetch + build it at a pinned commit in a oneshot (mirrors the garage-setup
# pattern in garage.nix) and run `bun run start` as a long-lived service. The DB +
# config are SQLite/JSON under /var/lib/ccflare, so a rebuild never loses accounts.
{ config, pkgs, lib, ... }:
let
  # Pin ccflare to a known-good commit; bump this to update. A rebuild re-fetches
  # and rebuilds only when the ref (or the built dashboard) changed.
  ccflareRef = "95c4c6a12d11598386333972e04cf1567c5a1298";
  stateDir = "/var/lib/ccflare";
  srcDir = "${stateDir}/src";
in
{
  imports = [ ../modules/base.nix ];
  networking.interfaces.eth0.ipv4.addresses = [{ address = "192.168.178.111"; prefixLength = 24; }];

  # bun is the runtime + package manager; git fetches the source.
  environment.systemPackages = with pkgs; [ bun git ];

  # Dedicated service account; its home is the state dir (bun's cache lives there).
  users.users.ccflare = {
    isSystemUser = true;
    group = "ccflare";
    home = stateDir;
  };
  users.groups.ccflare = { };

  # Fetch + build ccflare at the pinned ref. Oneshot, ordered before the server,
  # idempotent (re-runs safely on every boot; a no-op once built at that ref).
  systemd.services.ccflare-setup = {
    description = "Fetch and build ccflare at the pinned ref";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    before = [ "ccflare.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.bun pkgs.git pkgs.cacert pkgs.coreutils ];
    environment = {
      HOME = stateDir;
      CCFLARE_REF = ccflareRef;
      GIT_SSL_CAINFO = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "ccflare";
      Group = "ccflare";
      StateDirectory = "ccflare";
      WorkingDirectory = stateDir;
      ExecStart = "${pkgs.bash}/bin/bash ${../../scripts/ccflare-setup.sh}";
      # First build clones the repo + resolves the whole bun workspace; give it room.
      TimeoutStartSec = "1800";
    };
  };

  # The proxy + dashboard. Runs the built server from the source tree.
  systemd.services.ccflare = {
    description = "ccflare proxy + dashboard";
    after = [ "network.target" "ccflare-setup.service" ];
    requires = [ "ccflare-setup.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.bun pkgs.git ];
    environment = {
      HOME = stateDir;
      PORT = "8080";
      LOG_FORMAT = "json";
      # ccflare resolves these from lowercase env vars (see packages/config,
      # packages/database). Keep the DB + config in the persistent state dir.
      "ccflare_CONFIG_PATH" = "${stateDir}/ccflare.json";
      "ccflare_DB_PATH" = "${stateDir}/ccflare.db";
    };
    serviceConfig = {
      Type = "simple";
      User = "ccflare";
      Group = "ccflare";
      StateDirectory = "ccflare";
      WorkingDirectory = srcDir;
      ExecStart = "${pkgs.bun}/bin/bun run start";
      Restart = "on-failure";
      RestartSec = "5";
    };
  };

  # Proxy + dashboard reachable on the LAN.
  networking.firewall.allowedTCPPorts = [ 8080 ];
}
