{lib}: let
  selectorHost = "fixture-selector";
  exitHost = "fixture-exit";

  # WireGuard test vector also used by Nylon's own crypto tests. It is public
  # test data, not a production credential.
  privateKey = "sE7wuHwS06cQRlCKnbGVva6UcGaKMDLtWD4GghORWFg=";
  publicKey = "ynMTsT/6Is4mNsYAYp5nR98LEuUSz3AkwOCvMkT5fj8=";

  mesh = {
    defaults = {
      port = 6622;
      mtu = 1400;
      interfaceName = "nylon0";
      tcpObfuscation = true;
      udpCost = "5ms";
      transitCost = "3ms";
      selector = {
        enable = false;
        ipv6 = true;
      };
    };

    overlay = {
      ipv4Prefix = "10.250.99";
      ipv6Prefix = "fd10:250:99::";
    };

    topology.kind = "full-mesh";

    dns = {
      zone = "fixture.invalid.";
      ttl = 300;
      controller = selectorHost;
      apiUrl = "http://127.0.0.1/fixture.invalid";
    };

    reservedNumericIds = [];
    expected = {
      nodeCount = 2;
      exitCount = 1;
      selectorCount = 1;
    };
  };

  nodes = {
    ${selectorHost} = {
      numericId = 16;
      inherit publicKey;
      selector = {
        enable = true;
        ipv6 = true;
      };
      underlays.fixture = {
        interface = "eth0";
        endpoint = {
          ipv4 = "192.0.2.16";
          ipv6 = "2001:db8::16";
        };
      };
    };

    ${exitHost} = {
      numericId = 17;
      publicKey = "pOCSkrZRwni5dyxWn1+puxPZBrRqtoyd+dwrRAn4ogk=";
      underlays.fixture = {
        interface = "eth0";
        endpoint = {
          ipv4 = "192.0.2.17";
          ipv6 = "2001:db8::17";
        };
        exit = {
          label = 100;
          useDefaultRoute = true;
          families = {
            ipv4 = true;
            ipv6 = true;
          };
          presentation = {
            location = "ZZ,Fixture";
            operator = "Test";
          };
        };
      };
    };
  };

  compiled = import ../compile.nix {
    inherit lib mesh nodes;
    deployableHosts = [exitHost selectorHost];
  };
  selector = compiled.perHost.${selectorHost};
in {
  inherit
    privateKey
    publicKey
    selector
    selectorHost
    ;

  nodeConfigText = selector.publicNode.text + "key: ${privateKey}\n";
}
