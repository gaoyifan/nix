{inputs}: {
  name = "home-router";

  node.specialArgs = {inherit inputs;};

  nodes.router = {
    config,
    lib,
    pkgs,
    ...
  }: let
    exerciseTopology = pkgs.writeShellScriptBin "exercise-home-router-topology" ''
      set -euxo pipefail

      wait_for_bridge_port() {
        port="$1"
        for _ in $(seq 1 50); do
          networkctl reconfigure "$port" 2>/dev/null || true
          if bridge link show dev "$port" | grep -q 'master br-core'; then
            return
          fi
          sleep 0.1
        done
        networkctl status "$port"
        exit 1
      }

      ip netns add upstream
      ip link add uplink0 type veth peer name upstream0
      ip link set upstream0 netns upstream
      ip link set uplink0 up
      ip -n upstream link set lo up
      ip -n upstream link set upstream0 up
      wait_for_bridge_port uplink0

      ip -n upstream address add 198.51.100.1/24 dev upstream0
      ip -n upstream address add 2001:db8:931::1/64 dev upstream0
      ip -n upstream link add link upstream0 name upstream0.22 type vlan id 22
      ip -n upstream address add 192.0.2.1/24 dev upstream0.22
      ip -n upstream address add 203.0.113.10/32 dev upstream0.22
      ip -n upstream link set upstream0.22 up
      ip -n upstream route add 10.64.2.0/24 via 192.0.2.2 dev upstream0.22

      ip netns add guest
      ip link add vm-access0 type veth peer name guest0
      ip link set guest0 netns guest
      ip link set vm-access0 up
      ip -n guest link set lo up
      ip -n guest link set guest0 up
      wait_for_bridge_port vm-access0
      ip -n guest address add 10.64.2.2/24 dev guest0
      ip -n guest address add fd00:642::2/64 dev guest0
      ip -n guest route add default via 10.64.2.254 dev guest0

      ip netns exec upstream ping -c 2 -W 2 198.51.100.2
      ping -6 -c 2 -W 2 2001:db8:931::1
      ip netns exec upstream ping -c 2 -W 2 192.0.2.2
      ip netns exec upstream ping -c 2 -W 2 192.0.2.3
      ip netns exec guest ping -c 2 -W 2 10.64.2.254
      ip netns exec guest ping -6 -c 2 -W 2 fd00:642::254

      bridge vlan show dev uplink0 | grep -Eq '22$'
      bridge vlan show dev uplink0 | grep -Eq '931 PVID Egress Untagged$'
      bridge vlan show dev vm-access0 | grep -Eq '642 PVID Egress Untagged$'

      test "$(ip -o link show type vlan | grep -c 'br-core.22@')" -eq 1
      ip -4 address show dev br-core.22 | grep -F '192.0.2.2/24'
      ip -4 address show dev br-core.22 | grep -F '192.0.2.3/24'
      ip -d link show dev br-core.22 | grep -F 'altname chinanet'
      ip -d link show dev br-core.22 | grep -F 'altname cmcc'

      ! ip -o -4 address show dev br-core | grep -q .
      ! ip -o -6 address show dev br-core | grep -q .

      systemctl is-active --quiet policy-routing.service
      ip -4 route get 203.0.113.10 mark 198 | grep -F 'via 198.51.100.1 dev br-core.931 table cernet src 198.51.100.2'
      ip -4 route get 203.0.113.10 mark 201 | grep -F 'via 192.0.2.1 dev br-core.22 table chinanet src 192.0.2.2'
      ip -4 route get 203.0.113.10 mark 202 | grep -F 'via 192.0.2.1 dev br-core.22 table cmcc src 192.0.2.3'

      timeout 5 ip netns exec upstream tcpdump -qnli upstream0.22 -c 1 'icmp and dst host 203.0.113.10' > /tmp/wlt-chinanet-capture &
      capture_pid=$!
      sleep 0.2
      ip netns exec guest ping -c 1 -W 2 203.0.113.10
      wait "$capture_pid"
      grep -F '192.0.2.2 > 203.0.113.10' /tmp/wlt-chinanet-capture
    '';
  in {
    imports = [
      ../optional/gnet-edge-router.nix
      ../optional/home-router
      ../../secrets
    ];

    networking.hostName = "router";
    networking.homeRouter = {
      enable = true;

      switch.ports.uplink0 = {
        untagged = 931;
        tagged = [22];
      };

      lans = {
        internal = {
          vlan = 642;
          addresses = [
            "10.64.2.254/24"
            "fd00:642::254/64"
          ];
        };
        guest = {
          vlan = 654;
          addresses = ["10.64.4.254/24"];
          guest = true;
          ipv6.enable = false;
        };
      };

      wans = {
        cernet = {
          vlan = 931;
          addresses = [
            "198.51.100.2/24"
            "2001:db8:931::2/64"
          ];
          gateway4 = "198.51.100.1";
          routingTable = 198;
          defaultRoute = true;
        };
        chinanet = {
          vlan = 22;
          addresses = ["192.0.2.2/24"];
          gateway4 = "192.0.2.1";
          routingTable = 201;
        };
        cmcc = {
          vlan = 22;
          addresses = ["192.0.2.3/24"];
          gateway4 = "192.0.2.1";
          routingTable = 202;
        };
      };

      wlt = {
        enable = true;
        domain = "test.invalid";
        defaultOutlet.ipv4Mark = "201";
        defaultOutlet.ipv6 = "disabled";
      };

      dnsmasq.domain = "test.invalid";
    };

    services.wlt.enable = lib.mkForce false;

    networking.gnetEdgeRouter = {
      enable = true;
      lan = "internal";
    };

    networking.wireguard.interfaces.wg-iplc = {
      privateKeyFile = toString (pkgs.writeText "wg-iplc-test-private-key" "SHU/G83Hd3I1CH1EM8zifA5ja9QpKzcQljsZmDvuw3k=");
      table = "5110";
    };

    systemd.network.networks."50-vm-access" = {
      matchConfig.Name = "vm-access0";
      networkConfig.Bridge = config.networking.homeRouter.switch.name;
      bridgeVLANs = [
        {
          PVID = 642;
          EgressUntagged = 642;
        }
      ];
      linkConfig.RequiredForOnline = "no";
    };

    environment.systemPackages = [
      exerciseTopology
      pkgs.iproute2
      pkgs.iputils
      pkgs.tcpdump
    ];

    virtualisation.memorySize = 1024;
  };

  testScript = ''
    start_all()
    router.wait_for_unit("systemd-networkd.service")
    router.wait_until_succeeds("ip link show dev br-core")
    router.succeed("exercise-home-router-topology")
  '';
}
