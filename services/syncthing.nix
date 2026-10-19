{ config, pkgs, ... }:

{
  services.syncthing = {
    enable = true;
    user = "lmlzr";
    group = "users";

    guiAddress = "0.0.0.0:8384";
    # Klartext-Passwort, wird beim Start gehasht. Anlegen mit:
    #   echo -n 'passwort' | sudo tee /etc/secrets/syncthing-gui && sudo chmod 600 /etc/secrets/syncthing-gui
    #   sudo chown lmlzr /etc/secrets/syncthing-gui
    guiPasswordFile = "/etc/secrets/syncthing-gui";
    settings.gui.user = "lmlzr";

    # Geraete und Ordner werden in der GUI verwaltet. Ohne diese Zeilen loescht
    # syncthing-init beim Start alles, was nicht in Nix definiert ist.
    overrideDevices = false;
    overrideFolders = false;

    # 22000 TCP/UDP (Sync) + 21027 UDP (Discovery)
    openDefaultPorts = true;
  };

  networking.firewall.allowedTCPPorts = [
    8384
  ];
}
