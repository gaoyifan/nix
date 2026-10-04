{
  name = "home-router-devices";
  panels = builtins.concatMap (direction: let
    id =
      if direction == "upload"
      then 1
      else 2;
    title =
      if direction == "upload"
      then "Upload"
      else "Download";
    selector = ''home_router_device_bytes_total{job="node",lan=~"$lan",direction="${direction}"}'';
    names = ''* on (instance, lan, device_id) group_left(name) home_router_device_info{job="node",lan=~"$lan"}'';
    usage = ''sum by (instance, lan, device_id) (increase(${selector}[$__range]))'';
  in [
    {
      inherit id;
      title = "Device ${title} Rate";
      queries = [
        {
          refId = "A";
          query = {
            expr = ''sum by (instance, lan, device_id) (rate(${selector}[$__rate_interval])) ${names} * 8'';
            legendFormat = "{{name}} ({{lan}})";
            range = true;
          };
        }
      ];
      visualization = {
        type = "timeseries";
        fillOpacity = 0;
        legendCalcs = ["lastNotNull" "max"];
        fieldDefaults = {
          color.mode = "palette-classic";
          min = 0;
          unit = "bps";
        };
      };
    }
    {
      id = id + 2;
      title = "Device ${title} in Selected Period";
      queries = [
        {
          refId = "A";
          query = {
            expr = ''(${usage} ${names}) or on (instance, lan, device_id) label_replace(${usage}, "name", "$1", "device_id", "(.*)")'';
            instant = true;
            range = false;
            format = "table";
          };
        }
      ];
      transformations = [
        {
          id = "organize";
          options = {
            excludeByName = {
              Time = true;
              instance = true;
            };
            indexByName = {
              name = 0;
              lan = 1;
              device_id = 2;
              Value = 3;
            };
            renameByName = {
              name = "Device";
              lan = "LAN";
              device_id = "Identity";
              Value = "Bytes";
            };
          };
        }
      ];
      visualization = {
        type = "table";
        options = {
          showHeader = true;
          sortBy = [
            {
              displayName = "Bytes";
              desc = true;
            }
          ];
        };
        fieldDefaults = {};
        overrides = [
          {
            matcher = {
              id = "byName";
              options = "Bytes";
            };
            properties = [
              {
                id = "unit";
                value = "bytes";
              }
            ];
          }
        ];
      };
    }
  ]) ["upload" "download"];
  rows = [
    {
      title = "Rates";
      panels = [1 2];
      maxColumnCount = 2;
      rowHeightMode = "standard";
    }
    {
      title = "Usage";
      panels = [3 4];
      maxColumnCount = 2;
      rowHeightMode = "standard";
    }
  ];
  tags = ["home-router" "devices"];
  timeFrom = "now-24h";
  title = "Home Router Devices";
}
