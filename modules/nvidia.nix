{ config, pkgs, ... }:
{
    nixpkgs.config.nvidia.acceptLicense = true;
    services.xserver.videoDrivers = [ "nvidia" ];

    environment.variables = {
        GBM_BACKEND = "nvidia-drm";
        LIBVA_DRIVER_NAME = "nvidia";
        __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    };
    environment.systemPackages = with pkgs; [
       vulkan-loader
       vulkan-validation-layers
       vulkan-tools
    ];
    hardware = {
        nvidia = {
            modesetting.enable = true;
            powerManagement.enable = true;
            package = config.boot.kernelPackages.nvidiaPackages.latest;
            nvidiaSettings = true;
            open = false;
        };
        graphics = {
            enable = true;
            enable32Bit = true;
            extraPackages = with pkgs; [
                nvidia-vaapi-driver
                libva-vdpau-driver
                libvdpau-va-gl
            ];
       };
   };
    #nixpkgs.config = {
    #    allowUnfree = true;
    #    cudaSupport = true;
    #};

   # allow overclocking
    hardware.nvidia.prime.offload.enable = false; 
    services.xserver.displayManager.setupCommands = ''
    nvidia-settings -a '[gpu:0]/GPUPowerMizerMode=1'
    '';
    services.xserver.deviceSection = ''
    Option "Coolbits" "8"
    '';

}