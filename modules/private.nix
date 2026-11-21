{ lib, inputs, ... }:

# Private Werte (echte Domain, Mail-Adressen) aus einer Datei ausserhalb des Repos, damit sie
# nicht im oeffentlichen GitHub-Repo stehen. Quelle: Flake-Eingang "private"
# (~/.config/nixos-private/werte.env), Vorlage und Anleitung: private/werte.env.example.
# Verwendung: config.nas.private.DOMAIN usw.
let
  file = "${inputs.private}/werte.env";
  lines = lib.filter (l: l != "" && !lib.hasPrefix "#" l)
    (map lib.trim (lib.splitString "\n" (builtins.readFile file)));
  pair = l:
    let m = builtins.match "([A-Za-z_][A-Za-z0-9_]*)=(.*)" l;
    in if m == null then throw "private/werte.env: ungueltige Zeile: ${l}"
       else lib.nameValuePair (lib.elemAt m 0) (lib.trim (lib.elemAt m 1));
in
{
  options.nas.private = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    readOnly = true;
    description = "Werte aus ~/.config/nixos-private/werte.env (siehe private/werte.env.example).";
  };

  config.nas.private = lib.listToAttrs (map pair lines);
}
