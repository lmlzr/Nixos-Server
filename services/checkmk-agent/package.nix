{
  lib,
  stdenvNoCC,
  fetchurl,
  bash,
}:

# Checkmk Linux-Agent (Bash-Skript) und SMART-Plugin, unveraendert von Checkmk.
# Version moeglichst gleich oder aelter als die des Checkmk-Servers.
let
  version = "2.5.0p7"; # gleich wie der Checkmk-Server (10.0.0.3)
  base = "https://raw.githubusercontent.com/Checkmk/checkmk/v${version}/agents";
in
stdenvNoCC.mkDerivation {
  pname = "checkmk-agent";
  inherit version;

  agent = fetchurl {
    url = "${base}/check_mk_agent.linux";
    hash = "sha256-WVcETpNzj7wGuf3jh3MFE+QESgFu35/xH+hL15GnInY=";
  };

  smartPlugin = fetchurl {
    url = "${base}/plugins/smart";
    hash = "sha256-hFwuvveSw0MmefylzHpzjp17k/jbQh5KfkayfXaJU68=";
  };

  dontUnpack = true;
  buildInputs = [ bash ];

  installPhase = ''
    install -Dm755 $agent $out/bin/check_mk_agent
    install -Dm755 $smartPlugin $out/share/check_mk_agent/plugins/smart
    patchShebangs $out/bin $out/share
  '';

  meta = {
    description = "Checkmk Agent fuer Linux";
    homepage = "https://checkmk.com";
    license = lib.licenses.gpl2Only;
    mainProgram = "check_mk_agent";
    platforms = lib.platforms.linux;
  };
}
