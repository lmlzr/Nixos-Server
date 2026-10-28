{ config, lib, pkgs, ... }:

# Kurzbefehle fuer die Bash (statt ~/.bashrc, damit sie versioniert sind):
#   nrs   Repo holen (git pull) und System neu bauen (nixos-rebuild switch)
#   nup   wie nrs, vorher alle Pakete aktualisieren (nix flake update); klappt der Rebuild,
#         wird flake.lock committet und gepusht, sonst bleibt alles beim Alten
let
  repo = "/home/lmlzr/Nixos-Server";
  host = config.networking.hostName;
in
{
  programs.bash.interactiveShellInit = ''
    nrs() {
      (
        cd ${repo} || exit 1
        git pull --ff-only || { echo "git pull fehlgeschlagen (lokale Aenderungen?)"; exit 1; }
        sudo nixos-rebuild switch --flake .#${host}
      )
    }

    nup() {
      (
        cd ${repo} || exit 1
        git pull --ff-only || { echo "git pull fehlgeschlagen (lokale Aenderungen?)"; exit 1; }
        cp flake.lock /tmp/flake.lock.vor-update
        nix flake update || exit 1
        if git diff --quiet flake.lock; then
          echo "Keine Updates verfuegbar."
          exit 0
        fi
        echo "Neue Versionen:"
        git diff --stat flake.lock
        if sudo nixos-rebuild switch --flake .#${host}; then
          git -c user.name="Leon Melzer" -c user.email="leon.2004.me@gmail.com" \
            commit -q -m "flake.lock: Update $(date +%Y-%m-%d)" flake.lock && git push -q \
            && echo "Update fertig, flake.lock committet und gepusht."
        else
          cp /tmp/flake.lock.vor-update flake.lock
          echo "Rebuild fehlgeschlagen: flake.lock zurueckgesetzt, System unveraendert."
          exit 1
        fi
      )
    }
  '';
}
