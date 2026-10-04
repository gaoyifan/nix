{
  name = "home-router-public-egress";
  panels = [
    {
      id = 1;
      queries = [
        {
          query = {
            expr = ''ping_up{wan=~"$wan"}'';
            instant = true;
            legendFormat = "{{wan}}";
            range = false;
          };
          refId = "A";
        }
      ];
      title = "Probe Service";
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
        };
        type = "stat";
      };
    }
    {
      id = 2;
      queries = [
        {
          query = {
            expr = ''node_network_carrier{wan=~"$wan"}'';
            instant = true;
            legendFormat = "{{wan}} ({{device}})";
            range = false;
          };
          refId = "A";
        }
      ];
      title = "Physical WAN Link";
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
        };
        type = "stat";
      };
    }
    {
      id = 3;
      queries = [
        {
          query = {
            expr = ''(max by (wan) (ping_loss_ratio{wan=~"$wan", target=~"$target"}) > bool 0) + (min by (wan) (ping_loss_ratio{wan=~"$wan", target=~"$target"}) > bool 0)'';
            instant = true;
            legendFormat = "{{wan}}";
            range = false;
          };
          refId = "A";
        }
      ];
      title = "Current Packet Loss";
      visualization = {
        fieldDefaults = {
          color = {mode = "thresholds";};
          mappings = [
            {
              options = {
                "0" = {
                  color = "green";
                  index = 0;
                  text = "Healthy";
                };
                "1" = {
                  color = "yellow";
                  index = 1;
                  text = "Degraded";
                };
                "2" = {
                  color = "red";
                  index = 2;
                  text = "Loss";
                };
              };
              type = "value";
            }
          ];
          thresholds = {
            mode = "absolute";
            steps = [
              {
                color = "green";
                value = null;
              }
              {
                color = "yellow";
                value = 1;
              }
              {
                color = "red";
                value = 2;
              }
            ];
          };
        };
        options = {
          colorMode = "background";
          graphMode = "none";
        };
        type = "stat";
      };
    }
    {
      id = 4;
      queries = [
        {
          query = {
            expr = ''rate(home_router_wan_receive_bytes_total{wan=~"$wan"}[$__rate_interval]) * 8'';
            legendFormat = "{{wan}} RX";
            range = true;
          };
          refId = "A";
        }
        {
          query = {
            expr = ''rate(home_router_wan_transmit_bytes_total{wan=~"$wan"}[$__rate_interval]) * 8'';
            legendFormat = "{{wan}} TX";
            range = true;
          };
          refId = "B";
        }
      ];
      title = "Physical WAN Throughput";
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
      id = 5;
      description = "Peak packet loss in each displayed time cell, by WAN and probe target.";
      # Keep the number of status cells within the panel's rendering limit.
      queryOptions.maxDataPoints = 120;
      queries = [
        {
          query = {
            # A cell starts at its sample time, so include probes up to the next cell boundary.
            expr = ''max_over_time(ping_loss_ratio{wan=~"$wan", target=~"$target"}[$__interval] offset -$__interval) * 100'';
            legendFormat = "{{wan}} IPv{{ip_version}} {{target}}";
            range = true;
          };
          refId = "A";
        }
      ];
      title = "Packet Loss by Target";
      visualization = {
        fieldDefaults = {
          color = {mode = "thresholds";};
          min = 0;
          max = 100;
          thresholds = {
            mode = "absolute";
            steps = [
              {
                color = "#1f4734";
                value = null;
              }
              {
                color = "#eab839";
                value = 0.01;
              }
              {
                color = "#ff9830";
                value = 20;
              }
              {
                color = "#e24d42";
                value = 50;
              }
            ];
          };
          unit = "percent";
        };
        options = {
          colWidth = 1;
          legend.showLegend = false;
          rowHeight = 0.8;
          showValue = "never";
          tooltip.mode = "single";
        };
        type = "status-history";
      };
    }
    {
      id = 6;
      queries = [
        {
          query = {
            expr = ''ping_rtt_mean_seconds{wan=~"$wan", target=~"$target"}'';
            legendFormat = "{{wan}} IPv{{ip_version}} {{target}}";
            range = true;
          };
          refId = "A";
        }
      ];
      title = "Mean RTT";
      visualization = {
        fieldDefaults = {
          color = {mode = "palette-classic";};
          min = 0;
          unit = "s";
        };
        fillOpacity = 0;
        legendCalcs = ["lastNotNull" "mean" "max"];
        type = "timeseries";
      };
    }
    {
      id = 7;
      queries = [
        {
          query = {
            expr = ''ping_rtt_best_seconds{wan=~"$wan", target=~"$target"}'';
            legendFormat = "{{wan}} IPv{{ip_version}} {{target}} best";
            range = true;
          };
          refId = "A";
        }
        {
          query = {
            expr = ''ping_rtt_worst_seconds{wan=~"$wan", target=~"$target"}'';
            legendFormat = "{{wan}} IPv{{ip_version}} {{target}} worst";
            range = true;
          };
          refId = "B";
        }
      ];
      title = "Best and Worst RTT";
      visualization = {
        fieldDefaults = {
          color = {mode = "palette-classic";};
          min = 0;
          unit = "s";
        };
        fillOpacity = 0;
        legendCalcs = ["lastNotNull" "min" "max"];
        type = "timeseries";
      };
    }
    {
      id = 8;
      queries = [
        {
          query = {
            expr = ''ping_rtt_std_deviation_seconds{wan=~"$wan", target=~"$target"}'';
            legendFormat = "{{wan}} IPv{{ip_version}} {{target}}";
            range = true;
          };
          refId = "A";
        }
      ];
      title = "RTT Standard Deviation";
      visualization = {
        fieldDefaults = {
          color = {mode = "palette-classic";};
          min = 0;
          unit = "s";
        };
        fillOpacity = 0;
        legendCalcs = ["lastNotNull" "mean" "max"];
        type = "timeseries";
      };
    }
    {
      id = 9;
      queries = [
        {
          query = {
            expr = ''rate(node_network_receive_errs_total{wan=~"$wan"}[$__rate_interval])'';
            legendFormat = "{{wan}} RX errors";
            range = true;
          };
          refId = "A";
        }
        {
          query = {
            expr = ''rate(node_network_transmit_errs_total{wan=~"$wan"}[$__rate_interval])'';
            legendFormat = "{{wan}} TX errors";
            range = true;
          };
          refId = "B";
        }
        {
          query = {
            expr = ''rate(node_network_receive_drop_total{wan=~"$wan"}[$__rate_interval])'';
            legendFormat = "{{wan}} RX drops";
            range = true;
          };
          refId = "C";
        }
        {
          query = {
            expr = ''rate(node_network_transmit_drop_total{wan=~"$wan"}[$__rate_interval])'';
            legendFormat = "{{wan}} TX drops";
            range = true;
          };
          refId = "D";
        }
      ];
      title = "Physical WAN Errors and Drops";
      visualization = {
        fieldDefaults = {
          color = {mode = "palette-classic";};
          min = 0;
          unit = "pps";
        };
        fillOpacity = 0;
        legendCalcs = ["lastNotNull" "max"];
        type = "timeseries";
      };
    }
  ];
  rows = [
    {
      columnWidth = 200;
      maxColumnCount = 3;
      panels = [1 2 3];
      rowHeight = 280;
      title = "Status";
    }
    {
      columnWidth = 350;
      maxColumnCount = 2;
      panels = [4 5 6 7 8 9];
      rowHeightMode = "standard";
      title = "Trends";
    }
  ];
  tags = ["home-router" "public-egress"];
  timeFrom = "now-24h";
  title = "Home Router Public Egress";
}
