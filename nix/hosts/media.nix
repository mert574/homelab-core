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
  networking.interfaces.eth0.ipv4.addresses = [{ address = "192.168.178.110"; prefixLength = 24; }];

  # Shared storage + a common group so every service can read/write. setgid (2)
  # so new files inherit the media group.
  users.groups.media.gid = 1500; # fixed so the container apps can write (PGID)

  # Storage pool: /srv is a mergerfs UNION of two branches — the boot disk
  # (/mnt/disk-boot, on the CT rootfs) and the 114G USB (/mnt/disk-usb, a host
  # bind-mount added out-of-band via `pct set --mp0`, since a tofu mount_point is
  # ForceNew and would destroy the CT). Union-at-/srv keeps /srv/media and
  # /srv/downloads on ONE logical fs so the *arr apps hardlink instead of copy,
  # while spanning both disks. mergerfs degrades gracefully if the USB is pulled:
  # the pool stays up serving the boot branch, only USB-resident files go missing.
  # The host mountpoint /mnt/media-usb-110 is `chattr +i` so if the USB unmounts,
  # mergerfs can't write into the empty stub and fill the boot disk.
  fileSystems."/srv" = {
    device = "/mnt/disk-boot:/mnt/disk-usb";
    fsType = "fuse.mergerfs";
    options = [
      "cache.files=partial"
      "dropcacheonclose=true"
      "category.create=mfs"   # new files -> branch with most free space
      "moveonenospc=true"     # spill to the other branch if one fills mid-write
      "minfreespace=10G"      # boot branch shares the OS rootfs; keep headroom
      "allow_other"           # cross-uid access (root mounts it; arr/jellyfin/qbt use it)
      "nofail"                # a missing branch must not block boot
      "x-systemd.requires-mounts-for=/mnt/disk-usb"
    ];
  };
  system.fsPackages = [ pkgs.mergerfs ]; # provides the mount.fuse.mergerfs helper
  programs.fuse.userAllowOther = true;

  systemd.tmpfiles.rules = [
    # Boot-disk branch of the pool. The USB branch dirs live on the USB itself
    # (created when it was formatted), so they aren't managed here — that also
    # avoids fighting the immutable stub when the USB is absent.
    "d /mnt/disk-boot 2775 root media - -"
    "d /mnt/disk-boot/media 2775 root media - -"
    "d /mnt/disk-boot/downloads 2775 root media - -"
    # The iGPU is passed into the LXC (tofu/media.tf dev0) owned root:root, so the
    # jellyfin user (in group render) can't open it and HW transcoding fails with
    # "no valid media source". Hand the render node to the render group on every boot.
    "z /dev/dri/renderD128 0660 root render - -"
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
  # Download files group-writable (664/775) so the *arr apps (same "media" group)
  # can hardlink them into the library instead of copying. Default is 644, and with
  # fs.protected_hardlinks=1 a group-read-only file can't be hardlinked by another
  # user -> Sonarr/Radarr fall back to a full copy (every grab stored twice). 664
  # gives the media group write, which satisfies protected_hardlinks.
  systemd.services.qbittorrent.serviceConfig.UMask = "0002";

  # Self-heal the single-instance lock so boot stays 0-touch. An unclean shutdown
  # (power loss, OOM, a read-only-fs crash) leaves a stale lockfile; qBittorrent's
  # instance check then makes it exit 0 silently on every boot and the WebUI never
  # returns until the lock is cleared by hand. Removing it before start fixes that;
  # rm -f is a no-op on a clean boot. mkBefore so it runs ahead of any hook the
  # vpn-confinement module adds and merges instead of clobbering it.
  systemd.services.qbittorrent.serviceConfig.ExecStartPre =
    lib.mkBefore [ "${pkgs.coreutils}/bin/rm -f /var/lib/qBittorrent/qBittorrent/config/lockfile" ];

  # Automation on the LAN.
  services.prowlarr.enable = true; # indexers (9696)
  services.sonarr = { enable = true; group = "media"; }; # TV (8989)
  services.radarr = { enable = true; group = "media"; }; # movies (7878)
  # Create library dirs group-writable (0002) so Jellyfin (group media) can delete
  # imported files. Default umask 022 makes drwxr-sr-x dirs that block group deletes
  # -> Jellyfin DELETE fails with "Permission denied". Matches qBittorrent's UMask.
  systemd.services.sonarr.serviceConfig.UMask = "0002";
  systemd.services.radarr.serviceConfig.UMask = "0002";
  services.bazarr = { enable = true; group = "media"; }; # subtitles (6767)
  services.seerr.enable = true; # jellyseerr: requests + discovery front-end (5055)

  # Media server (web UI + Jellyfin apps) with Intel iGPU (UHD 630) hardware
  # transcoding. The iGPU is passed into the LXC in tofu/media.tf. NOTE: use VAAPI,
  # not QSV — the QSV/MFX (oneVPL) path fails to create a session in this LXC
  # (Error creating a MFX session: -9), while VAAPI via the iHD driver works. Set
  # in Jellyfin: Playback -> Hardware acceleration = VAAPI, device /dev/dri/renderD128.
  services.jellyfin = { enable = true; group = "media"; };
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver    # iHD VAAPI driver (Gen9+) — the working path here
      vpl-gpu-rt            # oneVPL runtime for QSV (kept, but QSV/MFX is broken in-LXC)
      intel-compute-runtime-legacy1 # NEO OpenCL runtime — Jellyfin tone-maps HDR/Dolby
                            # Vision to SDR via tonemap_opencl; UHD 630 (Gen9.5) has no
                            # VAAPI VPP tonemap, so without OpenCL every HDR transcode
                            # fails. Must be the *legacy1* build: mainline NEO dropped
                            # Gen9-11 support, leaving UHD 630 with zero OpenCL platforms.
    ];
  };

  # DLNA for the TV, declaratively. Jellyfin's DLNA is a manual/plugin step in
  # recent versions, so a dedicated DLNA server handles the TV instead.
  services.minidlna = {
    enable = true;
    openFirewall = true;
    settings = {
      media_dir = [ mediaDir ];
      friendly_name = "Mertflix";
      inotify = "yes";
    };
  };

  users.users.jellyfin.extraGroups = [ "media" "video" "render" ];
  users.users.sonarr.extraGroups = [ "media" ];
  users.users.radarr.extraGroups = [ "media" ];
  users.users.bazarr.extraGroups = [ "media" ];
  users.users.minidlna.extraGroups = [ "media" ];

  # Podman backend for the containerised apps below (lazylibrarian, byparr, suggestarr).
  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";

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

  # Homepage: the household "home page" — at-a-glance disk space + links to
  # Jellyfin (watch) and Jellyseerr (request), the only two apps the end user
  # touches. Served on port 80 so it's just http://media.internal. The disk
  # widgets read the two physical pool branches (real ext4, reliable statvfs)
  # plus the mergerfs union for the aggregate figure — see homepage/widgets.yaml.
  virtualisation.oci-containers.containers.homepage = {
    image = "ghcr.io/gethomepage/homepage:latest";
    ports = [ "80:3000" ];
    environment = {
      # Homepage 0.9+ refuses requests whose Host header isn't allow-listed.
      HOMEPAGE_ALLOWED_HOSTS = "media.internal,192.168.178.110,media.internal:80,192.168.178.110:80";
      PUID = "1000";
      PGID = "1500"; # the media group
      TZ = "Europe/Berlin";
    };
    volumes = [
      "homepage-config:/app/config"                               # writable: logs + generated files
      "${./homepage/settings.yaml}:/app/config/settings.yaml:ro"  # declarative config (tracks repo)
      "${./homepage/services.yaml}:/app/config/services.yaml:ro"
      "${./homepage/widgets.yaml}:/app/config/widgets.yaml:ro"
      "${./homepage/bookmarks.yaml}:/app/config/bookmarks.yaml:ro"
      "/srv:/pool:ro"                # media pool (mergerfs union) — headline number
      "/mnt/disk-boot:/disk-boot:ro" # OS/root-disk branch (the one that fills and breaks the CT)
      "/mnt/disk-usb:/disk-usb:ro"   # USB branch
    ];
    # The image's HEALTHCHECK probes localhost:3000 immediately on boot and loses
    # the race while the app is still starting, so the transient healthcheck unit
    # fails and makes `nixos-rebuild switch` return exit 4 even though the container
    # is fine. Drop the healthcheck — the container's own restart policy covers it.
    extraOptions = [ "--no-healthcheck" ];
  };

  # Live TV: regenerate the curated IPTV playlist daily (iptv-org stream URLs drift).
  # scripts/livetv-playlist.sh curates top-mainstream Turkish + international English
  # news + German public/news, and remaps each tvg-id to the epgshare01 XMLTV guide.
  # The M3U tuner + XMLTV listing providers live in Jellyfin's own state (set via API),
  # and Jellyfin re-reads the file + re-fetches the guide on its daily guide refresh.
  systemd.services.livetv-playlist = {
    description = "Regenerate the Jellyfin Live TV playlist (curated iptv-org + epgshare01 tvg-ids)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = with pkgs; [ bash curl gzip gnused gawk gnugrep coreutils ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash ${../../scripts/livetv-playlist.sh} /var/lib/jellyfin/livetv/playlist.m3u";
    };
  };
  systemd.timers.livetv-playlist = {
    description = "Daily Live TV playlist refresh";
    wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = "*-*-* 05:17:00"; Persistent = true; };
  };

  # LAN access: web UIs, Jellyfin, DLNA discovery (UDP), the *arr apps,
  # lazylibrarian, homepage (80). (Byparr stays on localhost.)
  networking.firewall = {
    allowedTCPPorts = [ 80 8096 8920 8989 7878 9696 8080 6767 5055 5299 ];
    allowedUDPPorts = [ 1900 7359 ];
  };
}
