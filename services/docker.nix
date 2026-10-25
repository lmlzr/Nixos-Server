{
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;

    # Alle Container (Pterodactyl-Gameserver, Portainer, Lancache-Dashboard) laufen in
    # einer gemeinsamen Slice mit festem Budget, siehe unten
    daemon.settings."cgroup-parent" = "docker-containers.slice";
  };

  # Gemeinsames Budget aller Container: einzelne Gameserver duerfen so viel nehmen wie
  # sie wollen (Limit 0 im Panel), alle zusammen aber hoechstens 24 GB RAM.
  # Bei CPU-Engpass bekommen die Dienste (Jellyfin, *arr, ...) Vorrang.
  # Kontrolle: systemctl status docker-containers.slice
  systemd.slices.docker-containers = {
    description = "Docker-Container (Gameserver usw.) mit gemeinsamem RAM-Budget";
    sliceConfig = {
      MemoryMax = "24G";
      MemoryHigh = "23G"; # vorher bremsen und Speicher zurueckholen statt sofort OOM-Kill
      CPUWeight = 50;
    };
  };

  users.users.lmlzr.extraGroups = [
    "docker"
  ];
}
