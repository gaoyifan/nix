{
  name = "incus-vm-performance";
  panels = [
    {
      id = 1;
      queries = [
        {
          query = {
            expr = ''count(incus_boot_time_seconds{job="incus",type="virtual-machine",name=~"$vm"})'';
            instant = true;
            legendFormat = "Running";
            range = false;
          };
          refId = "A";
        }
      ];
      title = "Running VMs";
      visualization = {
        fieldDefaults = {
          color = {mode = "thresholds";};
          decimals = 0;
          thresholds = {
            mode = "absolute";
            steps = [
              {
                color = "green";
                value = null;
              }
            ];
          };
        };
        options = {
          colorMode = "value";
          graphMode = "none";
        };
        type = "stat";
      };
    }
    {
      id = 2;
      queries = [
        {
          query = {
            expr = ''100 * (1 - sum(rate(incus_cpu_seconds_total{job="incus",type="virtual-machine",name=~"$vm",mode="idle"}[$__rate_interval])) / sum(rate(incus_cpu_seconds_total{job="incus",type="virtual-machine",name=~"$vm"}[$__rate_interval])))'';
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
            expr = ''100 * (1 - sum(incus_memory_MemAvailable_bytes{job="incus",type="virtual-machine",name=~"$vm"}) / sum(incus_memory_MemTotal_bytes{job="incus",type="virtual-machine",name=~"$vm"}))'';
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
            expr = ''100 * (1 - sum(incus_filesystem_avail_bytes{job="incus",type="virtual-machine",name=~"$vm",mountpoint=~"/|C:"}) / sum(incus_filesystem_size_bytes{job="incus",type="virtual-machine",name=~"$vm",mountpoint=~"/|C:"}))'';
            instant = true;
            legendFormat = "Root filesystem";
            range = false;
          };
          refId = "A";
        }
      ];
      title = "Root Filesystem Usage";
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
                value = 80;
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
            expr = ''100 * (1 - sum by (name) (rate(incus_cpu_seconds_total{job="incus",type="virtual-machine",name=~"$vm",mode="idle"}[$__rate_interval])) / sum by (name) (rate(incus_cpu_seconds_total{job="incus",type="virtual-machine",name=~"$vm"}[$__rate_interval])))'';
            instant = false;
            legendFormat = "{{name}}";
            range = true;
          };
          refId = "A";
        }
      ];
      title = "CPU Usage by VM";
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
    {
      id = 6;
      queries = [
        {
          query = {
            expr = ''100 * (1 - incus_memory_MemAvailable_bytes{job="incus",type="virtual-machine",name=~"$vm"} / incus_memory_MemTotal_bytes{job="incus",type="virtual-machine",name=~"$vm"})'';
            instant = false;
            legendFormat = "{{name}}";
            range = true;
          };
          refId = "A";
        }
      ];
      title = "Memory Usage by VM";
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
    {
      id = 7;
      queries = [
        {
          query = {
            expr = ''rate(incus_disk_read_bytes_total{job="incus",type="virtual-machine",name=~"$vm"}[$__rate_interval])'';
            instant = false;
            legendFormat = "{{name}} {{device}} read";
            range = true;
          };
          refId = "A";
        }
        {
          query = {
            expr = ''rate(incus_disk_written_bytes_total{job="incus",type="virtual-machine",name=~"$vm"}[$__rate_interval])'';
            instant = false;
            legendFormat = "{{name}} {{device}} write";
            range = true;
          };
          refId = "B";
        }
      ];
      title = "Disk Throughput by VM";
      visualization = {
        fieldDefaults = {
          color = {mode = "palette-classic";};
          min = 0;
          unit = "Bps";
        };
        fillOpacity = 10;
        legendCalcs = ["lastNotNull" "max"];
        type = "timeseries";
      };
    }
    {
      id = 8;
      queries = [
        {
          query = {
            expr = ''rate(incus_network_receive_bytes_total{job="incus",type="virtual-machine",name=~"$vm"}[$__rate_interval])'';
            instant = false;
            legendFormat = "{{name}} {{device}} receive";
            range = true;
          };
          refId = "A";
        }
        {
          query = {
            expr = ''rate(incus_network_transmit_bytes_total{job="incus",type="virtual-machine",name=~"$vm"}[$__rate_interval])'';
            instant = false;
            legendFormat = "{{name}} {{device}} transmit";
            range = true;
          };
          refId = "B";
        }
      ];
      title = "Network Throughput by VM";
      visualization = {
        fieldDefaults = {
          color = {mode = "palette-classic";};
          min = 0;
          unit = "Bps";
        };
        fillOpacity = 10;
        legendCalcs = ["lastNotNull" "max"];
        type = "timeseries";
      };
    }
  ];
  rows = [
    {
      columnWidth = 180;
      maxColumnCount = 4;
      panels = [1 2 3 4];
      rowHeight = 128;
      title = "Summary";
    }
    {
      columnWidth = 350;
      maxColumnCount = 2;
      panels = [5 6 7 8];
      rowHeightMode = "standard";
      title = "Virtual machine performance";
    }
  ];
  tags = ["incus" "virtual-machines"];
  timeFrom = "now-6h";
  title = "Incus VM Performance";
}
