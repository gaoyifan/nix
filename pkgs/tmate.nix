{pkgs}:
pkgs.tmate.overrideAttrs (old: {
  meta =
    old.meta
    // {
      # Accept release inactivity and the withdrawn CVE only; retain future reports.
      knownVulnerabilities =
        pkgs.lib.subtractLists [
          "There are no upstream releases since 2019-11."
          "CVE-2018-19387"
        ]
        old.meta.knownVulnerabilities;
    };
})
