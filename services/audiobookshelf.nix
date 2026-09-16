{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    audiobookshelf
  ];
    systemd.services.audiobookshelf = {
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      ExecStart = "${pkgs.audiobookshelf}/bin/audiobookshelf";
      Restart = "on-failure";
    };
  };
}