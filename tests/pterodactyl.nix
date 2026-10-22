# VM-Test: Pterodactyl Panel + Wings starten.
# Ausfuehren: nix build .#checks.x86_64-linux.pterodactyl -L
{ pkgs }:
pkgs.testers.runNixOSTest {
  name = "pterodactyl";
  nodes.machine = { ... }: {
    imports = [ ../services/pterodactyl ];
    services.pterodactyl.panel.enable = true;
    services.pterodactyl.wings.enable = true;
    virtualisation.memorySize = 2048;
    virtualisation.diskSize = 4096;
  };
  testScript = ''
    machine.wait_for_unit("pterodactyl-panel-setup.service")
    machine.wait_for_unit("phpfpm-pterodactyl.service")
    machine.wait_for_unit("pterodactyl-queue.service")
    machine.wait_for_unit("nginx.service")
    machine.wait_for_open_port(8090)
    print(machine.succeed("curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8090/auth/login"))
    machine.succeed("curl -sSf http://127.0.0.1:8090/auth/login | grep -i pterodactyl")
    machine.succeed("systemctl start pterodactyl-schedule.service")
    machine.succeed("pterodactyl-artisan p:user:make --email=admin@test.local --username=admin --name-first=A --name-last=B --password=Test1234Test --admin=1 --no-interaction")
    machine.succeed("test -s /var/lib/pterodactyl-panel/secrets/app-key")
    # Wings wartet auf config.yml und darf ohne sie nicht fehlschlagen
    machine.succeed("systemctl show wings -p ActiveState | grep -E 'inactive'")
    machine.succeed("systemctl is-active docker")
  '';
}
