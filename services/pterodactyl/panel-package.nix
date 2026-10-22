{
  lib,
  fetchzip,
  php83,
  dataDir ? "/var/lib/pterodactyl-panel",
}:

let
  php = php83.buildEnv {
    extensions = { enabled, all }: enabled ++ (with all; [ redis ]);
  };
in
php.buildComposerProject2 (finalAttrs: {
  pname = "pterodactyl-panel";
  version = "1.15.2";

  # Release-Tarball enthaelt bereits das gebaute Frontend (public/assets)
  src = fetchzip {
    url = "https://github.com/pterodactyl/panel/releases/download/v${finalAttrs.version}/panel.tar.gz";
    stripRoot = false;
    hash = "sha256-A+M7IJf0GP7E6PiTRMErPTBKawkh2HRJw9nqCGxjcEY=";
  };

  vendorHash = "sha256-cTsJsPopq94VojzzOxC7YEOOXRNf61i1xD20HjMTHOA=";

  passthru.phpPackage = php;

  # Beschreibbare Teile liegen im Datenordner, nicht im Nix-Store
  postInstall = ''
    chmod -R u+w $out/share
    mv $out/share/php/pterodactyl-panel/* $out/share/php/pterodactyl-panel/.env.example $out/
    rm -R $out/share $out/storage $out/bootstrap/cache
    ln -s ${dataDir}/storage $out/storage
    ln -s ${dataDir}/cache $out/bootstrap/cache
    ln -s ${dataDir}/.env $out/.env
  '';

  meta = {
    description = "Pterodactyl Panel – Verwaltungsoberflaeche fuer Gameserver";
    homepage = "https://pterodactyl.io";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
})
