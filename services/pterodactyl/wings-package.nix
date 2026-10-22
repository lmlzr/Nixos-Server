{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule (finalAttrs: {
  pname = "pterodactyl-wings";
  version = "1.13.4";

  src = fetchFromGitHub {
    owner = "pterodactyl";
    repo = "wings";
    tag = "v${finalAttrs.version}";
    hash = "sha256-McD+dQChR3nAaZp1vsyykAqNvrV+CAmZgmjaOR6D5+c=";
  };

  vendorHash = "sha256-98hvLcpcsZqC0DQ8JQ+xQ/OmvQ2fvO7neSBf3NHLlZw=";

  subPackages = [ "." ];

  ldflags = [
    "-s"
    "-w"
    "-X github.com/pterodactyl/wings/system.Version=${finalAttrs.version}"
  ];

  meta = {
    description = "Pterodactyl Wings – Daemon, der die Gameserver in Docker startet";
    homepage = "https://pterodactyl.io";
    license = lib.licenses.mit;
    mainProgram = "wings";
    platforms = lib.platforms.linux;
  };
})
