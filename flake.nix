{
  description = "Errm.. HTTP, an erlang library for HTTP/1.1 that's easy to use.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {inherit system;};
    beamPackages = pkgs.beamPackages;

    errm = beamPackages.buildRebar3 {
      name = "errm-HTTP";
      version = "0.1.0";

      src = ./.;

      buildPlugins = [beamPackages.pc];
      buildInputs = with pkgs; [file];
      beamDeps = [];
    };
  in {
    packages.${system}.default = errm;

    devShells.${system}.default = pkgs.mkShell {
      name = "errm-HTTP";

      buildInputs = with pkgs; [
        beamPackages.erlang
        beamPackages.rebar3
        file
      ];

      packages = with pkgs; [
        erlang-language-platform

        clang-tools
        bear

        just
      ];
    };
  };
}
