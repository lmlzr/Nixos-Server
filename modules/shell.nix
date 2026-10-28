{ config, lib, pkgs, ... }:

# Kurzbefehle fuer die Bash (statt ~/.bashrc, damit sie versioniert sind):
#   nrs   Repo holen (git pull) und System neu bauen (nixos-rebuild switch)
#   nup   wie nrs, vorher alle Pakete aktualisieren (nix flake update). Aendert das Update den
#         Kernel oder Kernel-Module (z. B. den NVIDIA-Treiber), wird die neue Version erst beim
#         naechsten Neustart aktiv (nixos-rebuild boot) - sonst passen Treiber-Modul und
#         -Bibliotheken bis zum Neustart nicht zusammen. flake.lock wird nur committet und
#         gepusht, wenn Bauen und Aktivieren geklappt haben.
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
        zurueck() { cp /tmp/flake.lock.vor-update flake.lock; echo "$1: flake.lock zurueckgesetzt, System unveraendert."; exit 1; }

        nix flake update || zurueck "nix flake update fehlgeschlagen"
        if git diff --quiet flake.lock; then
          echo "Keine Updates verfuegbar."
          exit 0
        fi
        git diff --stat flake.lock

        echo "Baue neue Version ..."
        neu=$(nix build --no-link --print-out-paths .#nixosConfigurations.${host}.config.system.build.toplevel) \
          || zurueck "Bauen fehlgeschlagen"

        if [ "$(readlink -f "$neu/kernel")" != "$(readlink -f /run/booted-system/kernel)" ] \
          || [ "$(readlink -f "$neu/kernel-modules")" != "$(readlink -f /run/booted-system/kernel-modules)" ]; then
          echo "Kernel oder Kernel-Module (z. B. NVIDIA-Treiber) aendern sich: aktiv nach dem naechsten Neustart."
          sudo nixos-rebuild boot --flake .#${host} || zurueck "nixos-rebuild boot fehlgeschlagen"
          neustart=1
        else
          sudo nixos-rebuild switch --flake .#${host}
          [ "$(readlink -f /run/current-system)" = "$neu" ] || zurueck "Aktivieren fehlgeschlagen"
          neustart=0
        fi

        git -c user.name="Leon Melzer" -c user.email="leon.2004.me@gmail.com" \
          commit -q -m "flake.lock: Update $(date +%Y-%m-%d)" flake.lock && git push -q \
          && echo "flake.lock committet und gepusht."

        if [ "$neustart" = 1 ]; then
          read -r -p "Jetzt neu starten? [j/N] " a
          case "$a" in j|J|ja|Ja) sudo systemctl reboot ;; *) echo "Spaeter neu starten: sudo reboot" ;; esac
        else
          echo "Update fertig."
        fi
      )
    }
  '';
}
