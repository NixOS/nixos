{ nixos ? ./..
, nixpkgs ? /etc/nixos/nixpkgs
, services ? /etc/nixos/services
, system ? builtins.currentSystem
}:

with import ../lib/build-vms.nix { inherit nixos nixpkgs services system; };

rec {
  nodes = {

    webserver =
      {config, pkgs, ...}:
      {
        services.httpd.enable = true;
        services.httpd.hosts.main = {
          adminAddr = "root@localhost";
          twiki.enable = true;
          twiki.startWeb = "NixOS/WebHome";
          twiki.name = "NixOS TWiki";
          twiki.registrationDomain = "all";
          twiki.dataDir = "/data/twiki/data";
          twiki.pubDir = "/data/twiki/pub";
        };
      };

    client =
      {config, pkgs, ...}:
      {
        services.xserver.enable = true;
        services.xserver.displayManager.slim.enable = false;
        services.xserver.displayManager.kdm.enable = true;
        services.xserver.displayManager.kdm.extraConfig =
          ''
            [X-:0-Core]
            AutoLoginEnable=true
            AutoLoginUser=alice
            AutoLoginPass=foobar
          '';
        services.xserver.desktopManager.default = "kde4";
        services.xserver.desktopManager.kde4.enable = true;
        users.extraUsers = pkgs.lib.singleton {
          name = "alice";
          description = "Alice Foobar";
          home = "/home/alice";
          createHome = true;
          useDefaultShell = true;
          password = "foobar";
        };
        environment.systemPackages = [ pkgs.scrot ];
      };
  };

  vms = buildVirtualNetwork { inherit nodes; };

  test = runTests vms
    ''
      startAll;

      # setup the TWiki webserver.
      # $webserver->mustSucceed("mkdir -p /data/wiki/data");

      $client->waitForFile("/tmp/.X11-unix/X0");
      sleep 60;

      print STDERR $client->execute("su - alice -c 'DISPLAY=:0.0 konqueror http://webserver/ &'");
      sleep 120;

      print STDERR $client->execute("DISPLAY=:0.0 scrot /hostfs/$ENV{out}/screen1.png");
    '';
}
