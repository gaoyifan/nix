{
  name = "home-router-overview";
  panels = [
    {
      id = 1;
      queries = [
        {
          query = {
            expr = ''time() - node_boot_time_seconds'';
            instant = true;
            legendFormat = "Uptime";
            range = false;
          };
          refId = "A";
        }
      ];
      title = "Uptime";
      visualization = {
        fieldDefaults = {
          color = {mode = "thresholds";};
          thresholds = {
            mode = "absolute";
            steps = [
              {
                color = "green";
                value = null;
              }
            ];
          };
          unit = "s";
        };
        options = {
          colorMode = "value";
          graphMode = "area";
        };
        type = "stat";
      };
    }
    {
      id = 2;
      queries = [
        {
          query = {
            expr = ''100 - avg(rate(node_cpu_seconds_total{mode="idle"}[$__rate_interval])) * 100'';
            instant = true;
            legendFormat = "CPU";
            range = false;
          };
          refId = "A";
        }
      ];
      title = "CPU Usage";
      visualization = {
        fieldDefaults = {
          color = {mode = "thresholds";};
          max = 100;
          min = 0;
          thresholds = {
            mode = "absolute";
            steps = [
              {
                color = "green";
                value = null;
              }
              {
                color = "yellow";
                value = 70;
              }
              {
                color = "red";
                value = 90;
              }
            ];
          };
          unit = "percent";
        };
        options = {
          colorMode = "value";
          graphMode = "area";
        };
        type = "stat";
      };
    }
    {
      id = 3;
      queries = [
        {
          query = {
            expr = ''(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100'';
            instant = true;
            legendFormat = "Memory";
            range = false;
          };
          refId = "A";
        }
      ];
      title = "Memory Usage";
      visualization = {
        fieldDefaults = {
          color = {mode = "thresholds";};
          max = 100;
          min = 0;
          thresholds = {
            mode = "absolute";
            steps = [
              {
                color = "green";
                value = null;
              }
              {
                color = "yellow";
                value = 75;
              }
              {
                color = "red";
                value = 90;
              }
            ];
          };
          unit = "percent";
        };
        options = {
          colorMode = "value";
          graphMode = "area";
        };
        type = "stat";
      };
    }
    {
      id = 4;
      queries = [
        {
          query = {
            expr = ''(1 - node_filesystem_avail_bytes{mountpoint="/",fstype!~"tmpfs|overlay"} / node_filesystem_size_bytes{mountpoint="/",fstype!~"tmpfs|overlay"}) * 100'';
            instant = true;
            legendFormat = "Root FS";
            range = false;
          };
          refId = "A";
        }
      ];
      title = "Root Filesystem";
      visualization = {
        fieldDefaults = {
          color = {mode = "thresholds";};
          max = 100;
          min = 0;
          thresholds = {
            mode = "absolute";
            steps = [
              {
                color = "green";
                value = null;
              }
              {
                color = "yellow";
                value = 75;
              }
              {
                color = "red";
                value = 90;
              }
            ];
          };
          unit = "percent";
        };
        options = {
          colorMode = "value";
          graphMode = "area";
        };
        type = "stat";
      };
    }
    {
      id = 5;
      queries = [
        {
          query = {
            expr = ''node_nf_conntrack_entries / node_nf_conntrack_entries_limit * 100'';
            instant = true;
            legendFormat = "Conntrack";
            range = false;
          };
          refId = "A";
        }
      ];
      title = "Conntrack Usage";
      visualization = {
        fieldDefaults = {
          color = {mode = "thresholds";};
          max = 100;
          min = 0;
          thresholds = {
            mode = "absolute";
            steps = [
              {
                color = "green";
                value = null;
              }
              {
                color = "yellow";
                value = 70;
              }
              {
                color = "red";
                value = 90;
              }
            ];
          };
          unit = "percent";
        };
        options = {
          colorMode = "value";
          graphMode = "area";
        };
        type = "stat";
      };
    }
    {
      id = 6;
      queries = [
        {
          query = {
            expr = ''node_load1'';
            instant = true;
            legendFormat = "Load 1m";
            range = false;
          };
          refId = "A";
        }
      ];
      title = "Load Average";
      visualization = {
        fieldDefaults = {
          color = {mode = "thresholds";};
          thresholds = {
            mode = "absolute";
            steps = [
              {
                color = "green";
                value = null;
              }
            ];
          };
          unit = "short";
        };
        options = {
          colorMode = "value";
          graphMode = "area";
        };
        type = "stat";
      };
    }
    {
      id = 7;
      queries = [
        {
          query = {
            expr = ''node_network_carrier{job="node", device=~"$interface"}'';
            instant = true;
            legendFormat = "{{device}}";
            range = false;
          };
          refId = "A";
        }
      ];
      title = "Interface State";
      visualization = {
        fieldDefaults = {
          color = {mode = "thresholds";};
          mappings = [
            {
              options = {
                "0" = {
                  color = "red";
                  index = 1;
                  text = "Down";
                };
                "1" = {
                  color = "green";
                  index = 0;
                  text = "Up";
                };
              };
              type = "value";
            }
          ];
          thresholds = {
            mode = "absolute";
            steps = [
              {
                color = "red";
                value = null;
              }
              {
                color = "green";
                value = 1;
              }
            ];
          };
        };
        options = {
          colorMode = "background";
          graphMode = "none";
          orientation = "horizontal";
        };
        type = "stat";
      };
    }
    {
      id = 8;
      queries = [
        {
          query = {
            expr = ''node_network_speed_bytes{job="node", device=~"$interface"} * 8'';
            instant = true;
            legendFormat = "{{device}}";
            range = false;
          };
          refId = "A";
        }
      ];
      title = "Link Speed";
      visualization = {
        fieldDefaults = {
          color = {mode = "palette-classic";};
          unit = "bps";
        };
        options = {
          colorMode = "value";
          graphMode = "none";
          orientation = "horizontal";
        };
        type = "stat";
      };
    }
    {
      id = 9;
      queries = [
        {
          query = {
            expr = ''increase(node_network_carrier_changes_total{job="node", device=~"$interface"}[$__range])'';
            instant = true;
            legendFormat = "{{device}}";
            range = false;
          };
          refId = "A";
        }
      ];
      title = "Carrier Changes in Range";
      visualization = {
        fieldDefaults = {
          color = {mode = "thresholds";};
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
          unit = "short";
        };
        options = {
          colorMode = "value";
          graphMode = "none";
          orientation = "horizontal";
        };
        type = "stat";
      };
    }
    {
      id = 10;
      queries = [
        {
          query = {
            expr = ''rate(node_network_receive_bytes_total{job="node", device=~"$interface"}[$__rate_interval]) * 8'';
            legendFormat = "{{device}} RX";
            range = true;
          };
          refId = "A";
        }
        {
          query = {
            expr = ''rate(node_network_transmit_bytes_total{job="node", device=~"$interface"}[$__rate_interval]) * 8'';
            legendFormat = "{{device}} TX";
            range = true;
          };
          refId = "B";
        }
      ];
      title = "Interface Throughput";
      visualization = {
        fieldDefaults = {
          color = {mode = "palette-classic";};
          unit = "bps";
        };
        fillOpacity = 10;
        legendCalcs = ["lastNotNull" "max"];
        type = "timeseries";
      };
    }
    {
      id = 11;
      queries = [
        {
          query = {
            expr = ''rate(node_network_receive_packets_total{job="node", device=~"$interface"}[$__rate_interval])'';
            legendFormat = "{{device}} RX";
            range = true;
          };
          refId = "A";
        }
        {
          query = {
            expr = ''rate(node_network_transmit_packets_total{job="node", device=~"$interface"}[$__rate_interval])'';
            legendFormat = "{{device}} TX";
            range = true;
          };
          refId = "B";
        }
      ];
      title = "Packet Rate";
      visualization = {
        fieldDefaults = {
          color = {mode = "palette-classic";};
          unit = "pps";
        };
        fillOpacity = 10;
        legendCalcs = ["lastNotNull" "max"];
        type = "timeseries";
      };
    }
    {
      id = 12;
      queries = [
        {
          query = {
            expr = ''rate(node_network_receive_errs_total{job="node", device=~"$interface"}[$__rate_interval])'';
            legendFormat = "{{device}} RX errors";
            range = true;
          };
          refId = "A";
        }
        {
          query = {
            expr = ''rate(node_network_transmit_errs_total{job="node", device=~"$interface"}[$__rate_interval])'';
            legendFormat = "{{device}} TX errors";
            range = true;
          };
          refId = "B";
        }
        {
          query = {
            expr = ''rate(node_network_receive_drop_total{job="node", device=~"$interface"}[$__rate_interval])'';
            legendFormat = "{{device}} RX drops";
            range = true;
          };
          refId = "C";
        }
        {
          query = {
            expr = ''rate(node_network_transmit_drop_total{job="node", device=~"$interface"}[$__rate_interval])'';
            legendFormat = "{{device}} TX drops";
            range = true;
          };
          refId = "D";
        }
      ];
      title = "Interface Errors and Drops";
      visualization = {
        fieldDefaults = {
          color = {mode = "palette-classic";};
          min = 0;
          unit = "pps";
        };
        fillOpacity = 10;
        legendCalcs = ["lastNotNull" "max"];
        type = "timeseries";
      };
    }
    {
      id = 13;
      queries = [
        {
          query = {
            expr = ''100 - avg(rate(node_cpu_seconds_total{mode="idle"}[$__rate_interval])) * 100'';
            instant = false;
            legendFormat = "CPU";
            range = true;
          };
          refId = "A";
        }
      ];
      title = "CPU Usage History";
      visualization = {
        fieldDefaults = {
          color = {mode = "palette-classic";};
          max = 100;
          min = 0;
          unit = "percent";
        };
        fillOpacity = 10;
        legendCalcs = ["lastNotNull" "mean" "max"];
        type = "timeseries";
      };
    }
    {
      id = 14;
      queries = [
        {
          query = {
            expr = ''(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100'';
            instant = false;
            legendFormat = "Memory";
            range = true;
          };
          refId = "A";
        }
      ];
      title = "Memory Usage History";
      visualization = {
        fieldDefaults = {
          color = {mode = "palette-classic";};
          max = 100;
          min = 0;
          unit = "percent";
        };
        fillOpacity = 10;
        legendCalcs = ["lastNotNull" "mean" "max"];
        type = "timeseries";
      };
    }
    {
      id = 15;
      queries = [
        {
          query = {
            expr = ''max(node_hwmon_temp_celsius{job="node", sensor!="temp0"} * on(instance, job, chip) group_left(chip_name) node_hwmon_chip_names{job="node", chip_name=~"cpu_thermal_0|k10temp|coretemp"})'';
            instant = true;
            legendFormat = "CPU/SoC";
            range = false;
          };
          refId = "A";
        }
      ];
      title = "CPU/SoC Temperature";
      visualization = {
        fieldDefaults = {
          color = {mode = "palette-classic";};
          unit = "celsius";
        };
        options = {
          colorMode = "value";
          graphMode = "area";
        };
        type = "stat";
      };
    }
    {
      id = 16;
      queries = [
        {
          query = {
            expr = ''min((((node_hwmon_temp_crit_celsius{job="node"} > 0) < 200) - on(instance, job, chip, sensor) node_hwmon_temp_celsius{job="node", sensor!="temp0"}) unless on(instance, job, chip, sensor) node_hwmon_sensor_label{job="node", label=~"Core .*"})'';
            instant = true;
            legendFormat = "Headroom";
            range = false;
          };
          refId = "A";
        }
      ];
      title = "Critical Temperature Headroom";
      visualization = {
        fieldDefaults = {
          color = {mode = "thresholds";};
          thresholds = {
            mode = "absolute";
            steps = [
              {
                color = "red";
                value = null;
              }
              {
                color = "yellow";
                value = 10;
              }
              {
                color = "green";
                value = 20;
              }
            ];
          };
          unit = "celsius";
        };
        options = {
          colorMode = "value";
          graphMode = "area";
        };
        type = "stat";
      };
    }
    {
      id = 17;
      queries = [
        {
          query = {
            expr = ''(node_hwmon_temp_celsius{job="node", sensor!="temp0"} * on(instance, job, chip) group_left(chip_name) node_hwmon_chip_names{job="node"}) * on(instance, job, chip, sensor) group_left(label) node_hwmon_sensor_label{job="node", label!~"Core .*"}'';
            instant = false;
            legendFormat = "{{chip_name}} {{chip}} {{label}}";
            range = true;
          };
          refId = "A";
        }
        {
          query = {
            expr = ''(node_hwmon_temp_celsius{job="node", sensor!="temp0"} * on(instance, job, chip) group_left(chip_name) node_hwmon_chip_names{job="node"}) unless on(instance, job, chip, sensor) node_hwmon_sensor_label{job="node"}'';
            instant = false;
            legendFormat = "{{chip_name}} {{chip}} {{sensor}}";
            range = true;
          };
          refId = "B";
        }
        {
          query = {
            expr = ''smartctl_device_temperature{job="smartctl", temperature_type="current"} * on(instance, job, device) group_left(model_name) smartctl_device{interface!="nvme"}'';
            instant = false;
            legendFormat = "{{model_name}} {{device}}";
            range = true;
          };
          refId = "C";
        }
      ];
      title = "Hardware Temperatures";
      visualization = {
        fieldDefaults = {
          color = {mode = "palette-classic";};
          unit = "celsius";
        };
        fillOpacity = 10;
        legendCalcs = ["lastNotNull" "mean" "max"];
        type = "timeseries";
      };
    }
    {
      id = 18;
      queries = [
        {
          query = {
            expr = ''max by (type) (node_cooling_device_cur_state{job="node"} > bool 0) * 100'';
            instant = false;
            legendFormat = "{{type}} cooling";
            range = true;
          };
          refId = "A";
        }
        {
          query = {
            expr = ''(increase(node_cpu_package_throttles_total{job="node"}[$__rate_interval]) > bool 0) * 100'';
            instant = false;
            legendFormat = "Package {{package}} throttled";
            range = true;
          };
          refId = "B";
        }
      ];
      title = "Thermal Mitigation";
      visualization = {
        fieldDefaults = {
          color = {mode = "palette-classic";};
          max = 100;
          min = 0;
          unit = "percent";
        };
        fillOpacity = 10;
        legendCalcs = ["lastNotNull" "max"];
        type = "timeseries";
      };
    }
  ];
  rows = [
    {
      columnWidth = 100;
      maxColumnCount = 8;
      panels = [1 2 3 4 5 6 15 16];
      rowHeight = 128;
      title = "Summary";
    }
    {
      columnWidth = 200;
      maxColumnCount = 3;
      panels = [7 8 9];
      rowHeight = 240;
      title = "Interface health";
    }
    {
      columnWidth = 350;
      maxColumnCount = 2;
      panels = [13 14];
      rowHeightMode = "standard";
      title = "Resource history";
    }
    {
      columnWidth = 350;
      maxColumnCount = 2;
      panels = [17 18];
      rowHeightMode = "standard";
      title = "Thermal health";
    }
    {
      columnWidth = 350;
      maxColumnCount = 2;
      panels = [10 11];
      rowHeightMode = "standard";
      title = "Interface traffic";
    }
    {
      maxColumnCount = 1;
      panels = [12];
      rowHeightMode = "standard";
      title = "Interface errors and drops";
    }
  ];
  tags = ["home-router"];
  timeFrom = "now-24h";
  title = "Home Router Overview";
}
