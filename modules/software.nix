{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    git
    gh
    neovim
    wget
    gcc
    stow
    socat
    rar
    fzf
    htop
    nvtopPackages.nvidia # GPU-Last (nvidia-smi stuerzt mit dem 580er-Legacy-Treiber ab)
    bat
    mediainfo # Metadaten fuer die Vorschau in yazi, siehe programs.yazi
    ffmpeg
    libbluray
    kitty.terminfo
    # qbittorrent-cli  # baut aktuell nicht: patchelf-Absturz an .NET-2.1-Runtime (nixpkgs-Bug)
    fastfetch
    claude-code
    wireguard-tools
  ];

  # Dateimanager im Terminal mit Vorschau (Start: yazi), bringt fd/rg/file/jq/poppler mit.
  # mediainfo zeigt bei Video, Audio und Bild die Vorschau plus Metadaten (scrollen: J/K).
  programs.yazi = {
    enable = true;
    plugins.mediainfo = pkgs.yaziPlugins.mediainfo;
    settings.yazi.plugin = {
      prepend_preloaders = [ { mime = "{audio,video,image}/*"; run = "mediainfo"; } ];
      prepend_previewers = [ { mime = "{audio,video,image}/*"; run = "mediainfo"; } ];
    };
  };
}
