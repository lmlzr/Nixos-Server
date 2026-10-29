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
    yazi # Dateimanager im Terminal mit Vorschau (Start: yazi), bringt fd/rg/file/jq/poppler mit
    ffmpeg
    libbluray
    kitty.terminfo
    # qbittorrent-cli  # baut aktuell nicht: patchelf-Absturz an .NET-2.1-Runtime (nixpkgs-Bug)
    tmux
    fastfetch
    claude-code
    wireguard-tools
  ];
}
