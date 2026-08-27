let
  datasource = {name = "home-router-prometheus";};
  autoRefreshIntervals = [
    "5s"
    "10s"
    "30s"
    "1m"
    "5m"
    "15m"
    "30m"
    "1h"
    "2h"
    "1d"
  ];
  annotation = {
    kind = "AnnotationQuery";
    spec = {
      query = {
        kind = "DataQuery";
        group = "grafana";
        version = "v0";
        datasource.name = "-- Grafana --";
        spec = {};
      };
      enable = true;
      hide = true;
      iconColor = "rgba(0, 211, 255, 1)";
      name = "Annotations & Alerts";
      builtIn = true;
      legacyOptions.type = "dashboard";
    };
  };
  elementName = id: "panel-${toString id}";
  panelQuery = value: {
    kind = "PanelQuery";
    spec = {
      query = {
        kind = "DataQuery";
        group = "prometheus";
        version = "v0";
        inherit datasource;
        spec = {editorMode = "code";} // value.query;
      };
      inherit (value) refId;
      hidden = false;
    };
  };
  timeseriesOptions = visualization: {
    legend = {
      calcs = visualization.legendCalcs;
      displayMode = "table";
      placement = "bottom";
      showLegend = true;
    };
    tooltip = {
      mode = "multi";
      sort = "desc";
    };
  };
  statOptions = {
    justifyMode = "auto";
    orientation = "auto";
    reduceOptions = {
      calcs = ["lastNotNull"];
      fields = "";
      values = false;
    };
    textMode = "auto";
    wideLayout = true;
  };
  visualization = value: let
    typeConfig = builtins.getAttr value.type {
      stat = {
        options = statOptions // value.options;
        fieldDefaults = {};
      };
      timeseries = {
        options = timeseriesOptions value;
        fieldDefaults.custom = {
          drawStyle = "line";
          fillOpacity = value.fillOpacity;
          lineInterpolation = "linear";
          lineWidth = 1;
          showPoints = "never";
          spanNulls = true;
        };
      };
    };
  in {
    kind = "VizConfig";
    group = value.type;
    version = "";
    spec = {
      inherit (typeConfig) options;
      fieldConfig = {
        defaults = value.fieldDefaults // typeConfig.fieldDefaults;
        overrides = [];
      };
    };
  };
  panel = value: {
    name = elementName value.id;
    value = {
      kind = "Panel";
      spec = {
        inherit (value) id title;
        description = "";
        links = [];
        data = {
          kind = "QueryGroup";
          spec = {
            queries = map panelQuery value.queries;
            transformations = [];
            queryOptions = {};
          };
        };
        vizConfig = visualization value.visualization;
      };
    };
  };
  layoutItem = panels: id: let
    value = builtins.head (builtins.filter (candidate: candidate.id == id) panels);
  in {
    kind = "AutoGridLayoutItem";
    spec =
      {
        element = {
          kind = "ElementReference";
          name = elementName value.id;
        };
      }
      // (
        if value ? conditionalRendering
        then {inherit (value) conditionalRendering;}
        else {}
      );
  };
  row = panels: value: {
    kind = "RowsLayoutRow";
    spec = {
      inherit (value) title;
      collapse = false;
      hideHeader = true;
      layout = {
        kind = "AutoGridLayout";
        spec =
          {
            columnWidthMode =
              if value ? columnWidth
              then "custom"
              else "standard";
            rowHeightMode =
              if value ? rowHeight
              then "custom"
              else value.rowHeightMode;
            items = map (layoutItem panels) value.panels;
            inherit (value) maxColumnCount;
          }
          // (
            if value ? columnWidth
            then {inherit (value) columnWidth;}
            else {}
          )
          // (
            if value ? rowHeight
            then {inherit (value) rowHeight;}
            else {}
          );
      };
    };
  };
in {
  customVariable = spec: {
    kind = "CustomVariable";
    spec =
      {
        options = [];
        multi = true;
        includeAll = true;
        hide = "dontHide";
        skipUrlSync = false;
        allowCustomValue = true;
      }
      // spec;
  };

  queryVariable = {
    name,
    label,
    query,
  }: {
    kind = "QueryVariable";
    spec = {
      inherit name label;
      current = {
        text = "All";
        value = "$__all";
      };
      hide = "dontHide";
      refresh = "onDashboardLoad";
      skipUrlSync = false;
      query = {
        kind = "DataQuery";
        group = "prometheus";
        version = "v0";
        inherit datasource;
        spec = {
          inherit query;
          refId = "StandardVariableQuery";
        };
      };
      regex = "";
      sort = "alphabeticalAsc";
      definition = query;
      options = [];
      multi = true;
      includeAll = true;
      allowCustomValue = true;
    };
  };

  build = {
    source,
    variables,
  }: {
    apiVersion = "dashboard.grafana.app/v2";
    kind = "Dashboard";
    metadata.name = source.name;
    spec = {
      annotations = [annotation];
      cursorSync = "Crosshair";
      editable = false;
      elements = builtins.listToAttrs (map panel source.panels);
      layout = {
        kind = "RowsLayout";
        spec.rows = map (row source.panels) source.rows;
      };
      links = [];
      liveNow = false;
      preload = false;
      inherit (source) tags title;
      timeSettings = {
        timezone = "browser";
        from = source.timeFrom;
        to = "now";
        autoRefresh = "30s";
        inherit autoRefreshIntervals;
        hideTimepicker = false;
        fiscalYearStartMonth = 0;
      };
      inherit variables;
    };
  };
}
