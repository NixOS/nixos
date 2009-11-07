{options, config, pkgs, ...}:

let
  inherit (pkgs.lib) mkOption addDefaultOptionValues types;

  mainServerArgs = {
    config = config.services.httpd;
    options = options.services.httpd;
  };

  subServiceOptions = {options, config, ...}: {
    options = {

      extraConfig = mkOption {
        default = "";
        description = "see host config.";
      };

      extraModules = mkOption {
        default = [];
        description = "see services.httpd.extraModules";
      };

      extraModulesPre = mkOption {
        default = [];
        description = "see services.httpd.extraModulesPre";
      };

      extraPath = mkOption {
        default = [];
        description = "see environment.systemPackages";
      };

      extraServerPath = mkOption {
        default = [];
        description = "see jobs.httpd.environment.PATH";
      };

      globalEnvVars = mkOption {
        default = [];
        description = "see jobs.httpd.environment";
      };

      robotsEntries = mkOption {
        default = "";
        description = "see host robotEntries.";
      };

      startupScript = mkOption {
        default = "";
        description = "see jobs.httpd.preStart";
      };


      serviceType = mkOption {
        description = "Obsolete name of <option>serviceName</option>.";
        # serviceType is the old name of serviceName.
        apply = x: config.serviceName;
      };

      serviceName = mkOption {
        example = "trac";
        description = "
          (Deprecated)

          Identify a service by the name of the file containing it.  The
          service expression is contained inside
          <filename>./modules/services/web-servers/apache-httpd</filename>
          directory.

          Due to lack of documentation, this option will be replaced by
          enable flags.
        ";

        # serviceName is the new name of serviceType.
        extraConfigs = map (def: def.value) options.serviceType.definitions;
      };

      function = mkOption {
        default = null;
        description = "
          (Deprecated) Add a function which configure the current sub-service.
        ";
        apply = f:
          if isNull f then
            import "${./.}/${config.serviceName}.nix"
          else
            f;
      };

      configuration = mkOption {
        default = {};
        description = "
          (Deprecated) Define option values of the current sub-service.
        ";
      };

    };
  };


  perServerOptions = {config, ...}: {

    extraSubservices = mkOption {
      default = [];
      type = with types; listOf optionSet;
      description = "
        Extra subservices to enable in the webserver.
      ";
      options = [ subServiceOptions ];
    };

  };

in

{
  options = {
    services.httpd = {

      virtualHosts = mkOption {
        options = [ perServerOptions ];
      };

    }
    // perServerOptions mainServerArgs
    ;
  };
}
