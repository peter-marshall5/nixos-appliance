{ config, lib, pkgs, modulesPath, ... }:
let

  cfg = config.diskImage;

  version = "${config.osName}_${config.release}";

  kernelPath = "/EFI/Linux/${version}.efi";

  partlabelPath = "/dev/disk/by-partlabel";

  arch =
    if pkgs.stdenv.hostPlatform.system == "x86_64-linux" then "x86-64"
    else if pkgs.stdenv.hostPlatform.system == "armv7l-linux" then "arm"
    else throw "Unsupported architecture";

  efiArch = pkgs.stdenv.hostPlatform.efiArch;

in

{

  options = {

    diskImage.dataLabel = lib.mkOption {
      default = "data";
      type = lib.types.str;
      description = lib.mdDoc ''
        Label used for the persistent data partition.
      '';
    };
    diskImage.luks.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
    diskImage.luks.defaultKey = lib.mkOption {
      type = lib.types.str;
      default = "changeme";
      description = lib.mdDoc ''
        Initial passphrase used for disk encryption.
      '';
    };
    osName = lib.mkOption {
      default = "nixos";
      type = lib.types.str;
      description = lib.mdDoc ''
        Name used as a prefix for kernels and root partitions.
      '';
    };
    release = lib.mkOption {
      type = lib.types.str;
      description = lib.mdDoc ''
        Incremental version number for releases.
      '';
    };
    boot.loader.depthcharge.enable = lib.mkOption {
      default = false;
      type = lib.types.bool;
      description = lib.mdDoc ''
        Whether or not to enable the ChromeOS kernel partition.
      '';
    };
    boot.loader.depthcharge.kernelPart = lib.mkOption {
      default = "";
      type = lib.types.str;
      description = lib.mdDoc ''
        This file gets written to the ChromeOS kernel partition.
      '';
    };
    updateUrl = lib.mkOption {
      type = lib.types.str;
      description = lib.mdDoc ''
        URL used by systemd-sysupdate to fetch OTA updates
      '';
    };
  };

  imports = [
    (modulesPath + "/image/repart.nix")
  ];

  config = {

    image.repart = {
      name = "${config.osName}";
      split = true;
      partitions = {
        "10-chromium" = lib.mkIf config.boot.loader.depthcharge.enable {
          repartConfig = {
            Type = "FE3A2A5D-4F32-41A7-B725-ACCC3285A309"; # ChromeOS Kernel
            Label = "KERN-A";
            SizeMinBytes = "16M";
            SizeMaxBytes = "16M";
            Flags = "0b0000000100000001000000000000000000000000000000000000000000000000"; # Prority = 1, Successful = 1
            CopyBlocks = "${config.boot.loader.depthcharge.kernelPart}";
          };
        };
        "20-esp" = {
          contents = lib.mkMerge [
            {
              "/EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI".source =
                "${pkgs.systemd}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";

              "${kernelPath}".source =
                "${config.system.build.uki}/${config.system.boot.loader.ukiFile}";
            }
            (lib.mkIf config.hardware.deviceTree.enable {
            "/${config.hardware.deviceTree.name}".source =
              "${config.hardware.deviceTree.dtbSource}/${config.hardware.deviceTree.name}";
            })
          ];
          repartConfig = {
            Type = "esp";
            Format = "vfat";
            Label = "esp";
            SizeMinBytes = "96M";
          };
        };
        "30-root" = {
          storePaths = [ config.system.build.toplevel ];
          repartConfig = {
            Type = "root-${arch}";
            Label = "${version}";
            Format = "squashfs";
            Minimize = "guess";
            SplitName = "root";
            MakeDirectories = "/home /etc /var";
            SizeMaxBytes = "512M";
          };
        };
      };
    };

    system.build.release = pkgs.callPackage ./release.nix {
      inherit version;
      rootfsPath = config.system.build.image + "/${config.osName}.root.raw";
      imagePath = config.system.build.image + "/${config.osName}.raw";
      ukiPath = "${config.system.build.uki}/${config.system.boot.loader.ukiFile}";
    };
  
    boot.initrd = {
      kernelModules = [ "loop" "squashfs" "overlay" ];
      systemd.enable = true; # See https://github.com/NixOS/nixpkgs/projects/51
      systemd.additionalUpstreamUnits = ["systemd-volatile-root.service"];
      systemd.storePaths = [
        "${config.boot.initrd.systemd.package}/lib/systemd/systemd-volatile-root"
        "${pkgs.btrfs-progs}/bin/btrfs"
        "${pkgs.btrfs-progs}/bin/mkfs.btrfs"
      ];
    };

    boot.kernelParams = [
      "boot.panic_on_fail"
      "panic=5"
      "systemd.volatile=overlay"
    ];

    boot.loader.grub.enable = false;

    environment.etc."os-release".text = lib.mkAfter ''
      IMAGE_VERSION=${config.release}
      IMAGE_ID=${config.osName}
    '';

    boot.initrd.luks.devices = lib.mkIf cfg.luks.enable {
      "data" = {
        device = "${partlabelPath}/${cfg.dataLabel}";
      };
    };

    fileSystems = let
      dataDevice = if cfg.luks.enable then "/dev/mapper/data" else "${partlabelPath}/${cfg.dataLabel}";
    in {
      "/" = {
        fsType = "squashfs";
        device = "${partlabelPath}/${toString version}";
      };

      "/boot" = {
        fsType = "vfat";
        device = "${partlabelPath}/esp";
      };

      "/etc" = {
        device = dataDevice;
        options = [ "subvol=@etc" ];
      };

      "/var" = {
        device = dataDevice;
        options = [ "subvol=@var" ];
      };

      "/home" = {
        device = dataDevice;
        options = [ "subvol=@home" ];
        neededForBoot = true;
      };
    };

    systemd.repart = {
      partitions = {
        "10-root-a" = {
          Type = "root";
          SizeMinBytes = "512M";
          SizeMaxBytes = "512M";
        };

        "20-root-b" = {
          Type = "root";
          Label = "_empty";
          SizeMinBytes = "512M";
          SizeMaxBytes = "512M";
        };

        "30-data" = {
          Type = "linux-generic";
          Label = "${config.diskImage.dataLabel}";
          Format = "btrfs";
          MakeDirectories = "/@home /@etc /@var";
          Subvolumes = "/@home /@etc /@var";
          FactoryReset = true;
          Encrypt = lib.optionalString cfg.luks.enable "key-file";
        };
      };
    };

    boot.initrd.systemd.contents = {
      "/etc/default-luks-key" = lib.mkIf cfg.luks.enable {
        text = cfg.luks.defaultKey;
      };
    };

    boot.initrd.systemd.repart.enable = true;

    boot.initrd.systemd.services.systemd-repart = {
      serviceConfig = {
        Environment = [
          "PATH=${pkgs.btrfs-progs}/bin" # Help systemd-repart to find btrfs-progs
        ];
        ExecStart = [
          " "
          (lib.strings.concatStrings [ ''${config.boot.initrd.systemd.package}/bin/systemd-repart \
            --definitions=/etc/repart.d \
            --dry-run no \
          '' (lib.optionalString cfg.luks.enable " --key-file=/etc/default-luks-key") ])
        ];
      };
    };

    system.switch.enable = false;

    systemd.sysupdate = {
      enable = true;
      reboot.enable = true;

      transfers = {
        "10-rootfs" = {
          Transfer = {
            Verify = "no";
          };
          Source = {
            Type = "url-file";
            Path = "${config.updateUrl}";
            MatchPattern = "${config.osName}_@v.rootfs";
          };
          Target = {
            Type = "partition";
            MatchPartitionType = "root";
            Path = "auto";
            MatchPattern = "${config.osName}_@v";
          };
        };

        "20-uki" = {
          Transfer = {
            Verify = "no";
          };
          Source = {
            Type = "url-file";
            Path = "${config.updateUrl}";
            MatchPattern = "${config.osName}_@v.efi";
          };
          Target = {
            Type = "regular-file";
            Path = "/EFI/Linux";
            PathRelativeTo = "esp";
            # Boot counting is not supported yet, see https://github.com/NixOS/nixpkgs/pull/273062
            MatchPattern = ''
              ${config.osName}_@v.efi
            '';
            Mode = "0444";
            TriesLeft = 3;
            TriesDone = 0;
            InstancesMax = 2;
          };
        };
      };

    };

  };

}