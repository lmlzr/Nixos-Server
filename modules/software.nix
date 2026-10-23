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
    qbittorrent-cli
    tmux
    fastfetch
  ];
}
