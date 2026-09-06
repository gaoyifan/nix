let
  selector = ''job="smartctl",device=~"$device"'';
  metric = name: ''${name}{${selector}}'';
  query = refId: expr: legendFormat: {
    inherit refId;
    query = {inherit expr legendFormat;};
  };
  panel = {
    id,
    title,
    queries,
    unit ? "short",
    type ? "timeseries",
    fieldDefaults ? {},
    transformations ? [],
    overrides ? [],
    options ? {},
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
    queries = map (value:
      value
      // {
        query =
          value.query
          // {
            instant = type != "timeseries";
            range = type == "timeseries";
          };
      })
    queries;
    visualization =
      {
        inherit type overrides;
        fieldDefaults =
          {
            inherit unit;
            min = 0;
            noValue = "Unknown / unsupported";
            color.mode = "palette-classic";
          }
          // fieldDefaults;
      }
      // (
        if type == "stat"
        then {
          options = {
            colorMode = "value";
            graphMode = "none";
          };
        }
        else if type == "table"
        then {inherit options;}
        else {
          fillOpacity = 0;
          legendCalcs = ["lastNotNull" "max"];
        }
      );
  };
  unknownMapping = {
    type = "special";
    options = {
      match = "null";
      result = {
        text = "Unknown";
        color = "gray";
      };
    };
  };
  errorThresholds = {
    color.mode = "thresholds";
    decimals = 0;
    mappings = [unknownMapping];
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
  };
  healthMappings = good: bad: [
    {
      type = "value";
      options = {
        "0" = {
          text = bad;
          color = "red";
        };
        "1" = {
          text = good;
          color = "green";
        };
      };
    }
    unknownMapping
  ];
  override = name: properties: {
    matcher = {
      id = "byName";
      options = name;
    };
    properties = map (id: {
      inherit id;
      value = properties.${id};
    }) (builtins.attrNames properties);
  };
in {
  name = "disk-smart";
  title = "Disk SMART Health";
  tags = ["storage" "smart"];
  timeFrom = "now-24h";
  panels = map panel [
    {
      id = 1;
      title = "SMART Exporter Availability";
      type = "stat";
      queries = [(query "A" ''up{job="smartctl"}'' "{{instance}}")];
      fieldDefaults.mappings = healthMappings "Available" "Unavailable";
    }
    {
      id = 2;
      title = "Disk Health and Information";
      type = "table";
      queries = map (value: value // {query = value.query // {format = "table";};}) [
        (query "A" ''max by (device, model_name, serial_number) (${metric "smartctl_device"})'' "")
        (query "B" ''max by (device) (${metric "smartctl_device_smart_status"})'' "")
        (query "C" ''max by (device) (smartctl_device_temperature{${selector},temperature_type="current"})'' "")
        (query "D" ''max by (device) (${metric "smartctl_device_power_on_seconds"})'' "")
        (query "E" ''max by (device) (${metric "smartctl_device_power_cycle_count"})'' "")
        (query "F" ''max by (device) (${metric "smartctl_device_capacity_bytes"})'' "")
        (query "G" ''max by (device) (${metric "smartctl_device_smartctl_exit_status"})'' "")
      ];
      transformations = [
        {
          kind = "Transformation";
          group = "joinByField";
          spec = {
            options = {
              byField = "device";
              mode = "outerTabular";
            };
          };
        }
        {
          kind = "Transformation";
          group = "filterFieldsByName";
          spec = {
            options.include.pattern = "^(device|model_name|serial_number|Value #[B-G])$";
          };
        }
        {
          kind = "Transformation";
          group = "organize";
          spec = {
            options = {
              indexByName = {
                device = 0;
                model_name = 1;
                serial_number = 2;
                "Value #B" = 3;
                "Value #C" = 4;
                "Value #D" = 5;
                "Value #E" = 6;
                "Value #F" = 7;
                "Value #G" = 8;
              };
              renameByName = {
                device = "Device";
                model_name = "Model";
                serial_number = "Serial";
                "Value #B" = "Health";
                "Value #C" = "Temperature";
                "Value #D" = "Power-on time";
                "Value #E" = "Power cycles";
                "Value #F" = "Capacity";
                "Value #G" = "smartctl status";
              };
            };
          };
        }
      ];
      options = {
        showHeader = true;
        cellHeight = "sm";
        sortBy = [
          {
            displayName = "Device";
            desc = false;
          }
        ];
      };
      fieldDefaults = {
        noValue = "Unknown";
        custom = {
          align = "auto";
          cellOptions.type = "auto";
          filterable = true;
          width = 110;
        };
      };
      overrides = [
        (override "Device" {"custom.width" = 260;})
        (override "Model" {"custom.width" = 200;})
        (override "Serial" {"custom.width" = 180;})
        (override "Health" {
          mappings = healthMappings "Passed" "Failed";
          "custom.cellOptions".type = "color-text";
          "custom.width" = 85;
        })
        (override "Temperature" {
          unit = "celsius";
          decimals = 0;
        })
        (override "Power-on time" {unit = "s";})
        (override "Power cycles" {decimals = 0;})
        (override "Capacity" {unit = "bytes";})
        (override "smartctl status" (errorThresholds // {"custom.cellOptions".type = "color-text";}))
      ];
    }
    {
      id = 4;
      title = "Disk Temperature";
      unit = "celsius";
      queries = [(query "A" ''smartctl_device_temperature{${selector},temperature_type="current"}'' "{{device}}")];
    }
    {
      id = 8;
      title = "ATA Reallocated, Pending and Uncorrectable Sectors (Raw)";
      queries = [(query "A" ''smartctl_device_attribute{${selector},attribute_id=~"5|197|198",attribute_value_type="raw"}'' "{{device}} {{attribute_name}}")];
      fieldDefaults.decimals = 0;
    }
    {
      id = 9;
      title = "SAS / SCSI Grown Defects";
      queries = [(query "A" (metric "smartctl_scsi_grown_defect_list") "{{device}}")];
      fieldDefaults.decimals = 0;
    }
    {
      id = 10;
      title = "SAS / SCSI Uncorrected Errors";
      queries = [
        (query "A" (metric "smartctl_read_total_uncorrected_errors") "{{device}} read")
        (query "B" (metric "smartctl_write_total_uncorrected_errors") "{{device}} write")
      ];
      fieldDefaults.decimals = 0;
    }
    {
      id = 11;
      title = "NVMe Endurance Used";
      unit = "percent";
      queries = [(query "A" (metric "smartctl_device_percentage_used") "{{device}}")];
    }
    {
      id = 12;
      title = "NVMe Available Spare and Warning Threshold";
      unit = "percent";
      queries = [
        (query "A" (metric "smartctl_device_available_spare") "{{device}} available")
        (query "B" (metric "smartctl_device_available_spare_threshold") "{{device}} threshold")
      ];
      fieldDefaults.max = 100;
    }
    {
      id = 13;
      title = "NVMe Media and Data Integrity Errors";
      queries = [(query "A" (metric "smartctl_device_media_errors") "{{device}}")];
      fieldDefaults.decimals = 0;
    }
    {
      id = 14;
      title = "NVMe Critical Warning by Disk (Bitmask)";
      type = "stat";
      queries = [(query "A" (metric "smartctl_device_critical_warning") "{{device}}")];
      fieldDefaults = errorThresholds;
    }
    {
      id = 15;
      title = "NVMe Error Information Log Entries";
      queries = [(query "A" (metric "smartctl_device_num_err_log_entries") "{{device}}")];
      fieldDefaults.decimals = 0;
    }
  ];
  rows = [
    {
      title = "Current health";
      maxColumnCount = 1;
      panels = [1];
      rowHeight = 100;
    }
    {
      title = "Disk information";
      maxColumnCount = 1;
      panels = [2];
      rowHeight = 400;
    }
    {
      title = "ATA and SAS / SCSI";
      columnWidth = 450;
      maxColumnCount = 2;
      panels = [4 8 9 10];
      rowHeightMode = "standard";
    }
    {
      title = "NVMe";
      columnWidth = 450;
      maxColumnCount = 2;
      panels = [11 12 13 14 15];
      rowHeightMode = "standard";
    }
  ];
}
