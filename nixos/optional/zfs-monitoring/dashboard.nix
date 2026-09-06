let
  pool = ''pool=~"$pool"'';
  properties = name: ''${name}{job="zfs",${pool}}'';
  vdev = name: ''${name}{job="zfs-vdev",${pool}}'';
  dataset = name: ''${name}{job="zfs",${pool},name=~"$dataset"}'';
  query = expr: legendFormat: {inherit expr legendFormat;};
  mapping = values: [
    {
      type = "value";
      options = values;
    }
  ];
  poolHealth = mapping {
    "0" = {
      text = "Online";
      color = "green";
    };
    "1" = {
      text = "Degraded";
      color = "red";
    };
    "2" = {
      text = "Faulted";
      color = "red";
    };
    "3" = {
      text = "Offline";
      color = "red";
    };
    "4" = {
      text = "Unavailable";
      color = "red";
    };
    "5" = {
      text = "Removed";
      color = "red";
    };
    "6" = {
      text = "Suspended";
      color = "red";
    };
  };
  errors = {
    "custom.cellOptions".type = "color-text";
    color.mode = "thresholds";
    thresholds = {
      mode = "absolute";
      steps = [
        {
          color = "green";
          value = null;
        }
        {
          color = "red";
          value = 1;
        }
      ];
    };
    decimals = 0;
  };
  table = {
    id,
    title,
    key,
    columns,
  }: {
    inherit id title;
    type = "table";
    queries = map (column: (query column.expr "") // {format = "table";}) columns;
    transformations = [
      {
        kind = "Transformation";
        group = "joinByField";
        spec.options = {
          byField = key;
          mode = "outerTabular";
        };
      }
      {
        kind = "Transformation";
        group = "filterFieldsByName";
        spec.options.include.pattern = "^(${key}|Value #[A-Z])$";
      }
      {
        kind = "Transformation";
        group = "organize";
        spec.options = {
          indexByName = builtins.listToAttrs ([
              {
                name = key;
                value = 0;
              }
            ]
            ++ builtins.genList (i: {
              name = "Value #${builtins.substring i 1 "ABCDEFGHIJKLMNOPQRSTUVWXYZ"}";
              value = i + 1;
            }) (builtins.length columns));
          renameByName = builtins.listToAttrs (builtins.genList (i: {
            name = "Value #${builtins.substring i 1 "ABCDEFGHIJKLMNOPQRSTUVWXYZ"}";
            value = (builtins.elemAt columns i).name;
          }) (builtins.length columns));
        };
      }
    ];
    fieldDefaults.custom = {
      width = 145;
      cellOptions.type = "auto";
      filterable = true;
    };
    options = {
      showHeader = true;
      cellHeight = "sm";
      sortBy = [
        {
          displayName = key;
          desc = false;
        }
      ];
    };
    overrides =
      [
        {
          matcher = {
            id = "byName";
            options = key;
          };
          properties = [
            {
              id = "custom.width";
              value =
                if key == "pool"
                then 160
                else 420;
            }
          ];
        }
      ]
      ++ map (column: {
        matcher = {
          id = "byName";
          options = column.name;
        };
        properties = let
          values = column.fields or {};
        in
          map (name: {
            id = name;
            value = values.${name};
          }) (builtins.attrNames values);
      })
      columns;
  };
  poolValue = expr: ''max by (pool) (${expr})'';
  deviceValue = expr: ''label_join(${expr}, "Device", " / ", "pool", "vdev", "path")'';
  panel = {
    id,
    title,
    queries,
    type ? "timeseries",
    unit ? "short",
    fieldDefaults ? {},
    options ? {},
    overrides ? [],
    transformations ? [],
  }: {
    inherit id title transformations;
    conditionalRendering = {
      kind = "ConditionalRenderingGroup";
      spec = {
        visibility = "show";
        condition = "and";
        items = [
          {
            kind = "ConditionalRenderingData";
            spec.value = true;
          }
        ];
      };
    };
    queries = builtins.genList (i: {
      refId = builtins.substring i 1 "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
      query =
        (builtins.elemAt queries i)
        // {
          instant = type != "timeseries";
          range = type == "timeseries";
        };
    }) (builtins.length queries);
    visualization =
      {
        inherit type overrides;
        fieldDefaults =
          {
            inherit unit;
            min = 0;
            noValue = "Unknown";
            color.mode = "palette-classic";
          }
          // fieldDefaults;
      }
      // (
        if type == "timeseries"
        then {
          fillOpacity = 0;
          legendCalcs = ["lastNotNull" "max"];
        }
        else if type == "stat"
        then {
          options =
            {
              colorMode = "value";
              graphMode = "none";
            }
            // options;
        }
        else {inherit options;}
      );
  };
in {
  name = "zfs-overview";
  title = "ZFS Storage";
  tags = ["storage" "zfs"];
  timeFrom = "now-24h";
  panels = map panel [
    {
      id = 1;
      title = "Collectors";
      type = "stat";
      queries = [
        (query ''up{job=~"zfs|zfs-vdev|zfs-arc"}'' "{{job}}")
        (query ''zfs_scrape_collector_success{job="zfs"}'' "{{collector}}")
        (query ''node_scrape_collector_success{job="zfs-arc",collector="zfs"}'' "ARC")
      ];
      fieldDefaults.mappings = mapping {
        "0" = {
          text = "Failed";
          color = "red";
        };
        "1" = {
          text = "OK";
          color = "green";
        };
      };
    }
    (table {
      id = 2;
      title = "Pool Health and Capacity";
      key = "pool";
      columns = [
        {
          name = "Health";
          expr = poolValue (properties "zfs_pool_health");
          fields = {
            mappings = poolHealth;
            "custom.cellOptions".type = "color-text";
          };
        }
        {
          name = "Used";
          expr = poolValue ''100 * ${properties "zfs_pool_allocated_bytes"} / ${properties "zfs_pool_size_bytes"}'';
          fields.unit = "percent";
        }
        {
          name = "Allocated";
          expr = poolValue (properties "zfs_pool_allocated_bytes");
          fields.unit = "bytes";
        }
        {
          name = "Pool Free";
          expr = poolValue (properties "zfs_pool_free_bytes");
          fields.unit = "bytes";
        }
        {
          name = "Fragmentation";
          expr = poolValue (properties "zfs_pool_fragmentation_ratio");
          fields.unit = "percentunit";
        }
        {
          name = "Data Errors";
          expr = poolValue (vdev "zfs_pool_errors");
          fields = errors;
        }
      ];
    })
    (table {
      id = 3;
      title = "Device Health and Cumulative Errors";
      key = "Device";
      columns = [
        {
          name = "State";
          expr = ''max by (Device) (${deviceValue ''zfs_vdev_state{job="zfs-vdev",${pool},path!=""}''})'';
          fields = {
            "custom.cellOptions".type = "color-text";
            mappings = mapping {
              "0" = {
                text = "Unknown";
                color = "gray";
              };
              "1" = {
                text = "Closed";
                color = "red";
              };
              "2" = {
                text = "Offline";
                color = "red";
              };
              "3" = {
                text = "Removed";
                color = "red";
              };
              "4" = {
                text = "Unavailable";
                color = "red";
              };
              "5" = {
                text = "Faulted";
                color = "red";
              };
              "6" = {
                text = "Degraded";
                color = "red";
              };
              "7" = {
                text = "Online";
                color = "green";
              };
            };
          };
        }
        {
          name = "Read Errors";
          expr = ''max by (Device) (${deviceValue ''zfs_vdev_errors{job="zfs-vdev",${pool},path!="",type="read"}''})'';
          fields = errors;
        }
        {
          name = "Write Errors";
          expr = ''max by (Device) (${deviceValue ''zfs_vdev_errors{job="zfs-vdev",${pool},path!="",type="write"}''})'';
          fields = errors;
        }
        {
          name = "Checksum Errors";
          expr = ''max by (Device) (${deviceValue ''zfs_vdev_errors{job="zfs-vdev",${pool},path!="",type="checksum"}''})'';
          fields = errors;
        }
      ];
    })
    (table {
      id = 4;
      title = "Most Recent Scrub / Resilver";
      key = "pool";
      columns = [
        {
          name = "Operation";
          expr = poolValue (vdev "zfs_pool_scan_func");
          fields.mappings = mapping {
            "0".text = "None";
            "1".text = "Scrub";
            "2".text = "Resilver";
            "3".text = "Rebuild";
          };
        }
        {
          name = "State";
          expr = poolValue (vdev "zfs_pool_scan_state");
          fields.mappings = mapping {
            "0".text = "None";
            "1".text = "Running";
            "2".text = "Finished";
            "3" = {
              text = "Cancelled";
              color = "red";
            };
          };
        }
        {
          name = "Started";
          expr = poolValue ''1000 * (${vdev "zfs_pool_scan_start_time_seconds"} > 0)'';
          fields = {
            unit = "dateTimeAsIso";
            "custom.width" = 220;
          };
        }
        {
          name = "Completed";
          expr = poolValue ''1000 * (${vdev "zfs_pool_scan_end_time_seconds"} > 0) and on (pool) (${vdev "zfs_pool_scan_state"} == 2)'';
          fields = {
            unit = "dateTimeAsIso";
            "custom.width" = 220;
          };
        }
        {
          name = "Errors";
          expr = poolValue (vdev "zfs_pool_scan_errors");
          fields = errors;
        }
      ];
    })
    {
      id = 5;
      title = "Pool Space Used";
      unit = "percent";
      queries = [(query ''100 * ${properties "zfs_pool_allocated_bytes"} / ${properties "zfs_pool_size_bytes"}'' "{{pool}}")];
    }
    {
      id = 6;
      title = "Top-level Vdev Space Used";
      unit = "percent";
      queries = [(query ''100 * zfs_vdev_space_allocated_bytes{job="zfs-vdev",${pool},path="",vdev!="root"} / zfs_vdev_space_capacity_bytes{job="zfs-vdev",${pool},path="",vdev!="root"}'' "{{pool}} {{vdev}}")];
    }
    {
      id = 7;
      title = "Pool I/O Throughput";
      unit = "Bps";
      queries = [(query ''rate(zfs_vdev_bytes{job="zfs-vdev",${pool},vdev="root",path="",type=~"read|write"}[$__rate_interval])'' "{{pool}} {{type}}")];
    }
    {
      id = 8;
      title = "Pool IOPS";
      unit = "iops";
      queries = [(query ''rate(zfs_vdev_ops{job="zfs-vdev",${pool},vdev="root",path="",type=~"read|write"}[$__rate_interval])'' "{{pool}} {{type}}")];
    }
    {
      id = 9;
      title = "Device I/O Latency — p95";
      unit = "s";
      queries = [(query ''histogram_quantile(0.95, sum by (le, pool, path, type) (rate(zfs_vdev_zio_latency_total_bucket{job="zfs-vdev",${pool},path!=""}[$__rate_interval])))'' "{{pool}} {{path}} {{type}}")];
    }
    {
      id = 10;
      title = "Device Pending I/O";
      queries = [(query ''sum by (pool, path) (zfs_vdev_queue_pending_length{job="zfs-vdev",${pool},path!=""})'' "{{pool}} {{path}}")];
    }
    {
      id = 11;
      title = "New Device Errors — 5 Minutes";
      queries = [(query ''increase(zfs_vdev_errors{job="zfs-vdev",${pool},path!="",type=~"read|write|checksum"}[5m])'' "{{pool}} {{path}} {{type}}")];
    }
    {
      id = 12;
      title = "Active Scrub / Resilver Progress";
      unit = "percent";
      queries = [(query ''100 * ${vdev "zfs_pool_scan_examined_bytes"} / (${vdev "zfs_pool_scan_to_examine_bytes"} > 0) and on (pool) (${vdev "zfs_pool_scan_state"} == 1)'' "{{pool}}")];
    }
    {
      id = 13;
      title = "Host ARC Size and Target";
      unit = "bytes";
      queries = [(query ''node_zfs_arc_size{job="zfs-arc"}'' "ARC size") (query ''node_zfs_arc_c{job="zfs-arc"}'' "ARC target")];
    }
    {
      id = 14;
      title = "Host ARC Demand Hit Rate";
      unit = "percent";
      queries = map (kind: query ''100 * rate(node_zfs_arc_demand_${kind}_hits{job="zfs-arc"}[$__rate_interval]) / (rate(node_zfs_arc_demand_${kind}_hits{job="zfs-arc"}[$__rate_interval]) + rate(node_zfs_arc_demand_${kind}_misses{job="zfs-arc"}[$__rate_interval]))'' kind) ["data" "metadata"];
    }
    (table {
      id = 15;
      title = "Dataset Space (Used Includes Children)";
      key = "name";
      columns = [
        {
          name = "Used";
          expr = ''max by (name) (${dataset "zfs_dataset_used_bytes"})'';
          fields.unit = "bytes";
        }
        {
          name = "Available";
          expr = ''max by (name) (${dataset "zfs_dataset_available_bytes"})'';
          fields.unit = "bytes";
        }
        {
          name = "Referenced";
          expr = ''max by (name) (${dataset "zfs_dataset_referenced_bytes"})'';
          fields.unit = "bytes";
        }
        {
          name = "Snapshots";
          expr = ''max by (name) (${dataset "zfs_dataset_used_by_snapshot_bytes"})'';
          fields.unit = "bytes";
        }
        {
          name = "Quota";
          expr = ''max by (name) (${dataset "zfs_dataset_quota_bytes"})'';
          fields = {
            unit = "bytes";
            mappings = mapping {"0".text = "Unlimited";};
          };
        }
        {
          name = "Refquota";
          expr = ''max by (name) (${dataset "zfs_dataset_referenced_quota_bytes"})'';
          fields = {
            unit = "bytes";
            mappings = mapping {"0".text = "Unlimited";};
          };
        }
      ];
    })
    {
      id = 16;
      title = "Snapshot Space by Dataset";
      unit = "bytes";
      queries = [(query (dataset "zfs_dataset_used_by_snapshot_bytes") "{{name}}")];
    }
    {
      id = 17;
      title = "Dataset Available Space";
      unit = "bytes";
      queries = [(query (dataset "zfs_dataset_available_bytes") "{{name}}")];
    }
  ];
  rows = [
    {
      title = "Collection";
      panels = [1];
      maxColumnCount = 1;
      rowHeight = 100;
    }
    {
      title = "Pools";
      panels = [2];
      maxColumnCount = 1;
      rowHeight = 180;
    }
    {
      title = "Devices";
      panels = [3];
      maxColumnCount = 1;
      rowHeight = 400;
    }
    {
      title = "Scans";
      panels = [4];
      maxColumnCount = 1;
      rowHeight = 180;
    }
    {
      title = "Capacity and I/O";
      panels = [5 6 7 8 9 10 11 12];
      columnWidth = 450;
      maxColumnCount = 2;
      rowHeightMode = "standard";
    }
    {
      title = "ARC";
      panels = [13 14];
      columnWidth = 450;
      maxColumnCount = 2;
      rowHeightMode = "standard";
    }
    {
      title = "Datasets";
      panels = [15];
      maxColumnCount = 1;
      rowHeight = 400;
    }
    {
      title = "Dataset trends";
      panels = [16 17];
      columnWidth = 450;
      maxColumnCount = 2;
      rowHeightMode = "standard";
    }
  ];
}
