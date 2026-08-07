#!/usr/bin/env -S uv run --script
#
# /// script
# requires-python = ">=3.12"
# dependencies = ["tree-sitter", "tree-sitter-nix", "rich", "humanize"]
# ///
"""Calculate marginal closure cost of Home Manager packages.

Measures how much each package ACTUALLY adds to the closure, accounting for
dependencies shared with a baseline set. Parses package lists from a Nix file
using tree-sitter.

Adapted from basnijholt/dotfiles (configs/nixos/scripts/nix/package-marginal-cost.py):
- resolves packages against this flake's pinned nixpkgs via --inputs-from,
  falling back to this flake's own packages (pkgs/) for custom derivations
- understands patterns used here: (lib.lowPrio nh), pkgs.foo, lib.optionals

Packages not present in the local store show as N/A (this script never builds).

Usage:
    ./scripts/package-marginal-cost.py                # analyze home-manager/default.nix
    ./scripts/package-marginal-cost.py some/file.nix
    ./scripts/package-marginal-cost.py --list         # only show parsed package names
"""

import argparse
import json
import subprocess
from pathlib import Path

import humanize
import tree_sitter_nix as tsnix
from rich.console import Console
from rich.progress import BarColumn, Progress, SpinnerColumn, TextColumn
from rich.table import Table
from tree_sitter import Language, Parser

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_NIX_FILE = REPO_ROOT / "home-manager" / "default.nix"

# Approximation of what is always present anyway; marginal cost is measured
# against the union of these closures.
BASELINE_PKGS = [
    "coreutils",
    "bash",
    "glibc",
    "ncurses",
    "openssl",
    "zlib",
    "curl",
    "git",
    "python3",
]

# Identifiers that appear in package lists but are not packages.
SKIP_IDENTIFIERS = {
    "with",
    "pkgs",
    "lib",
    "let",
    "in",
    "ps",
    "rec",
    "inputs",
    "config",
    "isDarwin",
    "stdenv",
}

console = Console()


def parse_packages_from_nix(nix_file: Path) -> list[str]:
    """Parse package names from a Nix file using tree-sitter."""
    parser = Parser(Language(tsnix.language()))
    source = nix_file.read_bytes()
    tree = parser.parse(source)

    def text(node):
        return source[node.start_byte : node.end_byte].decode()

    def select_parts(node):
        """Return dotted-path parts of a select_expression, or None."""
        if node.type != "select_expression":
            return None
        parts = text(node).split(".")
        return [p.strip() for p in parts]

    def from_apply(node):
        """Extract a package name from an apply expression inside a list.

        Handles:
          python3.withPackages (...)  -> python3
          lib.lowPrio nh              -> nh
        """
        fn, *args = [c for c in node.children if c.type != "comment"]
        parts = select_parts(fn)
        if parts and parts[0] == "lib" and args:
            arg = args[0]
            if arg.type == "variable_expression":
                return text(arg)
            return None
        if parts and parts[0] not in SKIP_IDENTIFIERS:
            return parts[0]
        return None

    def collect(node, in_list=False):
        if node.type == "list_expression":
            for child in node.children:
                yield from collect(child, in_list=True)
        elif in_list:
            if node.type == "variable_expression":
                yield text(node)
            elif node.type == "select_expression":
                parts = select_parts(node)
                # pkgs.lazyssh -> lazyssh; skip inputs.*, config.*, etc.
                if parts and parts[0] == "pkgs" and len(parts) == 2:
                    yield parts[1]
            elif node.type == "parenthesized_expression":
                for child in node.children:
                    yield from collect(child, in_list=True)
            elif node.type == "apply_expression":
                if pkg := from_apply(node):
                    yield pkg
            else:
                # binary_expression (++), etc: keep looking for nested lists
                for child in node.children:
                    yield from collect(child)
        else:
            for child in node.children:
                yield from collect(child)

    seen = []
    for pkg in collect(tree.root_node):
        if pkg not in SKIP_IDENTIFIERS and pkg not in seen:
            seen.append(pkg)
    return seen


def candidate_installables(pkg: str) -> list[list[str]]:
    """Nix installable argv fragments to try for a package, in order."""
    return [
        # Pinned nixpkgs from this repo's flake.lock, not the registry.
        ["--inputs-from", str(REPO_ROOT), f"nixpkgs#{pkg}"],
        # Custom packages exported by this flake (pkgs/).
        [f"{REPO_ROOT}#{pkg}"],
    ]


def get_closure_paths(pkg: str) -> set[str]:
    """Get all store paths in a package's closure (empty if unavailable)."""
    for installable in candidate_installables(pkg):
        try:
            result = subprocess.run(
                ["nix", "path-info", "-r", "--json", *installable],
                capture_output=True,
                text=True,
                timeout=120,
            )
        except Exception:
            continue
        if result.returncode == 0:
            data = json.loads(result.stdout)
            return set(data.keys())
    return set()


def get_paths_size(paths: set[str]) -> int:
    """Get total NAR size of a set of store paths."""
    if not paths:
        return 0
    try:
        result = subprocess.run(
            ["nix", "path-info", "-s", "--json", *sorted(paths)],
            capture_output=True,
            text=True,
            timeout=120,
        )
        if result.returncode != 0:
            return 0
        data = json.loads(result.stdout)
        return sum(info.get("narSize", 0) for info in data.values())
    except Exception:
        return 0


def format_size(size_bytes: int) -> str:
    if size_bytes < 0:
        return "N/A"
    return humanize.naturalsize(size_bytes, binary=True)


def main():
    parser = argparse.ArgumentParser(description="Calculate marginal closure cost of packages")
    parser.add_argument(
        "nix_file",
        nargs="?",
        type=Path,
        default=DEFAULT_NIX_FILE,
        help=f"Nix file to parse (default: {DEFAULT_NIX_FILE})",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="Only print the parsed package names and exit",
    )
    args = parser.parse_args()
    nix_file = args.nix_file.resolve()

    console.print("\n[bold blue]Package Marginal Cost Analyzer[/bold blue]")
    console.print(f"[dim]Parsing packages from {nix_file}...[/dim]")
    packages = parse_packages_from_nix(nix_file)
    console.print(f"[green]Found {len(packages)} packages[/green]: {', '.join(packages)}\n")

    if args.list:
        return

    base_paths = set()
    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        BarColumn(),
        TextColumn("[progress.percentage]{task.percentage:>3.0f}%"),
        console=console,
    ) as progress:
        task = progress.add_task("[cyan]Building baseline...", total=len(BASELINE_PKGS))
        for pkg in BASELINE_PKGS:
            base_paths.update(get_closure_paths(pkg))
            progress.advance(task)

    console.print(f"[dim]Baseline ({', '.join(BASELINE_PKGS)}) has {len(base_paths)} store paths[/dim]\n")

    results = []
    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        BarColumn(),
        TextColumn("[progress.percentage]{task.percentage:>3.0f}%"),
        console=console,
    ) as progress:
        task = progress.add_task("[cyan]Analyzing packages...", total=len(packages))
        for pkg in packages:
            progress.update(task, description=f"[cyan]Analyzing {pkg}...")
            pkg_paths = get_closure_paths(pkg)
            if not pkg_paths:
                results.append((pkg, -1, -1))
                progress.advance(task)
                continue
            closure_size = get_paths_size(pkg_paths)
            marginal_size = get_paths_size(pkg_paths - base_paths)
            results.append((pkg, closure_size, marginal_size))
            progress.advance(task)

    results.sort(key=lambda x: x[2], reverse=True)

    table = Table(title="Package Analysis Results", show_header=True)
    table.add_column("Package", style="cyan", min_width=20)
    table.add_column("Closure", justify="right", width=12)
    table.add_column("Marginal", justify="right", width=12)

    large, medium = [], []
    for pkg, closure, marginal in results:
        if marginal < 0:
            style = "dim"
        elif marginal > 50 * 1024 * 1024:
            style = "red bold"
            large.append((pkg, marginal))
        elif marginal > 10 * 1024 * 1024:
            style = "yellow"
            medium.append((pkg, marginal))
        else:
            style = "green"
        table.add_row(pkg, format_size(closure), f"[{style}]{format_size(marginal)}[/{style}]")

    console.print(table)

    unavailable = [pkg for pkg, closure, _ in results if closure < 0]
    if unavailable:
        console.print(f"\n[dim]N/A (not in local store, skipped): {', '.join(unavailable)}[/dim]")

    if large:
        console.print("\n[bold red]Large marginal cost (>50MB):[/bold red]")
        for pkg, size in large:
            console.print(f"   {pkg:<25} [red]+{format_size(size):>12}[/red]")
    if medium:
        console.print("\n[bold yellow]Medium marginal cost (10-50MB):[/bold yellow]")
        for pkg, size in medium:
            console.print(f"   {pkg:<25} [yellow]+{format_size(size):>12}[/yellow]")

    console.print(
        "\n[dim]Marginal cost = size actually added on top of the baseline closure."
        " Large offenders are candidates for the 'nix run' alias pattern.[/dim]\n"
    )


if __name__ == "__main__":
    main()
