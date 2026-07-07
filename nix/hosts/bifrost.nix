# Bifrost: a multi-account proxy in front of Anthropic/OpenAI. Load-balances
# requests across several Claude accounts, tracks usage, and rotates accounts on
# budget exhaustion. It's a single Go binary, so it doesn't need a
# git-clone-and-build step on every boot.
#
# There's no binary attached to Bifrost's GitHub releases (checked at plan time --
# asset lists are empty), so it's run from the maintainers' own Docker image rather
# than trying to vendor a build. config.json + its SQLite config store live on the
# persistent volume, so a container recreation never loses accounts.
#
# Usage notes:
# - Point an OpenAI-compatible client at http://bifrost.internal:8080/openai (or
#   /v1/chat/completions directly). Model ids are prefixed with the provider name
#   (`anthropic/<model-id>`) -- see the actual ids configured in config.json.
# - Accounts/providers/budgets are configured through Bifrost's UI or config.json,
#   not sops.
{ config, pkgs, lib, ... }:
let
  stateDir = "/var/lib/bifrost";
  # Pin Bifrost to a known-good release; bump this to update. v2.0.0 is still a
  # prerelease as of writing, so track the v1.6.x line.
  bifrostImageTag = "v1.6.3";
in
{
  imports = [ ../modules/base.nix ];
  networking.interfaces.eth0.ipv4.addresses = [{ address = "192.168.178.113"; prefixLength = 24; }];

  virtualisation.docker.enable = true;

  virtualisation.oci-containers.backend = "docker";
  virtualisation.oci-containers.containers.bifrost = {
    image = "maximhq/bifrost:${bifrostImageTag}";
    autoStart = true;
    ports = [ "8080:8080" ];
    volumes = [ "${stateDir}:/app/data" ];
  };

  systemd.tmpfiles.rules = [
    "d ${stateDir} 0750 root root -"
  ];

  # Proxy + dashboard reachable on the LAN.
  networking.firewall.allowedTCPPorts = [ 8080 ];
}
