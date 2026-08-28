{pkgs, ...}: let
  compiled = {
    central.text = "test: true\n";
    publicNode = {
      value = {
        id = "exit";
        interface_name = "nylon0";
        mtu = 1400;
        port = 6622;
      };
      text = "test: true\n";
    };
    expectedPublicKey = "ynMTsT/6Is4mNsYAYp5nR98LEuUSz3AkwOCvMkT5fj8=";
    exits = {
      public = {
        label = 100;
        interface = "wan0";
        families = {
          ipv4 = true;
          ipv6 = false;
        };
        useDefaultRoute = false;
        gateway4 = null;
        ipv4Address = "192.0.2.2";
        ipv6Address = null;
      };
      direct = {
        label = 101;
        interface = "p2p0";
        families = {
          ipv4 = true;
          ipv6 = false;
        };
        useDefaultRoute = false;
        gateway4 = null;
        ipv4Address = "198.51.100.2";
        ipv6Address = null;
      };
    };
    cloudflareWarp = null;
    selector = {
      enable = false;
      rules = {
        ipv4 = [];
        ipv6 = [];
      };
      routes = {
        ipv4 = [];
        ipv6 = [];
      };
      ownedTables = [];
      wlt.text = "";
    };
  };
in {
  name = "nylon-exit";

  nodes.exit = {
    lib,
    pkgs,
    ...
  }: {
    imports = [../nylon/module.nix];

    options.age.secrets = lib.mkOption {
      default = {};
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          file = lib.mkOption {type = lib.types.path;};
          path = lib.mkOption {type = lib.types.str;};
        };
      });
    };
    config = {
      age.secrets.nylon-private-key = {
        file = pkgs.writeText "nylon-private-key.age" "test fixture\n";
        path = "/etc/nylon-private-key";
      };
      environment.etc.nylon-private-key.text = "test fixture\n";

      networking.useNetworkd = true;
      systemd.network.networks."10-ra-test" = {
        matchConfig.Name = "eth1";
        networkConfig.IPv6AcceptRA = true;
      };

      services.nylon = {
        enable = true;
        inherit compiled;
        privateKeyFile = "/etc/nylon-private-key";
      };

      systemd.services = {
        prepare-nylon-exit-test = {
          before = ["nylon.service"];
          requiredBy = ["nylon.service"];
          path = [pkgs.iproute2];
          serviceConfig.Type = "oneshot";
          script = ''
            ip link add nylon0 type dummy
            ip link set nylon0 up

            ip link add wan0 type dummy
            ip address add 192.0.2.2/24 dev wan0
            ip link set wan0 up
            ip route add default via 192.0.2.1 dev wan0 metric 4096

            ip tuntap add dev p2p0 mode tun
            ip address add 198.51.100.2 peer 198.51.100.1 dev p2p0
            ip link set p2p0 up
          '';
        };

        nylon.serviceConfig = {
          ExecStartPre = lib.mkForce [];
          ExecStart = lib.mkForce "${pkgs.coreutils}/bin/sleep infinity";
        };
      };
    };
  };

  nodes.gateway = {
    boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = true;
    networking = {
      firewall.enable = false;
      interfaces.eth1.ipv6.addresses = [
        {
          address = "2001:db8::1";
          prefixLength = 64;
        }
      ];
    };
    services.radvd = {
      enable = true;
      config = ''
        interface eth1 {
          AdvSendAdvert on;
          MinRtrAdvInterval 3;
          MaxRtrAdvInterval 4;
          prefix 2001:db8::/64 { };
        };
      '';
    };
  };

  testScript = ''
    start_all()
    gateway.wait_for_unit("radvd.service")
    exit.wait_for_unit("nylon-exit.service")
    exit.succeed("sysctl -n net.ipv4.conf.all.forwarding | grep -Fx 1")
    exit.succeed("sysctl -n net.ipv6.conf.all.forwarding | grep -Fx 1")
    exit.succeed("grep -Fx 'IPv6AcceptRA=true' /etc/systemd/network/10-ra-test.network")
    exit.wait_until_succeeds("ip -6 route show default dev eth1 proto ra | grep -F default")
    exit.succeed("ip -f mpls route show 100 | grep -F 'via inet 192.0.2.1 dev wan0'")
    exit.succeed("ip -f mpls route show 101 | grep -F 'dev p2p0'")
    exit.fail("ip -f mpls route show 101 | grep -F 'via inet'")
  '';
}
