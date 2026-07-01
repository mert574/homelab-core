{
  description = "homelab-core NixOS LXC hosts (admin, ai, playground, postgres, cloudflared, garage, media, ccflare)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    vpn-confinement.url = "github:Maroka-chan/VPN-Confinement";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, sops-nix, vpn-confinement }:
    let
      system = "x86_64-linux";
      # Fresher packages (the AI CLIs) for hosts that opt in via `unstable`.
      unstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
      mkHost = modules: nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit unstable; };
        inherit modules;
      };
    in
    {
      nixosConfigurations = {
        # on-demand shells
        admin      = mkHost [ ./nix/hosts/admin.nix ];
        ai         = mkHost [ ./nix/hosts/ai.nix ];
        playground = mkHost [ ./nix/hosts/playground.nix ];

        # always-on services (secrets via sops-nix)
        postgres    = mkHost [ ./nix/hosts/postgres.nix sops-nix.nixosModules.sops ];
        cloudflared = mkHost [ ./nix/hosts/cloudflared.nix sops-nix.nixosModules.sops ];
        garage      = mkHost [ ./nix/hosts/garage.nix sops-nix.nixosModules.sops ];
        media       = mkHost [ ./nix/hosts/media.nix sops-nix.nixosModules.sops vpn-confinement.nixosModules.default ];
        ccflare     = mkHost [ ./nix/hosts/ccflare.nix ];
      };
    };
}
