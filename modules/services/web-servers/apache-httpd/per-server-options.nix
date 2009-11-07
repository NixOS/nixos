# This file defines the options that can be used both for the Apache
# main server configuration, and for the virtual hosts.  (The latter
# has additional options that affect the web server as a whole, like
# the user/group to run under.)

{options, config, pkgs, ...}:

with pkgs.lib;

let
  httpd = config.services.httpd;
  mainHost = httpd.hosts.main;
  allHosts = attrValues httpd.hosts;

  enableSSL = any (vhost: vhost.enableSSL) allHosts;


  isMainServer = {name, ...}:
    mainHost._args.name == name;

  inheritAsDefault = {config, options, ...}: opt:
    pkgs.lib.optionalAttrs
      (pkgs.lib.getAttr opt options).isDefined
      { default = pkgs.lib.getAttr opt config; };

  inheritDefaultFromMainServer = this: opt:
    pkgs.lib.optionalAttrs (! isMainServer this)
      (inheritAsDefault mainHost._args opt);

  perServerConfig = {name, config, ...}@args: let

    subservices = config.extraSubservices;

    documentRoot = if config.documentRoot != null then config.documentRoot else
      pkgs.runCommand "empty" {} "ensureDir $out";

    documentRootConf = ''
      DocumentRoot "${documentRoot}"

      <Directory "${documentRoot}">
          Options Indexes FollowSymLinks
          AllowOverride None
          Order allow,deny
          Allow from all
      </Directory>
    '';

    robotsTxt = pkgs.writeText "robots.txt" config.robotsEntries;

    robotsConf = ''
      Alias /robots.txt ${robotsTxt}
    '';

  in ''
    ServerName ${config.canonicalName}

    ${concatMapStrings (alias: "ServerAlias ${alias}\n") config.serverAliases}

    ${if config.sslServerCert != "" then ''
      SSLCertificateFile ${config.sslServerCert}
      SSLCertificateKeyFile ${config.sslServerKey}
    '' else ""}
    
    ${if config.enableSSL then ''
      SSLEngine on
    '' else if enableSSL then /* i.e., SSL is enabled for some host, but not this one */
    ''
      SSLEngine off
    '' else ""}

    ${if isMainServer args || config.adminAddr != "" then ''
      ServerAdmin ${config.adminAddr}
    '' else ""}

    ${if !isMainServer args && httpd.logPerVirtualHost then ''
      ErrorLog ${httpd.logDir}/error_log-${config.hostName}
      CustomLog ${httpd.logDir}/access_log-${config.hostName} ${httpd.logFormat}
    '' else ""}

    ${robotsConf}

    ${if isMainServer args || config.documentRoot != null then documentRootConf else ""}

    ${if config.enableUserDir then ''
    
      UserDir public_html
      UserDir disabled root
      
      <Directory "/home/*/public_html">
          AllowOverride FileInfo AuthConfig Limit Indexes
          Options MultiViews Indexes SymLinksIfOwnerMatch IncludesNoExec
          <Limit GET POST OPTIONS>
              Order allow,deny
              Allow from all
          </Limit>
          <LimitExcept GET POST OPTIONS>
              Order deny,allow
              Deny from all
          </LimitExcept>
      </Directory>
      
    '' else ""}

    ${if config.globalRedirect != "" then ''
      RedirectPermanent / ${config.globalRedirect}
    '' else ""}

    ${
      let makeFileConf = elem: ''
            Alias ${elem.urlPath} ${elem.file}
          '';
      in concatMapStrings makeFileConf config.servedFiles
    }

    ${
      let makeDirConf = elem: ''
            Alias ${elem.urlPath} ${elem.dir}/
            <Directory ${elem.dir}>
                Options +Indexes
                Order allow,deny
                Allow from all
                AllowOverride All
            </Directory>
          '';
      in concatMapStrings makeDirConf config.servedDirs
    }

    ${config.extraConfig}
  '';

  perServerOptions = {name, config, options, ...}@args: {

    hostName = mkOption {
      default = "localhost";
      description = "
        Canonical hostname for the server.
      ";
    };

    serverAliases = mkOption {
      default = [];
      example = ["www.example.org" "www.example.org:8080" "example.org"];
      description = "
        Additional names of virtual hosts served by this virtual host configuration.
      ";
    };

    port = mkOption {
      default = if config.enableSSL then 443 else 80;
      type = with types; uniq int;
      description = "
        Port for the server.  The default port depends on the
        <option>enableSSL</option> option of this server. (80 for http and
        443 for https).
      ";
    };

    canonicalName = mkOption {
      default = with pkgs.lib;
        (if config.enableSSL then "https" else "http") + "://" +
        config.hostName +
        optionalString options.port.isDefined ":${toString config.port}";
      type = with types; none string;
      description = "
        Canonical name of the host.
      ";
    };

    enableSSL = mkOption {
      default = false;
      description = "
        Whether to enable SSL (https) support.
      ";
    };

    # Note: sslServerCert and sslServerKey can be left empty, but this
    # only makes sense for virtual hosts (they will inherit from the
    # main server).
    
    sslServerCert = mkOption {
      default = ""; 
      example = "/var/host.cert";
      description = "
        Path to server SSL certificate.
      ";
    };

    sslServerKey = mkOption {
      default = "";
      example = "/var/host.key";
      description = "
        Path to server SSL certificate key.
      ";
    };

    adminAddr = mkOption ({
      example = "admin@example.org";
      description = "
        E-mail address of the server administrator.
      ";
    } // inheritDefaultFromMainServer args "adminAddr");

    documentRoot = mkOption {
      default = null;
      example = "/data/webserver/docs";
      description = "
        The path of Apache's document root directory.  If left undefined,
        an empty directory in the Nix store will be used as root.
      ";
    };

    servedDirs = mkOption {
      default = [];
      example = [
        { urlPath = "/nix";
          dir = "/home/eelco/Dev/nix-homepage";
        }
      ];
      description = "
        This option provides a simple way to serve static directories.
      ";
    };

    servedFiles = mkOption {
      default = [];
      example = [
        { urlPath = "/foo/bar.png";
          file = "/home/eelco/some-file.png";
        }
      ];
      description = "
        This option provides a simple way to serve individual, static files.
      ";
    };

    robotsEntries = mkOption {
      default = "";
      type = with types; string;
      description = "
        List of rules located inside the robots.txt file which will appear
        as being at the document root.  This option is useful for services
        to restrict access to private directories.

        All main host rules are append at the end of the rules defined for
        this host except if this host is the main host.
      ";
      merge = pkgs.lib.concatStringsSep "\n";
      apply = robotsEntries: ''
        ${robotsEntries}
        ${pkgs.lib.optionalString (!isMainServer args) mainHost.robotsEntries}
      '';
    };

    extraConfig = mkOption {
      default = "";
      example = ''
        <Directory /home>
          Options FollowSymlinks
          AllowOverride All
        </Directory>
      '';
      description = "
        These lines go to httpd.conf verbatim. They will go after
        directories and directory aliases defined by default.
      ";
    };

    enableUserDir = mkOption {
      default = false;
      description = "
        Whether to enable serving <filename>~/public_html</filename> as
        <literal>/~<replaceable>username</replaceable></literal>.
      ";
    };

    globalRedirect = mkOption {
      default = "";
      example = http://newserver.example.org/;
      description = "
        If set, all requests for this host are redirected permanently to
        the given URL.
      ";
    };

    serverConfig = mkOption {
      default = "";
      description = "
        If set, it overrides the default configuration computed from other
        options.
      ";
      apply = conf:
        if conf == "" then
          perServerConfig args
        else
          conf;
    };

  };

in

{
  options = {
    services.httpd = {

      hosts = mkOption {
        default = {};
        example = {
          foo = {
            hostName = "foo";
            documentRoot = "/data/webroot-foo";
          };
          bar = {
            hostName = "bar";
            documentRoot = "/data/webroot-bar";
          };
        };
        type = with types; attrsOf optionSet;
        description = ''
          Attribute set of hosts.  All hosts are virtual hosts except one
          which should be referenced inside
          <option>services.httpd.mainHosts</option> which is the main host.
        '';

        options = [ perServerOptions ];
      };

    };
  };

  config = {
    services.httpd.extraModules = mkIf enableSSL [
      "ssl"
    ];

    # Add the main server.
    services.httpd.hosts.main = {};
  };
}
