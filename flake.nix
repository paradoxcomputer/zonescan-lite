{
  description = "ZoneScan Lite - a QML block explorer for a Logos zone";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder/0.2.1";
    nix-bundle-lgx.url = "github:logos-co/nix-bundle-lgx";
  };

  outputs =
    inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
