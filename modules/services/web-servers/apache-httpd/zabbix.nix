{ config, pkgs, serverInfo, ... }:

with pkgs.lib;

let
  # usual shortcuts.
  httpd = config.services.httpd;
  allHosts = filter (h: h.zabbix.enable) (attrValues httpd.hosts);
  foreachHost = f: map f allHosts;

  serviceModule = {config, ...}: let

    # The Zabbix PHP frontend needs to be able to write its
    # configuration settings (the connection info to the database) to
    # the "conf" subdirectory.  So symlink $out/conf to some directory
    # outside of the Nix store where we want to keep this stateful info.
    # Note that different instances of the frontend will therefore end
    # up with their own copies of the PHP sources.  !!! Alternatively,
    # we could generate zabbix.conf.php declaratively.
    zabbixPHP = pkgs.runCommand "${pkgs.zabbixServer.name}-php" {} ''
      cp -rs ${pkgs.zabbixServer}/share/zabbix/php $out
      chmod -R u+w $out
      #rm -rf $out/conf
      ln -s ${config.zabbix.stateDir}/zabbix.conf.php $out/conf/zabbix.conf.php
    '';

  in {

    options = {
      zabbix = {
        enable = mkOption {
          default = false;
          type = with types; bool;
          description = "
            Enable the Zabbix web interface of the monitoring system.
          ";
        };

        urlPrefix = mkOption {
          default = "/zabbix";
          description = "
            The URL prefix under which the Zabbix service appears.
            Use the empty string to have it appear in the server root.
          ";
        };

        stateDir = mkOption {
          default = "/var/lib/zabbix/frontend";
          description = "
            Directory where the dynamically generated configuration data
            of the PHP frontend will be stored.
          ";
        };

      };
    };

    config = mkIf config.zabbix.enable {

      # !!! should also declare PHP options that Zabbix needs like the
      # timezone and timeout.

      extraConfig = ''
        Alias ${config.zabbix.urlPrefix}/ ${zabbixPHP}/
        
        <Directory ${zabbixPHP}>
          DirectoryIndex index.php
          Order deny,allow
          Allow from *
        </Directory>
      '';

    };

  };

  startupScript = config: ''
    mkdir -p ${config.zabbix.stateDir}
    chown -R ${httpd.user} ${config.zabbix.stateDir}
  '';

in

{
  options = {
    services.httpd.hosts = mkOption {
      options = [ serviceModule ];
    };
  };

  config = mkIf (allHosts != []) {

    jobs.httpd = {options, ...}: {

      # The frontend needs "ps" to find out whether zabbix_server is running.
      environment.PATH = "${pkgs.procps}/bin";

      preStart = options.preStart.merge (
        foreachHost startupScript
      );

    };

    services.httpd.extraModules = [
      { name = "php5"; path = "${pkgs.php}/modules/libphp5.so"; }
    ];

  };
}
