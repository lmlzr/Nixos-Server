{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    syncthing
    git
    gh
    neovim
    fastfetch
    wget
    gcc
    pulseaudio
    stow
    socat
    cron
    rar
    fzf
    htop
    qemu
    kvmtool
    bat
    ffmpeg
    libbluray
    mesa
    sudo
    kitty
  ];
}