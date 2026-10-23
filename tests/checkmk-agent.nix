# VM-Test: Checkmk-Agent liefert Daten, Zugriff nur von erlaubten Adressen.
# Ausfuehren: nix build .#checks.x86_64-linux.checkmk-agent -L
{ pkgs }:
pkgs.testers.runNixOSTest {
  name = "checkmk-agent";
  nodes = {
    server = { ... }: {
      imports = [ ../services/checkmk-agent ];
      services.checkmk-agent = {
        enable = true;
        interface = "eth1";
        allowedFrom = [ "127.0.0.1" "192.168.1.2" ]; # nur "monitor"
      };
      boot.supportedFilesystems = [ "zfs" ];
      networking.hostId = "99f03424";
      virtualisation.emptyDiskImages = [ 256 ];
    };
    monitor = { pkgs, ... }: { environment.systemPackages = [ pkgs.netcat ]; };
    fremd = { pkgs, ... }: { environment.systemPackages = [ pkgs.netcat ]; };
  };
  testScript = ''
    start_all()
    server.wait_for_unit("check-mk-agent.socket")
    server.succeed("zpool create tank /dev/vdb")

    with subtest("Agent liefert Daten"):
        out = server.succeed("${pkgs.netcat}/bin/nc -N 127.0.0.1 6556 < /dev/null || ${pkgs.netcat}/bin/nc 127.0.0.1 6556 < /dev/null")
        for s in ["<<<check_mk>>>", "Version: 2.5.0p17", "<<<df", "<<<mem>>>", "<<<cpu>>>", "<<<zpool_status>>>", "<<<zfsget>>>"]:
            assert s in out, f"{s} fehlt"

    with subtest("Asynchrone Teile laufen"):
        server.wait_for_unit("check-mk-agent-async.service")

    with subtest("Zugriff nur von erlaubten Adressen"):
        monitor.wait_for_unit("network.target")
        out = monitor.succeed("nc -w 10 server 6556 < /dev/null")
        assert "<<<check_mk>>>" in out
        out = fremd.execute("nc -w 5 server 6556 < /dev/null")[1]
        assert "<<<check_mk>>>" not in out, out
  '';
}
