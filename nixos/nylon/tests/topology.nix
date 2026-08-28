{lib}: let
  mesh = import ../mesh.nix;
  nodes = import ../nodes;
  expectedHosts = [
    "ali-sg"
    "blog"
    "cjia"
    "el"
    "el2"
    "misc0-jp"
    "misc1-sh"
    "misc1-sz"
    "oracle2"
    "oracle3"
    "somo-minisforum"
    "somo-nanopi-r4s"
    "xtom-hkg"
    "xtom-sjc"
    "xtom-syd"
  ];
  expectedSelectors = [
    "cjia"
    "el"
    "el2"
    "somo-minisforum"
    "somo-nanopi-r4s"
  ];
  expectedNumericIds = {
    blog = 16;
    cjia = 17;
    ali-sg = 18;
    el = 19;
    el2 = 20;
    misc1-sz = 23;
    misc1-sh = 24;
    oracle3 = 25;
    oracle2 = 26;
    somo-minisforum = 28;
    xtom-hkg = 29;
    xtom-sjc = 30;
    xtom-syd = 31;
    somo-nanopi-r4s = 32;
    misc0-jp = 33;
  };
  compileWith = {
    mesh' ? mesh,
    nodes' ? nodes,
    deployableHosts ? expectedHosts,
  }:
    import ../compile.nix {
      inherit lib;
      mesh = mesh';
      nodes = nodes';
      inherit deployableHosts;
    };
  fleet = compileWith {};

  inherit (builtins) attrNames elem filter hasAttr head length map;
  all = builtins.all;
  concatStringsSep = builtins.concatStringsSep;
  one = predicate: values: let
    matches = filter predicate values;
  in
    assert length matches == 1;
      head matches;
  fails = value: !(builtins.tryEval (builtins.deepSeq value true)).success;
  routerIds = view: map (router: router.id) view.central.value.routers;
  dnsNames = view: map (rrset: rrset.name) view.dns.rrsets;

  blogExit = one (exit: exit.nodeId == "blog" && exit.label == 100) fleet.topology.catalog;
  elSelector = fleet.perHost.el.selector;
  misc1SzNode = fleet.perHost.misc1-sz.publicNode;
  warpHosts = filter (name: fleet.perHost.${name}.cloudflareWarp != null) expectedHosts;
  updateNode = name: update:
    nodes
    // {
      ${name} = lib.recursiveUpdate nodes.${name} update;
    };

  duplicateIdNodes = updateNode "blog" {
    numericId = nodes.cjia.numericId;
  };
  duplicateKeyNodes = updateNode "blog" {
    publicKey = nodes.cjia.publicKey;
  };
  invalidEndpointNodes = updateNode "blog" {
    underlays.public.endpoint.ipv4 = "router.example.net";
  };
  invalidIpv4EndpointNodes = updateNode "blog" {
    underlays.public.endpoint.ipv4 = "256.0.0.1";
  };
  invalidIpv6EndpointNodes = updateNode "blog" {
    underlays.public.endpoint.ipv6 = "2001:db8:::1";
  };
  cidrIpv6EndpointNodes = updateNode "blog" {
    underlays.public.endpoint.ipv6 = "2001:db8::1/64";
  };
  invalidIpv6ExitNodes = updateNode "el" {
    underlays.cernet.exit.ipv6Address = "1:2:3:4:5:6:7:8:9";
  };
  invalidIpv6WarpNodes = updateNode "ali-sg" {
    underlays.warp.cloudflareWarp.ipv6Address = "2001::db8::1";
  };
  duplicateExitLabelNodes = updateNode "el" {
    underlays.chinanet.exit.label = 100;
  };
  unencodableExitNodes = updateNode "blog" {
    underlays.public.exit.label = 110;
  };
  reservedIdNodes = updateNode "blog" {
    numericId = 22;
  };
  conflictingBindNodes = updateNode "blog" {
    underlays.public = {
      bind = false;
      bindSource = true;
    };
  };
  secretBearingNodes = updateNode "blog" {
    privateKey = "must-not-enter-the-store";
  };
  unknownNodeFields = updateNode "blog" {
    addresses = {
      ipv4 = "10.250.10.16";
      ipv6 = "fd10:250:10::16";
    };
  };
  unknownSelectorFields = updateNode "el" {
    selector.routes = {
      ipv4 = [];
      ipv6 = [];
    };
  };
  unknownUnderlayFields = updateNode "blog" {
    underlays.public.binds = [];
  };
  unknownEndpointFields = updateNode "blog" {
    underlays.public.endpoint.hostname = "router.example.net";
  };
  unknownExitFields = updateNode "blog" {
    underlays.public.exit.mark = 352;
  };
  unknownExitFamilyFields = updateNode "blog" {
    underlays.public.exit.families.ipv10 = true;
  };
  unknownPresentationFields = updateNode "blog" {
    underlays.public.exit.presentation.displayName = "Hangzhou";
  };
  unknownWarpFields = updateNode "ali-sg" {
    underlays.warp.cloudflareWarp.label = 101;
  };
in
  assert attrNames nodes == expectedHosts;
  assert fleet.topology.peerNames == expectedHosts;
  assert fleet.topology.selectors == expectedSelectors;
  assert all (name: fleet.topology.peers.${name}.numericId == expectedNumericIds.${name}) expectedHosts;
  assert fleet.manifest.value.counts
  == {
    peers = 15;
    exits = 23;
    selectors = 5;
    dnsRrsets = 30;
  };
  assert routerIds fleet == expectedHosts;
  assert !(elem "los6" (routerIds fleet));
  assert !(elem "google" (routerIds fleet));
  assert !(elem "los6.ny.gaof.net." (dnsNames fleet));
  assert !(elem "google.ny.gaof.net." (dnsNames fleet));
  assert all (exit: exit.nodeId != "los6" && exit.nodeId != "google") fleet.topology.catalog;
  assert fleet.dns.controller == "el2";
  assert fleet.dns.apiUrl == "http://pdns-ui.ts.gaof.net/api/v1/servers/localhost/zones/ny.gaof.net";
  assert fleet.central.sha256 == "bfc095f5c9b347a554a453ad45991e33ce00922d3b4f8b0c0f8c95a8cfd5fd3c";
  assert fleet.central.value.graph == [(concatStringsSep ", " expectedHosts)];
  assert builtins.fromJSON fleet.dns.text == fleet.dns.value;
  assert builtins.match ".*privateKey.*" fleet.manifest.text == null;
  assert !hasAttr "exit" fleet.topology.peers.blog.underlays.public;
  assert !hasAttr "key" misc1SzNode.value;
  assert builtins.substring (builtins.stringLength misc1SzNode.text - 1) 1 misc1SzNode.text == "\n";
  assert map (bind: bind.source) misc1SzNode.value.binds == ["58.84.55.69" "14.215.130.15"];
  assert map (bind: bind.source) fleet.perHost.el.publicNode.value.binds
  == ["202.38.93.152" "202.141.162.122" "202.141.178.12" "2001:da8:d800:931::152"];
  assert warpHosts == ["ali-sg" "misc1-sh" "oracle2"];
  assert fleet.perHost.ali-sg.cloudflareWarp.interface == "wg-cloudflare";
  assert blogExit.mark == 352;
  assert blogExit.markHex == "0x160";
  assert blogExit.table == 5160;
  assert blogExit.mplsSelector == "16/100";
  assert elem "fwmark 0x160/0xfff lookup 5160" elSelector.rules.ipv4;
  assert elem "route replace default encap mpls 16/100 dev nylon0 table 5160" elSelector.routes.ipv4;
  assert !(elem "fwmark 0x270/0xfff lookup 5270" elSelector.rules.ipv4);
  assert !(elem "fwmark 0x271/0xfff lookup 5271" elSelector.rules.ipv6);
  assert all (exit: exit.nodeId != "el") fleet.wlt.selectors.el.outlets;
  assert attrNames elSelector == ["enable" "ownedTables" "routes" "rules" "wlt"];
  assert attrNames elSelector.wlt == ["text"];
  assert attrNames fleet.perHost.blog.central == ["text"];
  assert attrNames fleet.perHost.blog.exits.public
  == ["families" "gateway4" "interface" "ipv4Address" "ipv6Address" "label" "useDefaultRoute"];
  assert attrNames fleet.perHost.ali-sg.cloudflareWarp == ["interface" "ipv6Address" "reserved"];
  assert !hasAttr "binds" fleet.perHost.blog;
  assert !hasAttr "lanDiscovery" fleet.perHost.blog;
  assert !hasAttr "overlayNat" fleet.perHost.blog;
  assert !hasAttr "underlays" fleet.perHost.blog;
  assert fleet.perHost.cjia.selector.rules.ipv6 == [];
  assert !hasAttr "misc1-sz" fleet.wlt.selectors;
  assert fleet.perHost.misc1-sz.selector.routes
  == {
    ipv4 = [];
    ipv6 = [];
  };
  assert builtins.match ".*0x160000.*" (builtins.replaceStrings ["\n"] [" "] elSelector.wlt.text) != null;
  assert all (exit: !(exit.nodeId == "el" && exit.label == 103)) fleet.topology.catalog;
  assert fails (compileWith {nodes' = duplicateIdNodes;});
  assert fails (compileWith {nodes' = duplicateKeyNodes;});
  assert fails (compileWith {nodes' = invalidEndpointNodes;});
  assert fails (compileWith {nodes' = invalidIpv4EndpointNodes;});
  assert fails (compileWith {nodes' = invalidIpv6EndpointNodes;});
  assert fails (compileWith {nodes' = cidrIpv6EndpointNodes;});
  assert fails (compileWith {nodes' = invalidIpv6ExitNodes;});
  assert fails (compileWith {nodes' = invalidIpv6WarpNodes;});
  assert fails (compileWith {nodes' = duplicateExitLabelNodes;});
  assert fails (compileWith {nodes' = unencodableExitNodes;});
  assert fails (compileWith {nodes' = reservedIdNodes;});
  assert fails (compileWith {nodes' = conflictingBindNodes;});
  assert fails (compileWith {nodes' = secretBearingNodes;});
  assert fails (compileWith {nodes' = unknownNodeFields;});
  assert fails (compileWith {nodes' = unknownSelectorFields;});
  assert fails (compileWith {nodes' = unknownUnderlayFields;});
  assert fails (compileWith {nodes' = unknownEndpointFields;});
  assert fails (compileWith {nodes' = unknownExitFields;});
  assert fails (compileWith {nodes' = unknownExitFamilyFields;});
  assert fails (compileWith {nodes' = unknownPresentationFields;});
  assert fails (compileWith {nodes' = unknownWarpFields;});
  assert fails (compileWith {deployableHosts = filter (name: name != "blog") expectedHosts;}); {
    inherit (fleet.central) sha256;
    inherit (fleet.manifest.value) counts;
  }
