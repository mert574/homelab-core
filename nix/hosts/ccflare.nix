# ccflare: a multi-account proxy in front of Anthropic/OpenAI. It load-balances
# requests across several Claude (and OpenAI) accounts and records request history
# + analytics, exposing a dashboard and the proxy on :8080. Point a client at
# http://ccflare.internal:8080 and it fans out over the accounts you add.
#
# ccflare is a Bun monorepo, not packaged in nixpkgs and with no release artifact,
# so we fetch + build it at a pinned commit in a oneshot (mirrors the garage-setup
# pattern in garage.nix) and run `bun run start` as a long-lived service. The DB +
# config are SQLite/JSON under /var/lib/ccflare, so a rebuild never loses accounts.
#
# Usage notes (learned wiring Activepieces up to it, see cluster/apps/activepieces):
# - No auth needed, and no per-client API key exists -- ccflare ignores whatever
#   Authorization/x-api-key header a client sends and always uses its own stored
#   account credentials (`GET /api/accounts` to see what's registered).
# - Native passthrough (`/v1/anthropic/*`, `/v1/openai/*`) forwards the client's
#   auth header straight to the real upstream API instead of substituting one of
#   ccflare's accounts -- useless unless the client happens to have its own real
#   key. Fine for Claude Code CLI (built for this), not for pointing a random
#   OpenAI-compatible app at it.
# - What you actually want for that: the compat route
#   `POST /v1/ccflare/openai/chat/completions`, OpenAI request/response schema,
#   but `model` must be prefixed (`anthropic/<model-id>` -> prefers the
#   `claude-code` accounts, `openai/<model-id>` -> prefers `codex`/`openai`).
#   Bare model names 400. This is the one that actually load-balances across
#   the registered accounts.
# - Full reference: `docs/api-http.md` in the ccflare source tree on the box
#   (`/var/lib/ccflare/src/docs/`).
{ config, pkgs, lib, ... }:
let
  # ccflare packaged as an immutable /nix/store derivation (built once in CI,
  # substituted from the Garage cache). Bump the ref + hashes in this file to
  # update; a rebuild NEVER builds from source on the box, so a service restart
  # is just a process restart -- it can no longer trigger a multi-hour bun build.
  ccflare = pkgs.callPackage ../pkgs/ccflare.nix { };
  stateDir = "/var/lib/ccflare";
in
{
  imports = [ ../modules/base.nix ];
  networking.interfaces.eth0.ipv4.addresses = [{ address = "192.168.178.111"; prefixLength = 24; }];

  # bun on PATH for operator convenience (inspecting the DB, ad-hoc scripts). The
  # service runs the packaged binary, which carries its own bun; this isn't wired
  # into the service.
  environment.systemPackages = [ pkgs.bun ];

  # Dedicated service account; its home is the state dir (bun's cache lives there).
  users.users.ccflare = {
    isSystemUser = true;
    group = "ccflare";
    home = stateDir;
  };
  users.groups.ccflare = { };

  # The proxy + dashboard. Runs the packaged server straight from /nix/store.
  systemd.services.ccflare = {
    description = "ccflare proxy + dashboard";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
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
      ExecStart = lib.getExe ccflare;
      Restart = "on-failure";
      RestartSec = "5";
    };
  };

  # Proxy + dashboard reachable on the LAN.
  networking.firewall.allowedTCPPorts = [ 8080 ];
}
