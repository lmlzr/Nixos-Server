{
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
  };

  users.users.lmlzr.extraGroups = [
    "docker"
  ];
}