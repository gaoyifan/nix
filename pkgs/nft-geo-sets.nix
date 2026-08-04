{
  pkgs,
  inputs,
}:
pkgs.runCommand "nft-geo-sets" {} ''
  mkdir -p $out
  gen() {
    local set_name=$1 type=$2 src=$3
    {
      echo "set $set_name {"
      echo "  type $type"
      echo "  flags constant, interval"
      echo "  elements = {"
      awk '!/^#/ && NF { printf("    %s,\n", $1) }' "$src"
      echo "  }"
      echo "}"
    } > "$out/set-$set_name.conf"
  }
  gen cn ipv4_addr ${inputs.chnroutes2}/chnroutes.txt
  gen cn6 ipv6_addr ${inputs.china-operator-ip}/china6.txt
  gen cernet ipv4_addr ${inputs.china-operator-ip}/cernet.txt
  gen chinanet ipv4_addr ${inputs.china-operator-ip}/chinanet.txt
  gen cmcc ipv4_addr ${inputs.china-operator-ip}/cmcc.txt
''
