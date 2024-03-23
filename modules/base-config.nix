{ config, lib, pkgs, modulesPath, ... }: {

  imports = [
    (modulesPath + "/profiles/image-based-appliance.nix")
    (modulesPath + "/profiles/perlless.nix")
  ];

  # Required to allow user setup
  system.etc.overlay.mutable = true;
  users.mutableUsers = lib.mkForce true;

  # Add a default user for setup
  users.users."nixos" = {
    isNormalUser = true;
    initialPassword = "nixos";
    group = "nixos";
    useDefaultShell = true;
    extraGroups = [ "wheel" ];
  };
  users.groups."nixos" = {};

  # Fix boot warning
  environment.etc."machine-id".text = " ";

  # Use latest kernel
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Don't include kernel or its modules in rootfs
  boot.kernel.enable = false;
  boot.modprobeConfig.enable = false;
  boot.bootspec.enable = false;
  system.build = { inherit (config.boot.kernelPackages) kernel; };
  system.modulesTree = [ config.boot.kernelPackages.kernel ] ++ config.boot.extraModulePackages;

  # Modules must be loaded by initrd
  boot.initrd.kernelModules = config.boot.kernelModules;

  boot.kernelParams = [ "quiet" ];
  boot.consoleLogLevel = 1;

  # We don't need to install a bootloader
  boot.loader.grub.enable = false;

  boot.initrd.systemd.enable = true;

  # Use TCP BBR
  boot.kernel.sysctl = {
    "net.core.default_qdisc" = "fq";
    "net.ipv4.tcp_congestion_control" = "bbr";
  };

  # Use nftables
  networking.nftables.enable = true;
  boot.kernelModules = [
    "nf_tables"
    "nft_ct"
    "nft_log"
    "nf_log_syslog"
    "nft_fib"
    "nft_fib_inet"
    "nft_compat"
    "nfnetlink"
  ];

  # Replace sudo with doas
  security.sudo.enable = false;
  security.doas.enable = true;

  environment.systemPackages = with pkgs; [
    doas-sudo-shim
  ];

  networking.useNetworkd = true;
  systemd.network.wait-online.enable = false;

  systemd.watchdog = {
    runtimeTime = "10s";
    rebootTime = "30s";
  };

  services.openssh.startWhenNeeded = true;
  services.openssh.settings.PasswordAuthentication = false;

}
