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

      wait_for_address() {
        interface="$1"
        address="$2"
        for _ in $(seq 1 50); do
          networkctl reconfigure "$interface" 2>/dev/null || true
          address_line="$(ip -o address show dev "$interface" | grep "$address" || true)"
          if [ -n "$address_line" ] && ! grep -qw tentative <<<"$address_line"; then
            return
          fi
          sleep 0.1
        done
        networkctl status "$interface"
        exit 1
      }

      counter_bytes() {
        nft --json list counter inet home-router "$1" |
          ${pkgs.jq}/bin/jq --exit-status --raw-output '.nftables[] | select(.counter != null) | .counter.bytes'
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
      ip -n upstream address add 2606:4700:4408::1/128 dev lo
      ip -n upstream address add 223.5.5.5/32 dev lo
      ip -n upstream address add 223.6.6.6/32 dev lo
      ip -n upstream link add link upstream0 name upstream0.22 type vlan id 22
      ip -n upstream address add 192.0.2.1/24 dev upstream0.22
      ip -n upstream address add 203.0.113.10/32 dev upstream0.22
      ip -n upstream link set upstream0.22 up
      ip -n upstream route add 10.64.2.0/24 via 192.0.2.2 dev upstream0.22
      ip netns exec upstream ${pkgs.dnsmasq}/bin/dnsmasq \
        --no-daemon \
        --no-resolv \
        --bind-interfaces \
        --listen-address=223.5.5.5 \
        --listen-address=223.6.6.6 \
        --address=/www.public.test/223.5.5.5 \
        --address=/www.public-v6.test/2400:3200::53 \
        --pid-file=/tmp/fake-public-dns.pid \
        >/tmp/fake-public-dns.log 2>&1 &
      fake_dns_pid=$!
      sleep 0.2
      kill -0 "$fake_dns_pid"

      ip netns add management
      ip link add management0 type veth peer name router0
      ip link set router0 netns management
      ip link set management0 up
      ip -n management link set lo up
      ip -n management link set router0 up
      ip -n management address add 192.168.93.1/24 dev router0
      ip -n management address add 2001:db8:93::1/64 dev router0
      wait_for_address management0 192.168.93.2/24
      wait_for_address management0 2001:db8:93::2/64

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
      wait_for_address br-core.931 2001:db8:931::2/64

      ip netns add podman
      ip link add podman0 type veth peer name container0
      ip link set container0 netns podman
      ip address add 10.88.0.1/24 dev podman0
      ip link set podman0 up
      ip -n podman link set lo up
      ip -n podman link set container0 up
      ip -n podman address add 10.88.0.2/24 dev container0
      ip -n podman route add default via 10.88.0.1 dev container0

      nft list chain inet edge-filter input | grep -F 'policy drop'
      nft list chain inet edge-filter input | grep 'iifname' | grep -F '"br-core.642"'
      nft list chain inet edge-filter input | grep -F 'iifname "br-core.654" udp dport 67 accept'
      nft list chain inet edge-filter input | grep -F 'tcp dport 5201 accept'
      nft list chain inet edge-filter input | grep 'udp dport' | grep -F '5201' | grep -F '61001-61999'
      nft list chain inet edge-filter forward | grep -F 'policy drop'
      nft list chain inet home-router mss-forward | grep -F 'tcp option maxseg size set rt mtu'
      nft list chain inet home-router wlt-prerouting | grep -F 'meta mark set'
      nft list chain inet home-router egress-output | grep -F 'oifname "management0" jump egress-classify'
      nft list chain inet home-router egress-prerouting | grep -F 'iifname "podman*" jump egress-classify'
      nft list chain inet home-router egress-classify | grep 'udp sport' | grep -F '6627'
      nft list chain inet home-router egress-classify | grep -F 'udp sport 2197 return'
      nft list chain inet home-router egress-classify | grep -F 'ip daddr @cernet' | grep -F 'ct mark set meta mark return'
      ! nft list chain inet home-router egress-classify | grep -F 'ip saddr'
      nft list chain inet home-router egress-postrouting | grep -F 'snat ip to 198.51.100.2'
      nft list chain inet home-router egress-postrouting | grep -F 'snat ip6 to 2001:db8:931::2'
      nft list chain inet home-router egress-postrouting | grep -F 'oifgroup 6505 masquerade'
      ! nft list table inet el-router
      timeout 5 nc -6 -l 23456 >/dev/null &
      localhost_listener_pid=$!
      sleep 0.2
      nc -6 -z -w 2 ::1 23456
      wait "$localhost_listener_pid"

      timeout 5 ip netns exec upstream nc -6 -l 23457 >/dev/null &
      bound_source_listener_pid=$!
      sleep 0.2
      nc -6 -s 2001:db8:931::2 -z -w 2 2606:4700:4408::1 23457
      wait "$bound_source_listener_pid"

      timeout 5 ip netns exec upstream nc -6 -l 23457 >/dev/null &
      automatic_source_listener_pid=$!
      sleep 0.2
      ! nc -6 -z -w 2 2606:4700:4408::1 23457
      kill -0 "$automatic_source_listener_pid"
      kill "$automatic_source_listener_pid"
      wait "$automatic_source_listener_pid" || true

      ! ip netns exec upstream ping -c 1 -W 1 10.64.2.2

      ip netns exec upstream ping -c 2 -W 2 198.51.100.2
      ping -6 -c 2 -W 2 2001:db8:931::1
      ip netns exec upstream ping -c 2 -W 2 192.0.2.2
      ip netns exec upstream ping -c 2 -W 2 192.0.2.3
      ip netns exec guest ping -c 2 -W 2 10.64.2.254
      ip netns exec guest ping -6 -c 2 -W 2 fd00:642::254

      timeout 5 ip netns exec upstream tcpdump -qnli upstream0.22 -c 1 'icmp and src host 192.0.2.2 and dst host 223.5.5.5' > /tmp/podman-chinanet-capture &
      podman_capture_pid=$!
      sleep 0.2
      ip netns exec podman ping -c 1 -W 2 223.5.5.5
      wait "$podman_capture_pid"

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
      ip -o link show dev wg-iplc | grep -F 'mtu 1392'
      ip -4 address show dev wg-iplc | grep -F '10.255.255.100/24'
      wg show wg-iplc dump | tail -n +2 | awk '$4 == "0.0.0.0/0" && $8 == 60'
      ip -4 rule show | grep -F 'fwmark 0x100/0xfff lookup 5100'
      ip -6 rule show | grep -F 'fwmark 0xfff/0xfff lookup 4095'
      ip -4 rule show | grep -F 'from 198.51.100.2 lookup cernet'
      ip -4 rule show | grep -F 'from 192.0.2.2 lookup chinanet'
      ip -4 rule show | grep -F 'from 192.0.2.3 lookup cmcc'
      ip -6 rule show | grep -F 'from 2001:db8:931::2 lookup cernet'
      ip -4 route show default | grep -F 'via 192.168.93.1 dev management0' | grep -F 'metric 100'
      ip -4 route show default | grep -F 'via 198.51.100.1 dev br-core.931' | grep -F 'metric 200'
      ip -6 route show default | grep -F 'via 2001:db8:93::1 dev management0' | grep -F 'metric 100'
      ip -6 route show default | grep -F 'via 2001:db8:931::1 dev br-core.931' | grep -F 'metric 200'
      ip -4 route get 203.0.113.10 | grep -F 'via 192.168.93.1 dev management0 src 192.168.93.2'
      ip -6 route get 2606:4700:4408::1 | grep -F 'dev management0' | grep -F 'src 2001:db8:93::2'
      ip -4 route get 203.0.113.10 from 198.51.100.2 | grep -F 'via 198.51.100.1 dev br-core.931 table cernet'
      ip -6 route get 2606:4700:4408::1 from 2001:db8:931::2 | grep -F 'via 2001:db8:931::1 dev br-core.931 table cernet'
      ip -4 route get 203.0.113.10 oif br-core.931 | grep -F 'via 198.51.100.1 dev br-core.931 src 198.51.100.2'
      ip -4 route get 10.64.2.2 mark 198 | grep -F 'dev br-core.642'
      ip -4 route get 203.0.113.10 mark 198 | grep -F 'via 198.51.100.1 dev br-core.931 table cernet src 198.51.100.2'
      ip -4 route get 203.0.113.10 mark 201 | grep -F 'via 192.0.2.1 dev br-core.22 table chinanet src 192.0.2.2'
      ip -4 route get 203.0.113.10 mark 202 | grep -F 'via 192.0.2.1 dev br-core.22 table cmcc src 192.0.2.3'

      systemctl start wlt-dns.service
      systemctl is-active --quiet wlt-dns.service
      nft 'add element inet home-router src2mark { 10.64.2.2 : 0xc9000 }'
      test "$(ip netns exec guest ${pkgs.dnsutils}/bin/dig +short @10.64.2.254 fixture.el2.gaof.net A)" = "10.64.2.123"
      test "$(ip netns exec guest ${pkgs.dnsutils}/bin/dig +tcp +short @10.64.2.254 fixture.el2.gaof.net A)" = "10.64.2.123"
      test "$(ip netns exec guest ${pkgs.dnsutils}/bin/dig +short @10.64.2.254 www.public.test A)" = "223.5.5.5"
      test "$(ip netns exec guest ${pkgs.dnsutils}/bin/dig +tcp +short @10.64.2.254 www.public.test A)" = "223.5.5.5"
      test "$(ip netns exec guest ${pkgs.dnsutils}/bin/dig +short @10.64.2.254 www.public-v6.test AAAA)" = "2400:3200::53"
      test "$(ip netns exec guest ${pkgs.dnsutils}/bin/dig +tcp +short @10.64.2.254 www.public-v6.test AAAA)" = "2400:3200::53"
      nft 'delete element inet home-router src2mark { 10.64.2.2 }'

      timeout 10 ip netns exec upstream tcpdump -qnli upstream0 -c 1 'icmp and src host 198.51.100.2'
      timeout 10 ip netns exec upstream tcpdump -qnli upstream0.22 -c 1 'icmp and src host 192.0.2.2'
      timeout 10 ip netns exec upstream tcpdump -qnli upstream0.22 -c 1 'icmp and src host 192.0.2.3'

      nft 'add element inet home-router src2mark { 10.64.2.2 : 201 }'
      timeout 5 ip netns exec upstream tcpdump -qnli upstream0.22 -c 1 'icmp and dst host 203.0.113.10' > /tmp/wlt-chinanet-capture &
      capture_pid=$!
      sleep 0.2
      ip netns exec guest ping -c 1 -W 2 203.0.113.10
      wait "$capture_pid"
      grep -F '192.0.2.2 > 203.0.113.10' /tmp/wlt-chinanet-capture

      systemctl stop \
        prometheus-ping-cernet-exporter.service \
        prometheus-ping-chinanet-exporter.service \
        prometheus-ping-cmcc-exporter.service

      chinanet_receive_before="$(counter_bytes home_router_wan_1_receive)"
      chinanet_transmit_before="$(counter_bytes home_router_wan_1_transmit)"
      cmcc_receive_before="$(counter_bytes home_router_wan_2_receive)"
      cmcc_transmit_before="$(counter_bytes home_router_wan_2_transmit)"

      ip netns exec upstream ping -c 1 -W 2 192.0.2.2

      test "$(counter_bytes home_router_wan_1_receive)" -gt "$chinanet_receive_before"
      test "$(counter_bytes home_router_wan_1_transmit)" -gt "$chinanet_transmit_before"
      test "$(counter_bytes home_router_wan_2_receive)" -eq "$cmcc_receive_before"
      test "$(counter_bytes home_router_wan_2_transmit)" -eq "$cmcc_transmit_before"

      ip netns exec upstream ping -c 1 -W 2 192.0.2.3

      test "$(counter_bytes home_router_wan_2_receive)" -gt "$cmcc_receive_before"
      test "$(counter_bytes home_router_wan_2_transmit)" -gt "$cmcc_transmit_before"
      test "$(counter_bytes home_router_wan_0_receive)" -gt 0
      test "$(counter_bytes home_router_wan_0_transmit)" -gt 0

      systemctl start home-router-wan-metrics.service
      ! systemctl show --property=After --value home-router-wan-metrics.service | grep -qw prometheus-node-exporter.service
      ! systemctl show --property=Requires --value home-router-wan-metrics.service | grep -qw prometheus-node-exporter.service
      grep -F 'home_router_wan_receive_bytes_total{wan="cernet"}' /run/home-router-wan-metrics/home-router-wan.prom
      grep -F 'home_router_wan_transmit_bytes_total{wan="chinanet"}' /run/home-router-wan-metrics/home-router-wan.prom
      grep -F 'home_router_wan_transmit_bytes_total{wan="cmcc"}' /run/home-router-wan-metrics/home-router-wan.prom
      ${pkgs.curl}/bin/curl --fail --silent http://127.0.0.1:9100/metrics |
        grep -F 'home_router_wan_receive_bytes_total{wan="chinanet"}'

      prometheus_config="$(
        systemctl show --property=ExecStart --value prometheus.service |
          sed -n 's/.*--config.file=\([^ ;]*\).*/\1/p'
      )"
      test -r "$prometheus_config"
      test "$(grep -c 'collect\[\]:' "$prometheus_config")" -eq 3
      test "$(grep -c -- '- netclass' "$prometheus_config")" -eq 3
      test "$(grep -c -- '- netdev' "$prometheus_config")" -eq 3

      filtered_node_metrics="$(
        ${pkgs.curl}/bin/curl --fail --silent --get \
          --data-urlencode 'collect[]=netclass' \
          --data-urlencode 'collect[]=netdev' \
          http://127.0.0.1:9100/metrics
      )"
      test "$(grep -c '^node_scrape_collector_success{collector=' <<< "$filtered_node_metrics")" -eq 2
      grep -F 'node_scrape_collector_success{collector="netclass"} 1' <<< "$filtered_node_metrics"
      grep -F 'node_scrape_collector_success{collector="netdev"} 1' <<< "$filtered_node_metrics"
      ! grep -q '^node_cpu_seconds_total' <<< "$filtered_node_metrics"

      for metric in node_network_carrier node_network_receive_errs_total; do
        test "$(
          ${pkgs.curl}/bin/curl --fail --silent --get \
            --data-urlencode "query=count($metric{job=~\"node-wan-.+\"})" \
            http://127.0.0.1:9090/api/v1/query |
            ${pkgs.jq}/bin/jq --exit-status --raw-output '.data.result[0].value[1]'
        )" -eq 3
      done

      thermal_queries="$(
        ${pkgs.curl}/bin/curl --fail --silent \
          http://127.0.0.1:3001/api/dashboards/uid/home-router-overview |
          ${pkgs.jq}/bin/jq --exit-status --raw-output '
            [
          "CPU/SoC Temperature",
          "Hardware Temperatures",
          "IPMI Fan Speed",
          "Thermal Mitigation",
          "Critical Temperature Headroom"
            ] as $titles
            | if .meta.provisioned and ((($titles - [.dashboard.panels[].title]) | length) == 0)
              then
                .dashboard.panels[]
                | select(.title as $title | $titles | index($title))
                | .targets[].expr
              else error("thermal dashboard panels were not provisioned")
              end
          '
      )"

      while IFS= read -r query; do
        query="''${query//\$__rate_interval/5m}"
        ${pkgs.curl}/bin/curl --fail --silent --get \
          --data-urlencode "query=$query" \
          http://127.0.0.1:9090/api/v1/query |
          ${pkgs.jq}/bin/jq --exit-status '.status == "success"'
      done <<< "$thermal_queries"

      ${pkgs.curl}/bin/curl --fail --silent \
        http://127.0.0.1:3001/apis/dashboard.grafana.app/v2/namespaces/default/dashboards/home-router-overview |
        ${pkgs.jq}/bin/jq --exit-status '
          [
            .spec.layout.spec.rows[].spec.layout.spec.items[]
            | select(.spec.element.name == "panel-19")
            | .spec.conditionalRendering
            | select(
                .spec.visibility == "show"
                and (.spec.items | length) == 1
                and .spec.items[0].kind == "ConditionalRenderingData"
                and .spec.items[0].spec.value
              )
          ] | length == 1
        '
    '';
  in {
    imports = [
      inputs.agenix.nixosModules.default
      {
        options.services.secrets = {
          hasRealFiles = lib.mkOption {
            type = lib.types.bool;
            default = false;
            readOnly = true;
          };
          filesDir = lib.mkOption {
            type = lib.types.path;
            default = ../../secrets/files-example;
            internal = true;
          };
        };
      }
      ../common/internal-dns.nix
      ../optional/el-router.nix
      ../optional/home-router
    ];

    networking.hostName = "router";
    networking.homeRouter = {
      enable = true;

      monitoring.enable = true;

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
          dhcpServer.range = "10.64.4.100,10.64.4.200,1h";
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
          gateway6 = "2001:db8:931::1";
          routingTable = 198;
          defaultRoute = true;
          defaultRouteMetric = 200;
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
        dns = {
          explicitListenAddresses = [
            "192.168.93.2"
            "2001:db8:93::2"
          ];
          entryInterfaces = ["management0"];
          extraAllowedClientCidrs = [
            "192.168.93.0/24"
            "2001:db8:93::/64"
          ];
        };
      };

      egress = {
        classification = {
          extraIngressInterfaces = ["podman*"];
          outputClassificationInterface = "management0";
        };
        masquerade = {
          extraInterfaces = ["management0"];
          extraRules = [
            ''ip saddr @private_v4 oifgroup 6505 masquerade''
          ];
        };
      };

      wgIplc = {
        ip = "10.255.255.100/24";
        privateKeyFile = pkgs.writeText "unused-wg-iplc-test-private-key.age" "";
      };

      dnsmasq.domain = "el2.gaof.net";
    };

    services.wlt.enable = lib.mkForce false;
    services.tailscale.port = 6627;

    networking.hosts."10.64.2.123" = ["fixture.el2.gaof.net"];

    networking.elRouter = {
      enable = true;
    };

    networking.edgeFirewall.extraForwardRules = [''iifname "podman*" accept''];

    networking.wireguard.interfaces.wg-iplc.privateKeyFile =
      lib.mkForce (toString (pkgs.writeText "wg-iplc-test-private-key" "SHU/G83Hd3I1CH1EM8zifA5ja9QpKzcQljsZmDvuw3k="));

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

    systemd.network.networks."09-management" = {
      matchConfig.Name = "management0";
      address = [
        "192.168.93.2/24"
        "2001:db8:93::2/64"
      ];
      routes = [
        {
          Gateway = "192.168.93.1";
          GatewayOnLink = true;
          PreferredSource = "192.168.93.2";
          Metric = 100;
        }
        {
          Gateway = "2001:db8:93::1";
          GatewayOnLink = true;
          PreferredSource = "2001:db8:93::2";
          Metric = 100;
        }
      ];
      networkConfig = {
        DHCP = "no";
        IPv6AcceptRA = false;
      };
      linkConfig.RequiredForOnline = "no";
    };

    environment.systemPackages = [
      exerciseTopology
      pkgs.iproute2
      pkgs.iputils
      pkgs.netcat-openbsd
      pkgs.tcpdump
    ];

    virtualisation.memorySize = 1024;
  };

  testScript = {nodes, ...}: ''
    start_all()
    router.wait_for_unit("systemd-networkd.service")
    router.wait_for_open_port(9090)
    router.wait_for_open_port(9100)
    router.wait_for_open_port(3001)
    router.wait_until_succeeds("ip link show dev br-core")
    router.fail("systemctl list-unit-files wlt-dns-canary.service")
    router.fail("systemctl list-unit-files diverge.service")
    router.succeed("grep -F 'port=1053' ${nodes.router.services.dnsmasq.configFile}")
    router.succeed("grep -F 'local=/el2.gaof.net/' ${nodes.router.services.dnsmasq.configFile}")
    router.succeed("grep -F 'cache-size=0' ${nodes.router.services.dnsmasq.configFile}")
    router.fail("grep -F 'server=' ${nodes.router.services.dnsmasq.configFile}")
    router.succeed("grep -F '127.0.0.1:1053' ${nodes.router.services.wltDns.configFile}")
    router.succeed("grep -F '10.64.2.254:53' ${nodes.router.services.wltDns.configFile}")
    router.succeed("grep -F '192.168.93.2:53' ${nodes.router.services.wltDns.configFile}")
    router.succeed("grep -F '[2001:db8:93::2]:53' ${nodes.router.services.wltDns.configFile}")
    router.succeed("grep -F '[2001:2::ffff]:53' ${nodes.router.services.wltDns.configFile}")
    router.succeed("grep -F '127.0.0.1:9421' ${nodes.router.services.wltDns.configFile}")
    router.succeed("grep -F '[dns_servers.aliyun]' ${nodes.router.services.wltDns.configFile}")
    router.succeed("grep -F '[dns_servers.cloudflare]' ${nodes.router.services.wltDns.configFile}")
    router.succeed("grep -F 'ipv4_default_mark = 256' ${nodes.router.services.wltDns.configFile}")
    router.succeed("grep -F 'ipv6_default_mark = 4095' ${nodes.router.services.wltDns.configFile}")
    router.succeed("grep -F 'title = \"国内出口\"' ${nodes.router.services.wltDns.configFile}")
    router.succeed("grep -F 'title = \"海外出口\"' ${nodes.router.services.wltDns.configFile}")
    router.succeed("grep -F 'outlet_regex = \"^CN \"' ${nodes.router.services.wltDns.configFile}")
    router.fail("grep -F '10.64.4.254:53' ${nodes.router.services.wltDns.configFile}")
    router.fail("grep -F '192.0.2.2:53' ${nodes.router.services.wltDns.configFile}")
    router.fail("grep -F '10.255.255.100:53' ${nodes.router.services.wltDns.configFile}")
    router.succeed("test \"$(id -u wlt-dns)\" = 398")
    router.succeed("systemctl show wlt-dns.service -p PartOf --value | grep -F 'policy-routing.service'")
    router.succeed("systemctl show policy-routing.service -p Before --value | grep -F 'wlt-dns.service'")
    router.fail("systemctl show wlt-dns.service -p ExecStart --value | grep -F -- '--config-dir'")
    router.succeed("nft list chain inet home-router wlt-prerouting | grep -E 'dport (53|domain)' | grep -F 'iifname' | grep -F 'ct mark set'")
    router.succeed("nft list chain inet home-router egress-output | grep -F 'meta skuid 398'")
    router.succeed("nft list chain inet home-router egress-output | grep -F 'ip daddr != {' | grep -F '223.5.5.5' | grep -F '1.1.1.1'")
    router.succeed("nft list chain inet edge-filter input | grep -F 'th dport 1053 drop'")
    router.fail("nft list ruleset | grep -E 'dport (53|domain).*dnat'")
    router.succeed("ip -4 rule show | grep -F 'to 1.1.1.1' | grep -F 'goto 200'")
    router.succeed("ip -4 rule show | grep -F 'to 1.1.1.1' | grep -F 'fwmark' | grep -F '/0xffffff' | grep -F 'lookup main'")
    router.succeed("ip -4 rule show | grep -F 'to 1.1.1.1' | grep -F 'unreachable'")
    router.succeed("exercise-home-router-topology")
    router.wait_for_unit("wlt-dns.service")
    router.succeed("ss -Hlnut 'sport = :53' | grep -F '10.64.2.254:53'")
    router.succeed("ss -Hlnut 'sport = :1053' | grep -F '127.0.0.1:1053'")
  '';
}
