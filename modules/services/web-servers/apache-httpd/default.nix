{ config, pkgs, servicesPath, ... }:

with pkgs.lib;

let

  mainCfg = config.services.httpd;
  mainHost = mainCfg.hosts.main;
  allHosts = attrValues mainCfg.hosts;

  isMainServer = cfg: mainHost._args.name == cfg._args.name;
  vhosts = filter (cfg: ! isMainServer cfg) allHosts;


  startingDependency = if config.services.gw6c.enable then "gw6c" else "network-interfaces";

  httpd = pkgs.apacheHttpd;

  getPort = cfg: cfg.port;

  # !!! keep it as a memo (dead code)
  makeServerInfo = cfg: {
    inherit (cfg) canonicalName adminAddr;

    vhostConfig = cfg;
    serverConfig = mainCfg;
    fullConfig = config; # machine config
  };



  # !!! should be in lib
  writeTextInDir = name: text:
    pkgs.runCommand name {inherit text;} "ensureDir $out; echo -n \"$text\" > $out/$name";


  # Names of modules from ${httpd}/modules that we want to load.
  apacheModules =
    [ # HTTP authentication mechanisms: basic and digest.
      "auth_basic" "auth_digest"

      # Authentication: is the user who he claims to be?
      "authn_file" "authn_dbm" "authn_anon" "authn_alias"

      # Authorization: is the user allowed access?
      "authz_user" "authz_groupfile" "authz_host"

      # Other modules.
      "ext_filter" "include" "log_config" "env" "mime_magic"
      "cern_meta" "expires" "headers" "usertrack" /* "unique_id" */ "setenvif"
      "mime" "dav" "status" "autoindex" "asis" "info" "cgi" "dav_fs"
      "vhost_alias" "negotiation" "dir" "imagemap" "actions" "speling"
      "userdir" "alias" "rewrite" "proxy" "proxy_http"
    ];

  # list of all modules which have to be loaded.
  allModules =
    let
      httpdModule = name: {
        inherit name;
        path = "${httpd}/modules/mod_${name}.so";
      };

      convert = mod: with builtins;
        if isAttrs mod then mod
        else if isString mod then httpdModule mod
        else throw "Bad module syntax.";
    in
      map convert (
        mainCfg.extraModulesPre ++
        apacheModules ++
        mainCfg.extraModules
      );


  loggingConf = ''
    ErrorLog ${mainCfg.logDir}/error_log

    LogLevel notice

    LogFormat "%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\"" combined
    LogFormat "%h %l %u %t \"%r\" %>s %b" common
    LogFormat "%{Referer}i -> %U" referer
    LogFormat "%{User-agent}i" agent

    CustomLog ${mainCfg.logDir}/access_log ${mainCfg.logFormat}
  '';


  browserHacks = ''
    BrowserMatch "Mozilla/2" nokeepalive
    BrowserMatch "MSIE 4\.0b2;" nokeepalive downgrade-1.0 force-response-1.0
    BrowserMatch "RealPlayer 4\.0" force-response-1.0
    BrowserMatch "Java/1\.0" force-response-1.0
    BrowserMatch "JDK/1\.0" force-response-1.0
    BrowserMatch "Microsoft Data Access Internet Publishing Provider" redirect-carefully
    BrowserMatch "^WebDrive" redirect-carefully
    BrowserMatch "^WebDAVFS/1.[012]" redirect-carefully
    BrowserMatch "^gnome-vfs" redirect-carefully
  '';


  sslConf = ''
    SSLSessionCache dbm:${mainCfg.stateDir}/ssl_scache

    SSLMutex file:${mainCfg.stateDir}/ssl_mutex

    SSLRandomSeed startup builtin
    SSLRandomSeed connect builtin
  '';


  mimeConf = ''
    TypesConfig ${httpd}/conf/mime.types

    AddType application/x-x509-ca-cert .crt
    AddType application/x-pkcs7-crl    .crl
    AddType application/x-httpd-php    .php .phtml

    <IfModule mod_mime_magic.c>
        MIMEMagicFile ${httpd}/conf/magic
    </IfModule>

    AddEncoding x-compress Z
    AddEncoding x-gzip gz tgz
  '';




  
  httpdConf = pkgs.writeText "httpd.conf" ''
  
    ServerRoot ${httpd}

    PidFile ${mainCfg.stateDir}/httpd.pid

    <IfModule prefork.c>
        MaxClients           150
        MaxRequestsPerChild  0
    </IfModule>

    ${let
        ports = map getPort allHosts;
        uniquePorts = uniqList {inputList = ports;};
      in concatMapStrings (port: "Listen ${toString port}\n") uniquePorts
    }

    User ${mainCfg.user}
    Group ${mainCfg.group}

    ${let
        load = {name, path}: "LoadModule ${name}_module ${path}\n";
      in concatMapStrings load allModules
    }

    AddHandler type-map var

    <Files ~ "^\.ht">
        Order allow,deny
        Deny from all
    </Files>

    ${mimeConf}
    ${loggingConf}
    ${browserHacks}

    Include ${httpd}/conf/extra/httpd-default.conf
    Include ${httpd}/conf/extra/httpd-autoindex.conf
    Include ${httpd}/conf/extra/httpd-multilang-errordoc.conf
    Include ${httpd}/conf/extra/httpd-languages.conf
    
    ${# you cannot rely on hosts enableSSL because it can be bypass.
      let hasMod = name: any (mod: name == mod.name); in
      optionalString (hasMod "ssl" allModules) sslConf
    }

    # Fascist default - deny access to everything.
    <Directory />
        Options FollowSymLinks
        AllowOverride None
        Order deny,allow
        Deny from all
    </Directory>

    # But do allow access to files in the store so that we don't have
    # to generate <Directory> clauses for every generated file that we
    # want to serve.
    <Directory /nix/store>
        Order allow,deny
        Allow from all
    </Directory>

    # Generate directives for the main server.
    ${mainHost.serverConfig}
    
    # Always enable virtual hosts; it doesn't seem to hurt.
    ${let
        ports = map getPort allHosts;
        uniquePorts = uniqList {inputList = ports;};
      in concatMapStrings (port: "NameVirtualHost *:${toString port}\n") uniquePorts
    }

    ${let
        makeVirtualHost = vhost: ''
          <VirtualHost *:${toString vhost.port}>
              ${vhost.serverConfig}
          </VirtualHost>
        '';
      in concatMapStrings makeVirtualHost vhosts
    }
  '';

    
in


{

  ###### interface

  options = {
  
    services.httpd = {
      
      enable = mkOption {
        default = false;
        description = "
          Whether to enable the Apache httpd server.
        ";
      };

      extraModulesPre = mkOption {
        default = [];
        description = ''
          Specifies additional Apache modules which are loaded before Apache
          modules.  These can be specified as a string in the case of
          modules distributed with Apache, or as an attribute set specifying
          the <varname>name</varname> and <varname>path</varname> of the
          module (see <option>extraModules</option>).
        '';
      };

      extraModules = mkOption {
        default = [];
        example = [ "proxy_connect" { name = "php5"; path = "${pkgs.php}/modules/libphp5.so"; } ];
        description = ''
          Specifies additional Apache modules which are loaded after Apache
          modules.  These can be specified as a string in the case of
          modules distributed with Apache, or as an attribute set specifying
          the <varname>name</varname> and <varname>path</varname> of the
          module.
        '';
      };

      logPerVirtualHost = mkOption {
        default = false;
        description = "
          If enabled, each virtual host gets its own
          <filename>access_log</filename> and
          <filename>error_log</filename>, namely suffixed by the
          <option>hostName</option> of the virtual host.
        ";
      };

      user = mkOption {
        default = "wwwrun";
        description = "
          User account under which httpd runs.  The account is created
          automatically if it doesn't exist.
        ";
      };

      group = mkOption {
        default = "wwwrun";
        description = "
          Group under which httpd runs.  The account is created
          automatically if it doesn't exist.
        ";
      };

      logDir = mkOption {
        default = "/var/log/httpd";
        description = "
          Directory for Apache's log files.  It is created automatically.
        ";
      };

      logFormat = mkOption {
        default = "common";
        example = "combined";
        description = "
          Log format for Apache's log files. Possible values are: combined, common, referer, agent.
        ";
      };

      stateDir = mkOption {
        default = "/var/run/httpd";
        description = "
          Directory for Apache's transient runtime state (such as PID
          files).  It is created automatically.  Note that the default,
          <filename>/var/run/httpd</filename>, is deleted at boot time.
        ";
      };

    };

  };


  ###### implementation

  config = mkIf config.services.httpd.enable {

    users.extraUsers = singleton
      { name = mainCfg.user;
        description = "Apache httpd user";
      };

    users.extraGroups = singleton
      { name = mainCfg.group;
      };

    environment.systemPackages = [httpd];

    jobs.httpd =
      { # Statically verify the syntactic correctness of the generated
        # httpd.conf.  !!! this is impure!  It doesn't just check for
        # syntax, but also whether the Apache user/group exist,
        # whether SSL keys exist, etc.
        buildHook =
          ''
            echo
            echo '=== Checking the generated Apache configuration file ==='
            ${httpd}/bin/httpd -f ${httpdConf} -t || true
          '';

        description = "Apache HTTPD";

        startOn = "${startingDependency}/started";
        stopOn = "shutdown";

        environment = mkHeader
          { # !!! This should be added in test-instrumentation.nix.  It
            # shouldn't hurt though, since packages usually aren't built
            # with coverage enabled.
           GCOV_PREFIX = "/tmp/coverage-data";

           PATH = "${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin";
          };

        preStart = mkHeader
          ''
            mkdir -m 0700 -p ${mainCfg.stateDir}
            mkdir -m 0700 -p ${mainCfg.logDir}

            # Get rid of old semaphores.  These tend to accumulate across
            # server restarts, eventually preventing it from restarting
            # succesfully.
            for i in $(${pkgs.utillinux}/bin/ipcs -s | grep ' ${mainCfg.user} ' | cut -f2 -d ' '); do
                ${pkgs.utillinux}/bin/ipcrm -s $i
            done
          '';

        exec = "${httpd}/bin/httpd -f ${httpdConf} -DNO_DETACH";
      };

  };
  
}

