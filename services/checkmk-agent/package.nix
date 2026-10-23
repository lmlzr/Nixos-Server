{
  lib,
  stdenvNoCC,
  fetchurl,
  bash,
}:

# Checkmk Linux-Agent (Bash-Skript) und SMART-Plugin, unveraendert von Checkmk.
# Version moeglichst gleich oder aelter als die des Checkmk-Servers.
let
  version = "2.5.0p17";
  base = "https://raw.githubusercontent.com/Checkmk/checkmk/v${version}/agents";
in
stdenvNoCC.mkDerivation {
  pname = "checkmk-agent";
  inherit version;

  agent = fetchurl {
    url = "${base}/check_mk_agent.linux";
    hash = "sha256-e5lzhU+KoAmfHPkOezVo4ormKuRwq665oMzmsdmNdDc=";
  };

  smartPlugin = fetchurl {
    url = "${base}/plugins/smart";
    hash = "sha256-p+7b14PQu6wf9sN7oSNcImu597/jF2WC13E4H02i4DM=";
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
