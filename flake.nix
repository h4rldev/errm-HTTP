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
  in {
    devShells.${system}.default = pkgs.mkShell {
      name = "errm-HTTP";

      buildInputs = with pkgs; [
        beamPackages.erlang
        beamPackages.rebar3
      ];

      packages = with pkgs; [
        erlang-language-platform
      ];
    };
  };
}
