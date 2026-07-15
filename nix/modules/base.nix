{ config, pkgs, lib, modulesPath, ... }:

let
  # OSC52 pbcopy: pipe stdin into your local clipboard over SSH (headless
  # replacement for wl-clipboard). tmux: needs `set-clipboard on`.
  pbcopy = pkgs.writeShellScriptBin "pbcopy" ''
    printf '\033]52;c;%s\a' "$(base64 | tr -d '\n')"
  '';
in
{
  imports = [
    # LXC-appropriate defaults for a Proxmox container.
    "${modulesPath}/virtualisation/proxmox-lxc.nix"
  ];

  # claude-code and google-chrome are unfree.
  nixpkgs.config.allowUnfree = true;

  # flakes, so `nixos-rebuild --flake` works without the extra flag.
  #
  # The LAN Garage cache is an extra substituter: re-applies pull host closures
  # prebuilt (CI signs + pushes them, .github/workflows/validate.yml) instead of
  # rebuilding on each box. mkAfter keeps cache.nixos.org first, so upstream paths
  # come from there and our host closures from Garage. fallback + a short
  # connect-timeout mean a cache miss (or an unreachable cache, e.g. the ai box on
  # the isolated bridge) just builds locally instead of hanging. The public key is
  # the half of the `nix-store --generate-binary-cache-key nix-cache` pair; its
  # secret half is the sops NIX_CACHE_SIGNING_KEY / GitHub secret that CI signs with.
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    substituters = lib.mkAfter [ "http://nix-cache.garage.internal:3902" ];
    trusted-public-keys = lib.mkAfter [ "nix-cache:4PcFYVVhXuMebUpZjPR2BZTWYs+ZtJUPgZNEnYguWyA=" ];
    fallback = true;
    connect-timeout = 5;
  };

  # Every host resolves the LAN names from the one central file (the same file is
  # injected into the non-NixOS machines by scripts/inject-hosts.sh), so
  # nix-cache.garage.internal and the rest work without a DNS server. The ai box is on
  # the isolated bridge so those LAN IPs aren't routable there; the cache's
  # fallback + connect-timeout above mean it just builds locally on ai.
  networking.extraHosts = builtins.readFile ../lan-hosts;

  # Resolver so nixos-rebuild can reach cache.nixos.org on first apply (pihole
  # isn't up yet). mkDefault so hosts like ai can override with their own.
  networking.nameservers = lib.mkDefault [ "1.1.1.1" "8.8.8.8" ];

  # These LXCs have static IPs, so dhcpcd leases nothing and only feeds resolvconf
  # an empty nameserver set: /etc/resolv.conf ends up with no `nameserver` line and
  # every lookup fails (this nixpkgs's resolvconf emits name_servers only for the
  # local-resolver case, never for static networking.nameservers). So skip DHCP and
  # write resolv.conf statically from networking.nameservers. Defining
  # environment.etc."resolv.conf" also auto-disables resolvconf (its enable default
  # is `!(config.environment.etc ? "resolv.conf")`), so nothing clobbers it.
  networking.useDHCP = false;
  networking.resolvconf.enable = lib.mkForce false; # something enables it non-default; we own resolv.conf now
  environment.etc."resolv.conf".text =
    lib.concatMapStrings (ns: "nameserver ${ns}\n") config.networking.nameservers
    + "options edns0\n";

  # These LXCs are created with ostype "unmanaged", so Proxmox does NOT inject a
  # network config and the default (manageNetwork=false, systemd-networkd waits
  # for Proxmox) leaves them with no IP. So NixOS owns networking: each host sets
  # its own networking.interfaces.eth0 address; the gateway is shared here.
  proxmoxLXC.manageNetwork = true;
  networking.defaultGateway = lib.mkDefault "192.168.178.1";
  # LAN is IPv4-only and the ISP's IPv6 path stalls outbound TLS; keep guests off
  # it so fetches (cache.nixos.org, GHCR, etc.) don't hang on a dead v6 route.
  networking.enableIPv6 = false;

  time.timeZone = "Europe/Berlin";

  # Ship terminfo for all terminal emulators (incl. xterm-ghostty), so shelling
  # in from Ghostty/kitty/etc doesn't spew "unknown terminal" from tput.
  environment.enableAllTerminfo = true;

  # SSH is how you get in. Keys only, no passwords.
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  users.users.mert = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      # the dedicated homelab key (same one root trusts, baked into the install)
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHHe/12l40dJxmMJDDQm9VIHfuRUheLvrDnjpm0pB5aU homelab-root@mertyildiz"
    ];
  };
  security.sudo.wheelNeedsPassword = false;
  programs.zsh.enable = true;

  # Base CLI kit every NixOS box here gets. Host modules add their own on top.
  environment.systemPackages = with pkgs; [
    curl
    wget
    git
    neovim
    ripgrep
    jq
    tealdeer # binary is already `tldr`, no symlink needed
    gh
    unzip
    zip
    screen
    tmux
    pbcopy
    gcc
    gnumake
    binutils
  ];

  system.stateVersion = "26.05";
}
