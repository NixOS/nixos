{ config, pkgs, ... }:

with pkgs.lib;

{

  ###### interface

  options = {

    boot.blacklistedKernelModules = mkOption {
      default = [];
      example = [ "cirrusfb" "i2c_piix4" ];
      description = ''
        List of names of kernel modules that should not be loaded
        automatically by the hardware probing code.
      '';
    };

    boot.extraModprobeConfig = mkOption {
      default = "";
      example =
        ''
          options parport_pc io=0x378 irq=7 dma=1
        '';
      description = ''
        Any additional configuration to be appended to the generated
        <filename>modprobe.conf</filename>.  This is typically used to
        specify module options.  See
        <citerefentry><refentrytitle>modprobe.conf</refentrytitle>
        <manvolnum>5</manvolnum></citerefentry> for details.
      '';
    };

  };


  ###### implementation

  config = {

    environment.etc = singleton
      { source = pkgs.writeText "modprobe.conf"
          ''
            ${flip concatMapStrings config.boot.blacklistedKernelModules (name: ''
              blacklist ${name}
            '')}
            ${config.boot.extraModprobeConfig}
          '';
        target = "modprobe.d/nixos.conf";
      };

    boot.blacklistedKernelModules =
      [ # This module is for debugging and generates gigantic amounts
        # of log output, so it should never be loaded automatically.
        "evbug"

        # This module causes ALSA to occassionally select the wrong
        # default sound device, and is little more than an annoyance
        # on modern machines.
        "snd_pcsp"

        # !!! Hm, Ubuntu blacklists all framebuffer devices because
        # they're "buggy" and cause suspend problems.  Maybe we should
        # too?
      ];

    system.activationScripts.modprobe =
      # TODO: cleanup old symlinks
      let
        version = config.boot.kernelPackages.kernel.modDirVersion;
        inherit (config.system) modulesTree;
        src = "${modulesTree}${dest}";
        dest = "/lib/modules/${version}";
      in
      ''
        mkdir -p /lib/modules
        ln -sfn ${src} ${dest}.tmp
        mv -T -f ${dest}.tmp ${dest}
        ls -l ${dest}
        echo ${pkgs.kmod}/sbin/modprobe > /proc/sys/kernel/modprobe
      '';
  };

}
