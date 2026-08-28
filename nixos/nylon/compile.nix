# Pure boundary between public fleet declarations and side-effecting NixOS,
# deployment, and DNS adapters. This file deliberately returns values/text,
# never store paths or runtime secret locations.
{
  lib,
  mesh,
  nodes,
  deployableHosts,
}: let
  inherit (builtins) attrNames attrValues concatMap concatStringsSep elem filter foldl' hasAttr length listToAttrs map mapAttrs;
  inherit (lib) allUnique count mod optional unique;

  compilerError = message: throw "Nylon topology compiler: ${message}";
  ensure = condition: message:
    if condition
    then true
    else compilerError message;

  getOr = attrs: name: fallback:
    if hasAttr name attrs
    then attrs.${name}
    else fallback;
  quote = builtins.toJSON;
  replace = builtins.replaceStrings;

  isNonEmptyString = value: builtins.isString value && value != "";
  isIpv4Literal = value: let
    match =
      if builtins.isString value
      then builtins.match "^([0-9]{1,3})\\.([0-9]{1,3})\\.([0-9]{1,3})\\.([0-9]{1,3})$" value
      else null;
    decimal = text:
      foldl' (value: index: value * 10 + builtins.fromJSON (builtins.substring index 1 text)) 0
      (builtins.genList (index: index) (builtins.stringLength text));
  in
    match != null && builtins.all (octet: decimal octet <= 255) match;
  isIpv6Literal = value:
    builtins.isString value
    && builtins.match ".*/.*" value == null
    && (builtins.tryEval (builtins.deepSeq (lib.network.ipv6.fromString value) true)).success;
  isIpLiteral = family: value:
    if family == "ipv4"
    then isIpv4Literal value
    else isIpv6Literal value;
  isPublicKey = value:
    builtins.isString value
    && builtins.match "^[A-Za-z0-9+/]{43}=$" value != null;
  isSecretLikeField = field: let
    lower = lib.strings.toLower field;
  in
    field
    != "publicKey"
    && (
      lower
      == "key"
      || builtins.match ".*(secret|private|password|token|credential).*" lower != null
      || builtins.match ".*key(file|path)?$" lower != null
    );
  schemaChecks = context: allowed: attrs: let
    fields = attrNames attrs;
    secretLike = filter isSecretLikeField fields;
    unknown = filter (field: !elem field allowed) fields;
  in [
    (ensure (secretLike == [])
      "${context}: secret-like fields are forbidden (${concatStringsSep ", " secretLike})")
    (ensure (unknown == [])
      "${context}: unknown fields (${concatStringsSep ", " unknown})")
  ];

  nodeFields = ["numericId" "publicKey" "selector" "transitCost" "underlays"];
  selectorFields = ["enable" "ipv6"];
  underlayFields = ["bind" "bindSource" "cloudflareWarp" "endpoint" "exit" "interface" "lanDiscovery"];
  endpointFields = ["ipv4" "ipv6"];
  exitFields = ["families" "gateway4" "ipv4Address" "ipv6Address" "label" "presentation" "useDefaultRoute"];
  exitFamilyFields = ["ipv4" "ipv6"];
  presentationFields = ["location" "operator"];
  cloudflareWarpFields = ["ipv6Address" "reserved"];

  defaults = mesh.defaults;
  selectorDefault = defaults.selector;
  overlay4 = numericId: "${mesh.overlay.ipv4Prefix}.${toString numericId}";
  overlay6 = numericId: "${mesh.overlay.ipv6Prefix}${toString numericId}";
  endpointText = endpoint:
    if endpoint.family == "ipv4"
    then "${endpoint.address}:${toString defaults.port}"
    else "[${endpoint.address}]:${toString defaults.port}";

  normalizeExit = nodeId: numericId: underlayName: underlay: let
    raw = underlay.exit;
    families = getOr raw "families" {};
    presentation = getOr raw "presentation" {};
    useDefaultRoute = getOr raw "useDefaultRoute" false;
  in {
    name = underlayName;
    inherit nodeId numericId underlayName useDefaultRoute;
    label = getOr raw "label" null;
    interface =
      if useDefaultRoute
      then null
      else getOr underlay "interface" null;
    underlayInterface = getOr underlay "interface" null;
    families = {
      ipv4 = getOr families "ipv4" false;
      ipv6 = getOr families "ipv6" false;
    };
    gateway4 = getOr raw "gateway4" null;
    ipv4Address = getOr raw "ipv4Address" null;
    ipv6Address = getOr raw "ipv6Address" null;
    presentation = {
      location = getOr presentation "location" null;
      operator = getOr presentation "operator" null;
    };
    cloudflareWarp = let
      warp = getOr underlay "cloudflareWarp" null;
    in
      if warp == null
      then null
      else {
        ipv6Address = getOr warp "ipv6Address" null;
        reserved = getOr warp "reserved" null;
      };
  };

  normalizePeer = name: raw: let
    numericId = getOr raw "numericId" null;
    underlays = getOr raw "underlays" {};
    underlayNames = attrNames underlays;
    normalizedUnderlays =
      mapAttrs (_: underlay: let
        endpoint = getOr underlay "endpoint" {};
        warp = getOr underlay "cloudflareWarp" null;
      in {
        interface = getOr underlay "interface" null;
        inherit endpoint;
        bind = getOr underlay "bind" (endpoint != {});
        bindSource = getOr underlay "bindSource" false;
        lanDiscovery = getOr underlay "lanDiscovery" false;
        cloudflareWarp =
          if warp == null
          then null
          else {
            ipv6Address = getOr warp "ipv6Address" null;
            reserved = getOr warp "reserved" null;
          };
      })
      underlays;
    endpointsFrom = underlayName: let
      endpoint = getOr underlays.${underlayName} "endpoint" {};
    in
      concatMap (family:
        optional (hasAttr family endpoint) {
          inherit family;
          address = endpoint.${family};
        }) ["ipv4" "ipv6"];
    # Match the established config order: all IPv4 transports precede IPv6.
    # Nylon may use this list as a dialing preference, so this is behavioral,
    # not merely a formatting choice.
    endpointEntries = concatMap (family:
      concatMap (underlayName:
        filter (entry: entry.family == family) (endpointsFrom underlayName))
      underlayNames) ["ipv4" "ipv6"];
    sourceBinds = concatMap (family:
      concatMap (underlayName: let
        underlay = underlays.${underlayName};
        endpoint = getOr underlay "endpoint" {};
      in
        optional (
          getOr underlay "bind" (endpoint != {})
          && getOr underlay "bindSource" false
          && hasAttr family endpoint
        ) {
          interface = getOr underlay "interface" null;
          source = endpoint.${family};
        })
      underlayNames) ["ipv4" "ipv6"];
    interfaceBinds = concatMap (underlayName: let
      underlay = underlays.${underlayName};
      endpoint = getOr underlay "endpoint" {};
    in
      optional (
        getOr underlay "bind" (endpoint != {})
        && !getOr underlay "bindSource" false
      ) {
        interface = getOr underlay "interface" null;
      })
    underlayNames;
    binds = sourceBinds ++ interfaceBinds;
    lanDiscovery = unique (concatMap (underlayName:
      optional (getOr underlays.${underlayName} "lanDiscovery" false)
      (getOr underlays.${underlayName} "interface" null))
    underlayNames);
    exits = listToAttrs (concatMap (underlayName: let
      underlay = underlays.${underlayName};
    in
      optional (hasAttr "exit" underlay) {
        name = underlayName;
        value = normalizeExit name numericId underlayName underlay;
      })
    underlayNames);
    selector = selectorDefault // getOr raw "selector" {};
    transitCost = getOr raw "transitCost" defaults.transitCost;
    address4 = overlay4 numericId;
    address6 = overlay6 numericId;
  in {
    id = name;
    inherit numericId binds exits selector transitCost lanDiscovery;
    underlays = normalizedUnderlays;
    publicKey = getOr raw "publicKey" null;
    addresses = {
      ipv4 = address4;
      ipv6 = address6;
    };
    inherit endpointEntries;
    endpoints = map endpointText endpointEntries;
  };

  managedNames = attrNames nodes;
  normalizedManaged = mapAttrs normalizePeer nodes;

  exitListFor = peers:
    builtins.sort
    (left: right:
      left.numericId
      < right.numericId
      || (left.numericId == right.numericId && left.label < right.label)
      || (left.numericId == right.numericId && left.label == right.label && left.name < right.name))
    (concatMap (nodeName: attrValues peers.${nodeName}.exits) (attrNames peers));

  hexDigits = "0123456789abcdef";
  toHex = value:
    if value < 16
    then builtins.substring value 1 hexDigits
    else "${toHex (builtins.div value 16)}${builtins.substring (mod value 16) 1 hexDigits}";
  padHex = width: value: let
    rendered = toHex value;
    missing = width - builtins.stringLength rendered;
  in
    concatStringsSep "" (builtins.genList (_: "0") (
      if missing > 0
      then missing
      else 0
    ))
    + rendered;
  allocateExit = exit: let
    index = mod exit.label 10;
    mark = builtins.div exit.numericId 10 * 256 + mod exit.numericId 10 * 16 + index;
    nameBase = "${replace [","] [" "] exit.presentation.location} | ${exit.presentation.operator}";
  in
    exit
    // {
      inherit mark nameBase;
      markHex = "0x${padHex 3 mark}";
      table = 5000 + exit.numericId * 10 + index;
      mplsSelector = "${toString exit.numericId}/${toString exit.label}";
      signature = "${exit.presentation.operator}|${exit.presentation.location}";
    };

  centralValueFor = peers: let
    peerNames = attrNames peers;
    routerFor = name: let
      peer = peers.${name};
    in
      {
        id = peer.id;
        pubkey = peer.publicKey;
        numeric_id = peer.numericId;
        addresses = [peer.addresses.ipv4 peer.addresses.ipv6];
      }
      // (
        if defaults.tcpObfuscation
        then {tcp_obfuscation = true;}
        else {}
      )
      // (
        if peer.endpoints != []
        then {endpoints = peer.endpoints;}
        else {}
      );
  in {
    routers = map routerFor peerNames;
    graph =
      if length peerNames < 2
      then []
      else [(concatStringsSep ", " peerNames)];
  };

  renderCentralRouter = router:
    "  - id: ${quote router.id}\n"
    + "    pubkey: ${quote router.pubkey}\n"
    + (
      if getOr router "tcp_obfuscation" false
      then "    tcp_obfuscation: true\n"
      else ""
    )
    + "    numeric_id: ${toString router.numeric_id}\n"
    + "    addresses:\n"
    + concatStringsSep "" (map (address: "      - ${quote address}\n") router.addresses)
    + (
      if hasAttr "endpoints" router
      then "    endpoints:\n" + concatStringsSep "" (map (endpoint: "      - ${quote endpoint}\n") router.endpoints)
      else ""
    );
  renderCentral = value:
    "routers:\n"
    + concatStringsSep "" (map renderCentralRouter value.routers)
    + (
      if value.graph == []
      then "graph: []\n"
      else "graph:\n" + concatStringsSep "" (map (edge: "  - ${quote edge}\n") value.graph)
    );

  publicNodeValue = peer:
    {
      id = peer.id;
      port = defaults.port;
      interface_name = defaults.interfaceName;
      mtu = defaults.mtu;
      transit_cost = peer.transitCost;
      udp_cost = defaults.udpCost;
    }
    // (
      if peer.exits != {}
      then {advertise_exit_node = true;}
      else {}
    )
    // (
      if peer.binds != []
      then {binds = peer.binds;}
      else {}
    )
    // (
      if peer.lanDiscovery != []
      then {lan_discovery = peer.lanDiscovery;}
      else {}
    );
  renderPublicNode = value:
    "id: ${quote value.id}\n"
    + "port: ${toString value.port}\n"
    + "interface_name: ${quote value.interface_name}\n"
    + "mtu: ${toString value.mtu}\n"
    + (
      if getOr value "advertise_exit_node" false
      then "advertise_exit_node: true\n"
      else ""
    )
    + "transit_cost: ${quote value.transit_cost}\n"
    + "udp_cost: ${quote value.udp_cost}\n"
    + (
      if hasAttr "binds" value
      then
        "binds:\n"
        + concatStringsSep "" (map (bind:
          "  - interface: ${quote bind.interface}\n"
          + (
            if hasAttr "source" bind
            then "    source: ${quote bind.source}\n"
            else ""
          ))
        value.binds)
      else ""
    )
    + (
      if hasAttr "lan_discovery" value
      then "lan_discovery:\n" + concatStringsSep "" (map (interface: "  - ${quote interface}\n") value.lan_discovery)
      else ""
    );

  renderWlt = selector: outlets: let
    ordered = builtins.sort (left: right:
      left.displayName
      < right.displayName
      || (left.displayName == right.displayName && left.mplsSelector < right.mplsSelector))
    outlets;
    familyOutlets = family: filter (outlet: outlet.families.${family}) ordered;
    renderMap = shift: values:
      concatStringsSep "" (map (outlet: "${quote outlet.displayName} = 0x${padHex (
          if shift
          then 6
          else 3
        ) (
          if shift
          then outlet.mark * 4096
          else outlet.mark
        )}\n")
      values);
  in
    "[[outlet_groups]]\n"
    + "title = \"国内出口\"\n"
    + "[outlet_groups.outlets]\n"
    + renderMap true (familyOutlets "ipv4")
    + (
      if selector.ipv6
      then "[outlet_groups.outlets_v6]\n" + renderMap true (familyOutlets "ipv6")
      else ""
    )
    + "\n[[outlet_groups]]\n"
    + "title = \"海外出口\"\n"
    + "[outlet_groups.outlets]\n"
    + renderMap false (familyOutlets "ipv4")
    + (
      if selector.ipv6
      then "[outlet_groups.outlets_v6]\n" + renderMap false (familyOutlets "ipv6")
      else ""
    );

  cloudflareWarpsFor = peer:
    concatMap (underlayName: let
      underlay = peer.underlays.${underlayName};
      warp = getOr underlay "cloudflareWarp" null;
    in
      optional (warp != null) {
        interface = underlay.interface;
        inherit (warp) ipv6Address reserved;
      })
    (attrNames peer.underlays);

  selectorProjection = peer: catalog:
    if !peer.selector.enable
    then {
      inherit (peer.selector) enable;
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
    }
    else let
      localSignatures = map (exit: "${exit.presentation.operator}|${exit.presentation.location}") (attrValues peer.exits);
      eligible = filter (exit:
        exit.nodeId
        != peer.id
        && !elem exit.signature localSignatures)
      catalog;
      duplicateNames = unique (map (exit: exit.nameBase) (filter (candidate:
        count (exit: exit.nameBase == candidate.nameBase) eligible > 1)
      eligible));
      outlets = map (exit:
        exit
        // {
          displayName =
            if elem exit.nameBase duplicateNames
            then "${exit.nameBase} (${exit.nodeId})"
            else exit.nameBase;
        })
      eligible;
      ipv4Outlets = filter (exit: exit.families.ipv4) outlets;
      ipv6Outlets =
        if peer.selector.ipv6
        then filter (exit: exit.families.ipv6) outlets
        else [];
      ruleFor = exit: "fwmark ${exit.markHex}/0xfff lookup ${toString exit.table}";
      routeFor = exit: "route replace default encap mpls ${exit.mplsSelector} dev ${defaults.interfaceName} table ${toString exit.table}";
    in {
      inherit (peer.selector) enable;
      inherit outlets;
      rules = {
        ipv4 = map ruleFor ipv4Outlets;
        ipv6 = map ruleFor ipv6Outlets;
      };
      routes = {
        ipv4 = map routeFor ipv4Outlets;
        ipv6 = map routeFor ipv6Outlets;
      };
      ownedTables = unique (map (exit: exit.table) (ipv4Outlets ++ ipv6Outlets));
      wlt.text = renderWlt peer.selector outlets;
    };

  dnsFor = peers: let
    zone = mesh.dns.zone;
    ttl = mesh.dns.ttl;
    controller = mesh.dns.controller;
    apiUrl = mesh.dns.apiUrl;
    rrsets = concatMap (name: let
      peer = peers.${name};
      record = type: content: {
        name = "${name}.${zone}";
        inherit type ttl;
        records = [
          {
            inherit content;
            disabled = false;
          }
        ];
      };
    in [
      (record "A" peer.addresses.ipv4)
      (record "AAAA" peer.addresses.ipv6)
    ]) (attrNames peers);
    value = {inherit zone rrsets;};
    text = builtins.toJSON value + "\n";
  in {
    inherit zone ttl controller apiUrl rrsets value text;
  };

  compiled = let
    peers = normalizedManaged;
    peerNames = attrNames peers;
    rawExits = exitListFor peers;
    catalog = map allocateExit rawExits;
    centralValue = centralValueFor peers;
    centralText = renderCentral centralValue;
    central = {
      value = centralValue;
      text = centralText;
      sha256 = builtins.hashString "sha256" centralText;
    };
    selectors = filter (name: normalizedManaged.${name}.selector.enable) managedNames;
    selectorProjections = listToAttrs (map (name: {
        inherit name;
        value = selectorProjection normalizedManaged.${name} catalog;
      })
      selectors);
    perHost =
      mapAttrs (_: peer: let
        nodeValue = publicNodeValue peer;
        cloudflareWarps = cloudflareWarpsFor peer;
        projection =
          if hasAttr peer.id selectorProjections
          then selectorProjections.${peer.id}
          else selectorProjection peer catalog;
      in {
        central = {inherit (central) text;};
        publicNode = {
          value = nodeValue;
          text = renderPublicNode nodeValue;
        };
        expectedPublicKey = peer.publicKey;
        exits =
          mapAttrs (_: exit: {
            inherit (exit) families gateway4 interface ipv4Address ipv6Address label useDefaultRoute;
          })
          peer.exits;
        cloudflareWarp =
          if cloudflareWarps == []
          then null
          else builtins.head cloudflareWarps;
        selector = {
          inherit (projection) enable ownedTables routes rules wlt;
        };
      })
      normalizedManaged;
    dns = dnsFor peers;
    manifestValue = {
      schemaVersion = 1;
      inherit peerNames;
      selectors = selectors;
      counts = {
        peers = length peerNames;
        exits = length catalog;
        selectors = length selectors;
        dnsRrsets = length dns.rrsets;
      };
      centralSha256 = central.sha256;
      exitCatalog = catalog;
      selectorRouting =
        mapAttrs (_: projection: {
          inherit (projection) outlets rules routes ownedTables;
        })
        selectorProjections;
      nodes =
        mapAttrs (_: peer: {
          inherit (peer) numericId publicKey addresses endpoints;
          exitNames = attrNames peer.exits;
          selector = peer.selector;
        })
        peers;
      dns = {
        inherit (dns) zone ttl controller apiUrl rrsets;
      };
    };
    manifestText = builtins.toJSON manifestValue + "\n";
  in {
    topology = {
      inherit peerNames peers catalog;
      selectors = selectors;
    };
    inherit central perHost dns;
    wlt.selectors = selectorProjections;
    manifest = {
      value = manifestValue;
      text = manifestText;
      sha256 = builtins.hashString "sha256" manifestText;
    };
  };

  peerChecks = rawPeers: normalizedPeers:
    concatMap (name: let
      raw = rawPeers.${name};
      peer = normalizedPeers.${name};
      rawSelector = getOr raw "selector" {};
      underlays = getOr raw "underlays" {};
      underlayChecks = concatMap (
        underlayName: let
          underlay = underlays.${underlayName};
          endpoint = getOr underlay "endpoint" {};
          warp = getOr underlay "cloudflareWarp" null;
          bind = getOr underlay "bind" (endpoint != {});
          bindSource = getOr underlay "bindSource" false;
          interface = getOr underlay "interface" null;
          exit = getOr underlay "exit" null;
          families =
            if exit == null
            then {}
            else getOr exit "families" {};
          presentation =
            if exit == null
            then {}
            else getOr exit "presentation" {};
          useDefaultRoute =
            if exit == null
            then false
            else getOr exit "useDefaultRoute" false;
        in
          schemaChecks "${name}.${underlayName}" underlayFields underlay
          ++ schemaChecks "${name}.${underlayName}.endpoint" endpointFields endpoint
          ++ (
            if warp == null
            then []
            else schemaChecks "${name}.${underlayName}.cloudflareWarp" cloudflareWarpFields warp
          )
          ++ [
            (ensure (isNonEmptyString interface) "${name}.${underlayName}: interface must be a non-empty string")
            (ensure (builtins.isBool bind) "${name}.${underlayName}: bind must be a boolean")
            (ensure (builtins.isBool bindSource) "${name}.${underlayName}: bindSource must be a boolean")
            (ensure (builtins.isBool (getOr underlay "lanDiscovery" false))
              "${name}.${underlayName}: lanDiscovery must be a boolean")
            (ensure (!bindSource || bind) "${name}.${underlayName}: bindSource=true conflicts with bind=false")
            (ensure (!bindSource || endpoint != {}) "${name}.${underlayName}: bindSource requires an endpoint address")
            (ensure (builtins.all (family: !hasAttr family endpoint || isIpLiteral family endpoint.${family}) ["ipv4" "ipv6"])
              "${name}.${underlayName}: endpoint must contain explicit IP literals")
          ]
          ++ (
            if exit == null
            then []
            else
              schemaChecks "${name}.${underlayName}.exit" exitFields exit
              ++ schemaChecks "${name}.${underlayName}.exit.families" exitFamilyFields families
              ++ schemaChecks "${name}.${underlayName}.exit.presentation" presentationFields presentation
              ++ [
                (ensure (builtins.isInt (getOr exit "label" null)) "${name}.${underlayName}: exit label must be an integer")
                (ensure (builtins.isBool (getOr families "ipv4" null) && builtins.isBool (getOr families "ipv6" null))
                  "${name}.${underlayName}: exit family flags must be booleans")
                (ensure (getOr families "ipv4" false || getOr families "ipv6" false)
                  "${name}.${underlayName}: exit must support at least one address family")
                (ensure (builtins.isBool useDefaultRoute) "${name}.${underlayName}: useDefaultRoute must be a boolean")
                (ensure (isNonEmptyString (getOr presentation "location" null) && isNonEmptyString (getOr presentation "operator" null))
                  "${name}.${underlayName}: exit presentation requires location and operator")
                (ensure (!hasAttr "gateway4" exit || isIpv4Literal exit.gateway4)
                  "${name}.${underlayName}: gateway4 must be an IPv4 literal")
                (ensure (!hasAttr "ipv4Address" exit || isIpv4Literal exit.ipv4Address)
                  "${name}.${underlayName}: ipv4Address must be an IPv4 literal")
                (ensure (!hasAttr "ipv6Address" exit || isIpv6Literal exit.ipv6Address)
                  "${name}.${underlayName}: ipv6Address must be an IPv6 literal")
              ]
          )
      ) (attrNames underlays);
      selector = peer.selector;
      exitLabels = map (exit: exit.label) (attrValues peer.exits);
      cloudflareWarps = concatMap (underlayName:
        optional (hasAttr "cloudflareWarp" underlays.${underlayName}) {
          inherit underlayName;
          underlay = underlays.${underlayName};
          warp = underlays.${underlayName}.cloudflareWarp;
        })
      (attrNames underlays);
    in
      schemaChecks name nodeFields raw
      ++ schemaChecks "${name}.selector" selectorFields rawSelector
      ++ [
        (ensure (builtins.match "^[a-z0-9][a-z0-9-]*$" name != null) "${name}: node name is not a valid host label")
        (ensure (builtins.isInt peer.numericId && peer.numericId > 0 && peer.numericId < 256)
          "${name}: numericId must be an integer in 1..255")
        (ensure (isPublicKey peer.publicKey) "${name}: publicKey must be a 44-character base64 key")
        (ensure (isNonEmptyString peer.transitCost) "${name}: transitCost must be a non-empty string")
        (ensure (isIpv4Literal peer.addresses.ipv4 && isIpv6Literal peer.addresses.ipv6)
          "${name}: overlay prefixes and numericId must derive valid addresses")
        (ensure (builtins.isBool selector.enable && builtins.isBool selector.ipv6)
          "${name}: selector enable/ipv6 must be booleans")
        (ensure (allUnique exitLabels) "${name}: exit labels must be unique")
        (ensure (allUnique (map builtins.toJSON peer.binds)) "${name}: generated binds conflict")
        (ensure (allUnique (map (entry: entry.address) peer.endpointEntries))
          "${name}: endpoint addresses must be unique per node")
        (ensure (length cloudflareWarps <= 1) "${name}: at most one Cloudflare WARP underlay is supported")
        (ensure (builtins.all (entry:
          hasAttr "exit" entry.underlay
          && isIpv6Literal (getOr entry.warp "ipv6Address" null)
          && builtins.isString (getOr entry.warp "reserved" null)
          && builtins.match "^0x[0-9A-Fa-f]{6}$" entry.warp.reserved != null)
        cloudflareWarps) "${name}: Cloudflare WARP requires an exit, IPv6 address, and 24-bit reserved value")
      ]
      ++ underlayChecks)
    (attrNames rawPeers);

  allocationChecks = view: let
    catalog = view.topology.catalog;
    marks = map (exit: exit.mark) catalog;
    tables = map (exit: exit.table) catalog;
    selectors = map (exit: exit.mplsSelector) catalog;
    selectorOutputs = attrValues view.wlt.selectors;
  in [
    (ensure (builtins.all (exit:
      exit.numericId
      >= 16
      && exit.numericId <= 99
      && exit.label >= 100
      && exit.label <= 109)
    catalog) "fleet: exit selector IDs cannot be encoded as 0xNNI")
    (ensure (allUnique marks) "fleet: generated WLT marks conflict")
    (ensure (allUnique tables) "fleet: generated routing tables conflict")
    (ensure (allUnique selectors) "fleet: generated MPLS selectors conflict")
    (ensure (builtins.all (selector:
      allUnique (map (outlet: outlet.displayName) selector.outlets))
    selectorOutputs) "fleet: generated WLT outlet names conflict")
  ];

  allPeers = attrValues normalizedManaged;
  forbiddenMembers = ["google" "los6" "oracle" "el2-install"];
  expected = mesh.expected;
  checks =
    [
      (ensure (builtins.isList deployableHosts) "deployableHosts must be a list")
      (ensure (allUnique deployableHosts) "deployableHosts must not contain duplicates")
      (ensure (builtins.isInt defaults.port && defaults.port > 0 && defaults.port <= 65535)
        "defaults.port must be in 1..65535")
      (ensure (builtins.isInt defaults.mtu && defaults.mtu > 0) "defaults.mtu must be positive")
      (ensure (isNonEmptyString defaults.interfaceName) "defaults.interfaceName must be non-empty")
      (ensure (builtins.isBool defaults.tcpObfuscation) "defaults.tcpObfuscation must be boolean")
      (ensure (isNonEmptyString defaults.udpCost && isNonEmptyString defaults.transitCost)
        "default UDP and transit costs must be non-empty strings")
      (ensure (isNonEmptyString mesh.overlay.ipv4Prefix && isNonEmptyString mesh.overlay.ipv6Prefix)
        "overlay prefixes must be non-empty strings")
      (ensure (mesh.topology.kind == "full-mesh") "only topology.kind=full-mesh is supported")
      (ensure (isNonEmptyString mesh.dns.zone && builtins.match ".*\\.$" mesh.dns.zone != null)
        "dns.zone must be an absolute zone name ending in a dot")
      (ensure (builtins.isInt mesh.dns.ttl && mesh.dns.ttl > 0) "dns.ttl must be a positive integer")
      (ensure (elem mesh.dns.controller managedNames) "dns.controller must be a managed Nylon node")
      (ensure (isNonEmptyString mesh.dns.apiUrl) "dns.apiUrl must be a non-empty string")
      (ensure (builtins.isInt expected.nodeCount && builtins.isInt expected.exitCount && builtins.isInt expected.selectorCount)
        "expected fleet counts must be integers")
      (ensure (builtins.all (name: elem name deployableHosts) managedNames)
        "every managed Nylon node must be a deployable NixOS host")
      (ensure (builtins.all (name: !elem name managedNames) forbiddenMembers)
        "google, los6, oracle, and el2-install cannot be managed Nylon members")
      (ensure (builtins.all (peer: !elem peer.numericId mesh.reservedNumericIds) allPeers)
        "managed nodes cannot use a reserved numeric ID")
      (ensure (allUnique (map (peer: peer.numericId) allPeers)) "numeric IDs must be unique")
      (ensure (allUnique (map (peer: peer.addresses.ipv4) allPeers)) "overlay IPv4 addresses must be unique")
      (ensure (allUnique (map (peer: peer.addresses.ipv6) allPeers)) "overlay IPv6 addresses must be unique")
      (ensure (allUnique (map (peer: peer.publicKey) allPeers)) "public keys must be unique")
      (ensure (allUnique (concatMap (peer: peer.endpoints) allPeers)) "transport endpoints must be unique")
      (ensure (length managedNames == expected.nodeCount)
        "final node count is ${toString (length managedNames)}, expected ${toString expected.nodeCount}")
      (ensure (length compiled.topology.catalog == expected.exitCount)
        "exit count is ${toString (length compiled.topology.catalog)}, expected ${toString expected.exitCount}")
      (ensure (length compiled.topology.selectors == expected.selectorCount)
        "selector count is ${toString (length compiled.topology.selectors)}, expected ${toString expected.selectorCount}")
    ]
    ++ peerChecks nodes normalizedManaged
    ++ allocationChecks compiled;
in
  builtins.deepSeq checks compiled
