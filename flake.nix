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

    errm-prod = beamPackages.buildRebar3 {
      name = "errm-http";
      version = "0.1.0";

      src = ./.;

      buildPlugins = [beamPackages.pc];
      buildInputs = with pkgs; [file];
      beamDeps = [];

      env = {
        REBAR_PROFILE = "prod";
      };
    };

    errm-debug = beamPackages.buildRebar3 {
      name = "errm-http";
      version = "0.1.0";

      src = ./.;

      buildPlugins = [beamPackages.pc];
      buildInputs = with pkgs; [file];
      beamDeps = [];

      env = {
        REBAR_PROFILE = "debug";
      };
    };
  in {
    packages.${system} = {
      errm-prod = errm-prod;
      default = errm-prod;
      errm-debug = errm-debug;
    };

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
