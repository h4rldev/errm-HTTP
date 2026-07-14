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
      name = "errm-HTTP";
      version = "0.1.0-prod";

      src = ./.;

      nativeBuildInputs = with pkgs; [pkg-config];
      buildInputs = with pkgs; [file bash just brotli];
      beamDeps = [];

      preBuild = ''
        sed -i 's|#!/usr/bin/env bash|#!${pkgs.bash}/bin/bash|' justfile
      '';

      env = {
        REBAR_PROFILE = "prod";
        ERL_ROOT = "${beamPackages.erlang}/lib/erlang";
      };
    };

    errm-debug = beamPackages.buildRebar3 {
      name = "errm-HTTP";
      version = "0.1.0-debug";

      src = ./.;

      nativeBuildInputs = with pkgs; [pkg-config];
      buildInputs = with pkgs; [file bash just brotli];

      preBuild = ''
        sed -i 's|#!/usr/bin/env bash|#!${pkgs.bash}/bin/bash|' justfile
      '';

      env = {
        REBAR_PROFILE = "debug";
        ERL_ROOT = "${beamPackages.erlang}/lib/erlang";
      };
    };
  in {
    packages.${system} = {
      errm-http-prod = errm-prod;
      default = errm-prod;
      errm-http-debug = errm-debug;
    };

    devShells.${system}.default = pkgs.mkShell {
      name = "errm-HTTP";

      buildInputs = with pkgs; [
        beamPackages.erlang
        beamPackages.rebar3
        file
        brotli
        pkg-config
      ];

      packages = with pkgs; [
        erlang-language-platform

        clang-tools
        bear

        just
      ];

      shellHook = ''
        export ERL_ROOT="${beamPackages.erlang}/lib/erlang"
      '';
    };
  };
}
