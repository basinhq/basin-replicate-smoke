#!/usr/bin/env bash
set -euo pipefail

version=v1.5.4
arch=${1:?usage: stage_duckdb_cli.sh <amd64|arm64> <bin-dir> <extension-dir>}
bin_dir=${2:?missing bin directory}
extension_dir=${3:?missing extension directory}

case "$arch" in
  amd64)
    platform=linux_amd64
    cli_sha=1f2fa724fb054b3dbe1a9cbd13de5b76997d850e7087ec762ba88db04e0180cf
    extension_gz_sha=648101794f4adb49e72939ef37cc4a0237414eafde1f6db1ee7b180384d396bf
    extension_sha=00f72402c9c5d1f69c3329f38837f4abd100cddb7c69e76650f46bf35a17babe
    ;;
  arm64)
    platform=linux_arm64
    cli_sha=377f03fb9f17ab5a78f28f829cbfcb5333da8ab3c2d0788f27694f81df77ed29
    extension_gz_sha=0b1eab5666b142c2abad87d9d261fb45952a403cc34b7cd2f69c1806ca4f0a52
    extension_sha=f73ec9ab68a6de5c3c190cd1ecbba553a5791bf5821a991d70ea65abc5e45562
    ;;
  *)
    echo "unsupported Docker architecture: $arch" >&2
    exit 2
    ;;
esac

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cli_zip="$work/duckdb.zip"
curl -fsSL \
  "https://github.com/duckdb/duckdb/releases/download/$version/duckdb_cli-linux-$arch.zip" \
  -o "$cli_zip"
echo "$cli_sha  $cli_zip" | sha256sum -c -
unzip -q "$cli_zip" -d "$work/cli"
install -m 0755 "$work/cli/duckdb" "$bin_dir/duckdb"

destination="$extension_dir/$version/$platform/ducklake.duckdb_extension"
mkdir -p "$(dirname "$destination")"
compressed="$work/ducklake.duckdb_extension.gz"
curl -fsSL \
  "https://extensions.duckdb.org/$version/$platform/ducklake.duckdb_extension.gz" \
  -o "$compressed"
echo "$extension_gz_sha  $compressed" | sha256sum -c -
gunzip -c "$compressed" > "$destination"
echo "$extension_sha  $destination" | sha256sum -c -
