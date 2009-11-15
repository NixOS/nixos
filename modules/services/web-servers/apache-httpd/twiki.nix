{ config, pkgs, servicesPath, ... }:

let
  inherit (pkgs.lib) mkOption mkIf mkFixStrictness types;

  serviceModule = {config, ...}: let

    inherit (config.twiki) dataDir pubDir startWeb enable registrationDomain;

    scriptUrlPath = "/bin";
    pubUrlPath    = "/pub";
    absHostPath   = "/";

    # Hacks for proxying and rewriting
    dispPubUrlPath    = "/pub";
    dispScriptUrlPath = "";
    dispViewPath      = "";

    defaultUrlHost = "";

    # Build the TWiki CGI and configuration files.
    twikiRoot = (import (servicesPath + /twiki/twiki-instance.nix)).twiki {
      name = "wiki-instance";

      inherit scriptUrlPath pubUrlPath absHostPath dispPubUrlPath
        dispScriptUrlPath dispViewPath defaultUrlHost registrationDomain;

      twikiName = config.twiki.name;
      pubdir = pubDir;
      datadir = dataDir;
    };

    plugins = import (servicesPath + /twiki/server-pkgs/twiki-plugins.nix);

  in {

    options = {
      twiki.enable = mkOption {
        default = false;
        type = with types; bool;
        description = "
          Enable a TWiki wiki.
        ";
      };

      twiki.dataDir = mkOption {
        example = "/data/wiki/data";
        description = "
          Path to the directory that holds the Wiki data.
        ";
      };

      twiki.pubDir = mkOption {
        example = "/data/wiki/pub";
        description = "
          Path to the directory that holds uploaded files.
        ";
      };

      twiki.name = mkOption {
        default = "Wiki";
        example = "Foobar Wiki";
        description = "
          Name of this Wiki.
        ";
      };

      twiki.startWeb = mkOption {
        example = "MyProject/WebHome";
        description = "
          Where users are redirected when they enter your domain name.
        ";
      };

      twiki.registrationDomain = mkOption {
        example = "example.org";
        description = "
          Domain from which registrations are permitted.  Use `all' to
          permit registrations from anywhere.
        ";
      };

      twiki.customRewriteRules = mkOption {
        default = "";
        example = ''
          RewriteRule ^index.php$            bin/view/MyProject/WebHome [L]
        '';
        description = "
          These lines go to httpd.conf verbatim. They are used to rewrite
          the demanded address.
        ";
      };

    };

    config = mkIf enable {

      extraConfig = mkFixStrictness ''

        ScriptAlias ${scriptUrlPath} "${twikiRoot}/bin"
        Alias ${pubUrlPath} "${pubDir}"

        <Directory "${twikiRoot}/bin">
           Options +ExecCGI
           SetHandler cgi-script
           AllowOverride All
           Allow from all
        </Directory>
        <Directory "${twikiRoot}/templates">
           deny from all
        </Directory>
        <Directory "${twikiRoot}/lib">
           deny from all
        </Directory>
        <Directory "${pubDir}">
           Options None
           AllowOverride None
           Allow from all
           # Hardening suggested by http://twiki.org/cgi-bin/view/Codev/SecurityAlertSecureFileUploads.
           php_admin_flag engine off
           AddType text/plain .html .htm .shtml .php .php3 .phtml .phtm .pl .py .cgi
        </Directory>
        <Directory "${dataDir}">
           deny from all
        </Directory>

        Alias ${absHostPath} ${twikiRoot}/rewritestub/

        <Directory "${twikiRoot}/rewritestub">
          RewriteEngine On
          RewriteBase ${absHostPath}

          # complete bin path
          RewriteRule ^bin(.*)  bin/$1 [L]

          ${config.twiki.customRewriteRules}

          # Hack for restricted webs.
          RewriteRule ^pt/(.*)  $1

          # action / web / whatever
          RewriteRule ^([a-z]+)/([A-Z][^/]+)/(.*)  bin/$1/$2/$3 [L]

          # web / topic
          RewriteRule ^([A-Z][^/]+)/([^/]+)   bin/view/$1/$2 [L]

          # web
          RewriteRule ^([A-Z][^/]+)           bin/view/$1/WebHome [L]

          # web/
          RewriteRule ^([A-Z][^/]+)/          bin/view/$1/WebHome [L]

          RewriteRule ^index.html$            bin/view/${startWeb} [L]

          RewriteRule ^$                      bin/view/${startWeb} [L]
        </Directory>

      '';

      robotsEntries = ''
        User-agent: *
        Disallow: /rdiff/
        Disallow: /rename/
        Disallow: /edit/
        Disallow: /bin/
        Disallow: /oops/
        Disallow: /view/
        Disallow: /search/
        Disallow: /attach/
        Disallow: /pt/bin/
      '';

    };
  };

in

{
  options = {
    services.httpd.hosts = mkOption {
      options = [ serviceModule ];
    };
  };
}
