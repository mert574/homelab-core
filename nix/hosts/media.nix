# Mixed-use box: the media stack + a place for small scripts (add systemd timers).
# The torrent client runs inside a Mullvad WireGuard namespace with a kill-switch
# (no VPN = no route = no traffic). Jellyfin + the *arr apps run on the LAN so the
# TV and you can reach them.
{ config, pkgs, lib, ... }:
let
  mediaDir = "/srv/media";
  downloadDir = "/srv/downloads";
in
{
  imports = [ ../modules/base.nix ../modules/sops.nix ];

  # Shared storage + a common group so every service can read/write. setgid (2)
  # so new files inherit the media group.
  users.groups.media.gid = 1500; # fixed so the container apps can write (PGID)
  systemd.tmpfiles.rules = [
    "d ${mediaDir} 2775 root media - -"
    "d ${downloadDir} 2775 root media - -"
  ];

  # Mullvad WireGuard namespace. The whole wg-quick config (incl. the private key)
  # is the secret; see DEPLOY.md for creating secrets/mullvad.wg.enc.
  sops.secrets."mullvad-wg" = {
    format = "binary";
    sopsFile = ../../secrets/mullvad.wg.enc;
  };
  vpnNamespaces.mullvad = {
    enable = true;
    wireguardConfigFile = config.sops.secrets."mullvad-wg".path;
    accessibleFrom = [ "192.168.178.0/24" "127.0.0.1" ];
    portMappings = [{ from = 8080; to = 8080; }]; # qbittorrent web ui
  };

  # Torrent client, confined to the VPN namespace.
  services.qbittorrent = {
    enable = true;
    webuiPort = 8080;
    user = "qbittorrent";
    group = "media";
  };
  systemd.services.qbittorrent.vpnConfinement = {
    enable = true;
    vpnNamespace = "mullvad";
  };

  # Automation on the LAN.
  services.prowlarr.enable = true; # indexers (9696)
  services.sonarr = { enable = true; group = "media"; }; # TV (8989)
  services.radarr = { enable = true; group = "media"; }; # movies (7878)
  services.bazarr = { enable = true; group = "media"; }; # subtitles (6767)
  services.seerr.enable = true; # jellyseerr: requests + discovery front-end (5055)

  # Media server (web UI + Jellyfin apps), with Intel QuickSync (UHD 630) for
  # hardware transcoding. The iGPU is passed into the LXC in tofu/media.tf.
  services.jellyfin = { enable = true; group = "media"; };
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver # iHD VAAPI driver (Gen9+)
      vpl-gpu-rt         # oneVPL runtime for QSV
    ];
  };

  # DLNA for the TV, declaratively. Jellyfin's DLNA is a manual/plugin step in
  # recent versions, so a dedicated DLNA server handles the TV instead.
  services.minidlna = {
    enable = true;
    openFirewall = true;
    settings = {
      media_dir = [ mediaDir ];
      friendly_name = "Home Media";
      inotify = "yes";
    };
  };

  users.users.jellyfin.extraGroups = [ "media" "video" "render" ];
  users.users.sonarr.extraGroups = [ "media" ];
  users.users.radarr.extraGroups = [ "media" ];
  users.users.bazarr.extraGroups = [ "media" ];
  users.users.minidlna.extraGroups = [ "media" ];

  # Lidarr (music management) for digarr to feed into.
  services.lidarr = { enable = true; group = "media"; }; # 8686
  users.users.lidarr.extraGroups = [ "media" ];

  # digarr: AI music discovery (not packaged; runs as a container). Uses the
  # postgres LXC for its DB and talks to Lidarr above. Fill secrets/digarr.env.enc
  # from digarr's .env.example (DATABASE_URL -> the postgres LXC, AI provider key,
  # initial creds, LIDARR_API_KEY).
  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";
  sops.secrets."digarr-env" = {
    format = "binary";
    sopsFile = ../../secrets/digarr.env.enc;
  };
  virtualisation.oci-containers.containers.digarr = {
    image = "iuliandita/digarr:stable";
    ports = [ "3000:3000" ];
    environment = {
      AI_PROVIDER = "anthropic";
      LIDARR_URL = "http://192.168.178.110:8686";
    };
    environmentFiles = [ config.sops.secrets."digarr-env".path ];
  };

  # LazyLibrarian: books/magazines (Readarr is retired). Container.
  virtualisation.oci-containers.containers.lazylibrarian = {
    image = "lscr.io/linuxserver/lazylibrarian:latest";
    ports = [ "5299:5299" ];
    environment = {
      PUID = "1000";
      PGID = "1500"; # the media group
      TZ = "Europe/Berlin";
    };
    volumes = [
      "lazylibrarian-config:/config"
      "${mediaDir}:/media"
      "${downloadDir}:/downloads"
    ];
  };

  # Byparr: Cloudflare solver for Prowlarr (FlareSolverr replacement). Localhost
  # only; add it in Prowlarr as a FlareSolverr proxy at http://localhost:8191.
  virtualisation.oci-containers.containers.byparr = {
    image = "ghcr.io/thephaseless/byparr:latest";
    ports = [ "127.0.0.1:8191:8191" ];
  };

  # SuggestArr: watches recently-played in Jellyfin and auto-requests similar
  # titles via Jellyseerr (-> Sonarr/Radarr). Hands-off video discovery. Config
  # (TMDb key, Jellyfin + Jellyseerr URLs/keys) is set in its web UI.
  virtualisation.oci-containers.containers.suggestarr = {
    image = "ciuse99/suggestarr:latest";
    ports = [ "5000:5000" ];
    volumes = [ "suggestarr-config:/app/config/config_files" ];
  };

  # LAN access: web UIs, Jellyfin, DLNA discovery (UDP), the *arr apps, digarr,
  # lazylibrarian, suggestarr. (Byparr stays on localhost.)
  networking.firewall = {
    allowedTCPPorts = [ 8096 8920 8989 7878 9696 8080 8686 3000 6767 5055 5299 5000 ];
    allowedUDPPorts = [ 1900 7359 ];
  };
}
