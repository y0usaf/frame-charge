self:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.frame.charge;
  conf = pkgs.writeText "frame-charge.conf" ''
    limit=${toString cfg.limit}
    hysteresis=${toString cfg.hysteresis}
  '';
in
{
  options.frame.charge = {
    limit = lib.mkOption {
      type = lib.types.either (lib.types.enum [ "off" ]) (lib.types.ints.between 1 100);
      default = "off";
      description = "Battery percentage at which charging pauses, or off.";
    };
    hysteresis = lib.mkOption {
      type = lib.types.ints.positive;
      default = 3;
      description = "Percent below the limit at which charging resumes.";
    };
  };

  config = lib.mkIf (cfg.limit != "off") {
    systemd.services.frame-charge = {
      description = "Hold the battery at its charge limit";
      wantedBy = [ "multi-user.target" ];
      environment.FRAME_CHARGE_CONFIG = "${conf}";
      serviceConfig = {
        ExecStart = "${self.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/frame-charge watch";
        Restart = "on-failure";
        RestartSec = 60;
      };
    };
  };
}
