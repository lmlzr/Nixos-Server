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
    bat
    ffmpeg
    libbluray
    kitty.terminfo
    # qbittorrent-cli  # baut aktuell nicht: patchelf-Absturz an .NET-2.1-Runtime (nixpkgs-Bug)
    tmux
    fastfetch
    claude-code
  ];
}
