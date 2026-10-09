{
  description = "Hold a Steam Frame's battery at a charge limit";

  inputs.nixpkgs.url = "https://releases.nixos.org/nixpkgs/nixpkgs-26.11pre1080803.419fe0f449b3/nixexprs.tar.zst";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "aarch64-linux"
        "x86_64-linux"
      ];
      eachSystem = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = eachSystem (pkgs: rec {
        frame-charge = pkgs.runCommand "frame-charge" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
          install -Dm755 ${./frame-charge} $out/bin/frame-charge
          patchShebangs $out/bin/frame-charge
          wrapProgram $out/bin/frame-charge --prefix PATH : ${pkgs.coreutils}/bin
        '';
        default = frame-charge;
      });

      apps = eachSystem (pkgs: {
        default = {
          type = "app";
          program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/frame-charge";
        };
      });

      checks = eachSystem (pkgs: {
        lint = pkgs.runCommand "frame-charge-lint" { nativeBuildInputs = [ pkgs.shellcheck ]; } ''
          shellcheck -s sh ${./frame-charge} ${./contrib/stock-install}
          touch $out
        '';
      });

      formatter = eachSystem (pkgs: pkgs.nixfmt);
    };
}
