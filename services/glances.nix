{ config, lib, pkgs, ... }:

# Glances: Systemwerte (CPU, RAM, Temperaturen, Netzwerk, Belegung von fast/tank) als REST-API
# fuer die Homepage-Widgets (type: glances, version: 4) auf vmdocker. http://10.0.0.5:61208
# Ohne Login, deshalb nur im LAN offen (die Werte sind nur lesbar, steuern laesst sich nichts).
let
  port = 61208;
in
{
  services.glances = {
    enable = true;
    inherit port;
    # GPU-Plugin (Quadro P400): braucht nvidia-ml-py, das NVML aus /run/opengl-driver/lib laedt
    package = pkgs.glances.overridePythonAttrs (old: {
      propagatedBuildInputs = (old.propagatedBuildInputs or [ ]) ++ [ pkgs.python3Packages.nvidia-ml-py ];
      doCheck = false;
    });
    # --webserver: Web-UI + REST-API; --disable-webui: nur die API, die Homepage braucht
    extraArgs = [ "--webserver" "--disable-webui" "--disable-check-update" ];
  };

  systemd.services.glances = {
    environment.LD_LIBRARY_PATH = "/run/opengl-driver/lib";
    # Das Modul setzt PrivateDevices, dann fehlen /dev/nvidia* und das GPU-Plugin bleibt leer
    serviceConfig = {
      PrivateDevices = lib.mkForce false;
      DeviceAllow = [ "/dev/nvidiactl rw" "/dev/nvidia0 rw" ];
    };
  };

  networking.firewall.interfaces.${config.nas.lanInterface}.allowedTCPPorts = [ port ];
}
