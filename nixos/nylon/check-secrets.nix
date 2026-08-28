# Production-only boundary check for Nylon's encrypted inputs. Callers must
# invoke this only when the private secrets submodule is available.
{
  filesDir,
  nodes,
  powerDnsController,
  recipientRules,
}: let
  inherit (builtins) all any attrNames attrValues filter hasAttr isAttrs isList isString length map pathExists;

  checkError = message: throw "Nylon production secrets: ${message}";
  ensure = condition: message:
    if condition
    then true
    else checkError message;
  isNonEmptyString = value: isString value && value != "";

  nodeNames = attrNames nodes;
  nodePaths = map (name: "nixos/${name}/nylon-private-key.age") nodeNames;
  hasCloudflareWarp = node:
    any
    (underlay: isAttrs underlay && hasAttr "cloudflareWarp" underlay)
    (attrValues (node.underlays or {}));
  warpHosts = filter (name: hasCloudflareWarp nodes.${name}) nodeNames;
  warpPaths = map (name: "nixos/${name}/wg-cloudflare-private-key.age") warpHosts;
  powerDnsPaths = ["nixos/${powerDnsController}/nylon-powerdns-api-key.age"];
  requiredPaths = nodePaths ++ warpPaths ++ powerDnsPaths;

  checkPath = relativePath: let
    rule =
      if hasAttr relativePath recipientRules
      then recipientRules.${relativePath}
      else null;
    publicKeys =
      if isAttrs rule && hasAttr "publicKeys" rule
      then rule.publicKeys
      else null;
  in
    ensure (pathExists (filesDir + "/${relativePath}")) "missing ciphertext ${relativePath}"
    && ensure (isAttrs rule) "missing recipient rule for ${relativePath}"
    && ensure (isList publicKeys) "recipient rule for ${relativePath} must define publicKeys as a list"
    && ensure (publicKeys != []) "recipient rule for ${relativePath} must not be empty"
    && ensure (all isNonEmptyString publicKeys) "recipient rule for ${relativePath} contains an empty or non-string key";
in
  assert ensure (isAttrs nodes) "nodes must be an attribute set";
  assert ensure (isNonEmptyString powerDnsController) "powerDnsController must be a non-empty string";
  assert ensure (isAttrs recipientRules) "recipientRules must be an attribute set";
  assert all checkPath requiredPaths; {
    checked = length requiredPaths;
    nodeKeys = length nodePaths;
    warpKeys = length warpPaths;
    powerDnsKeys = length powerDnsPaths;
  }
