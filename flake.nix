{
  description = "Main flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    lancache-nix.url = "github:menixator/lancache.nix";
    vpn-confinement.url = "github:Maroka-chan/VPN-Confinement";
  };

  outputs = { self, nixpkgs, ... }@inputs:
  let
    system = "x86_64-linux";
  in
  {
    nixosConfigurations.neotokyo = nixpkgs.lib.nixosSystem {
      inherit system;

      specialArgs = {
        inherit inputs;
      };

      modules = [
        ./configuration.nix
        inputs.lancache-nix.nixosModules.default
        inputs.vpn-confinement.nixosModules.default
      ];
    };

    # VM-Tests, z. B.: nix build .#checks.x86_64-linux.nas-migration -L
    checks.${system} =
      let pkgs = nixpkgs.legacyPackages.${system};
      in {
        nas-migration = import ./tests/nas-migration.nix { inherit pkgs; };
        pterodactyl = import ./tests/pterodactyl.nix { inherit pkgs; };
      };
  };
}
