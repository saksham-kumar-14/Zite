{
  description = "Development environment for Zig 0.14.0";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    zig-overlay.url = "github:mitchellh/zig-overlay";
  };

  outputs = { self, nixpkgs, zig-overlay }:
    let
      system = "aarch64-darwin"; 
      pkgs = nixpkgs.legacyPackages.${system};
      zig = zig-overlay.packages.${system}."0.14.0";
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        name = "zig-dev-shell";
        buildInputs = [ 
          zig 
          pkgs.zlib  
        ];
      };
    };
}
