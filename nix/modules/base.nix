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
  # The LAN Garage cache (an extra substituter) is left out until Garage is up and
  # we have a real signing key. First bring-up builds locally, which it would do
  # anyway. To turn it on later: generate a key with
  # `nix-store --generate-binary-cache-key`, then add back
  #   substituters = lib.mkAfter [ "http://nix-cache.garage.internal:3902" ];
  #   trusted-public-keys = lib.mkAfter [ "nix-cache:<the-real-base64-public-key>" ];
  #   fallback = true; connect-timeout = 5;
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
  };

  # Every host resolves the LAN names from the one central file (the same file is
  # injected into the non-NixOS machines by scripts/inject-hosts.sh), so
  # nix-cache.garage.internal and the rest work without a DNS server. The ai box is on
  # the isolated bridge so those LAN IPs aren't routable there; the cache's
  # fallback + connect-timeout above mean it just builds locally on ai.
  networking.extraHosts = builtins.readFile ../../network/lan-hosts;

  # Resolver so nixos-rebuild can reach cache.nixos.org on first apply (pihole
  # isn't up yet). mkDefault so hosts like ai can override with their own.
  networking.nameservers = lib.mkDefault [ "1.1.1.1" "8.8.8.8" ];

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
