{ config, pkgs, ... }:

with pkgs.lib;

let
  # usual shortcuts.
  httpd = config.services.httpd;
  allHosts = filter (h: h.subversion.enable) (attrValues httpd.hosts);
  foreachHost = f: map f allHosts;

  # Build a Subversion instance with Apache modules and Swig/Python bindings.
  subversion = pkgs.subversion.override (origArgs: {
    bdbSupport = true;
    httpServer = true;
    sslSupport = true;
    compressionSupport = true;
    pythonBindings = true;
  });

  trac = pkgs.pythonPackages.trac;

  createTracProject = project: ''
    if [ ! -d /var/trac/${project.identifier} ]; then
      ${trac}/bin/trac-admin /var/trac/${project.identifier} initenv "${project.name}" "${project.databaseURL}" svn "${project.subversionRepository}"
    fi
  '';

  serviceModule = {config, ...}: {
    options = {
      trac = {
        enable = mkOption {
          default = false;
          type = with types; bool;
          description = "
            Enable a Trac interface for the host.
          ";
        };

        projectsLocation = mkOption {
          default = "/projects";
          description = "
            URL path in which Trac projects can be accessed
          ";
        };

        # !!! These should be enhanced in order to setup a postgres database
        # when the database URL is not provided and so on.
        projects = mkOption {
          default = [];
          example = [
            { identifier = "myproject";
              name = "My Project";
              databaseURL="postgres://root:password@/tracdb";
              subversionRepository="/data/subversion/myproject";
            }
          ];
          description = "
            List of projects that should be provided by Trac. If they are
            not defined yet empty projects are created.
          ";
        };
        
        user = mkOption {
          default = httpd.user;
          description = "
            User account under which Trac runs.  By default this is the user
            of the httpd server. (see <option>services.httpd.user</option>)

            The account is not created automatically.
          ";
        };

        group = mkOption {
          default = httpd.group;
          description = "
            Group under which Trac runs.  By default this is the group of
            the httpd server. (see <option>services.httpd.group</option>)

            The group is not created automatically.
          ";
        };
      };
    };

    config = mkIf config.trac.enable {
      extraConfig = ''
        <Location ${config.trac.projectsLocation}>
          SetHandler mod_python
          PythonHandler trac.web.modpython_frontend
          PythonOption TracEnvParentDir /var/trac/projects
          PythonOption TracUriRoot ${config.trac.projectsLocation}
          PythonOption PYTHON_EGG_CACHE /var/trac/egg-cache
        </Location>
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

  config = mkIf (allHosts != []) {

    jobs.httpd = {

      environment.PYTHONPATH =
        "${pkgs.mod_python}/lib/python2.5/site-packages:" +
        "${pkgs.pythonPackages.trac}/lib/python2.5/site-packages:" +
        "${pkgs.setuptools}/lib/python2.5/site-packages:" +
        "${pkgs.pythonPackages.genshi}/lib/python2.5/site-packages:" +
        "${pkgs.pythonPackages.psycopg2}/lib/python2.5/site-packages:" +
        "${subversion}/lib/python2.5/site-packages";

      # Use preStart merge function instead of the usual copy&paste pattern.
      preStart = ''
        mkdir -p /var/trac
        chown ${config.trac.user}:${config.trac.group} /var/trac

        ${concatMapStrings
            (h: concatMapStrings createTracProject h.trac.projects)
            allHosts
        }
      '';

    };

    services.httpd.extraModules = [
      { name = "python"; path = "${pkgs.mod_python}/modules/mod_python.so"; }
    ];

  };
}