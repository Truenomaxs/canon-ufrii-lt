{
  description = "Canon UFRII LT CUPS driver for NixOS";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;

        config.allowUnfreePredicate =
          pkg:
          builtins.elem (nixpkgs.lib.getName pkg) [
            "canon-ufrii-lt"
          ];
      };
    in
    {
      nixosModules.default = import ./module.nix;

      packages.${system}.default = pkgs.callPackage ./package.nix { };

      checks.${system}.build = self.packages.${system}.default;
    };
}
