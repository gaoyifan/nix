#!/usr/bin/env bash
set -euo pipefail

roots_file=${1:?usage: push-r2-cache-misses.sh ROOTS_FILE}

: "${R2_BUCKET:?R2_BUCKET is required}"
: "${S3_ENDPOINT:?S3_ENDPOINT is required}"
if [ "${DRY_RUN:-0}" != 1 ]; then
  : "${BINARY_CACHE_SECRET_KEY:?BINARY_CACHE_SECRET_KEY is required}"
fi

work_dir=$(mktemp -d)
cache_dir=$(mktemp -d)
trap 'rm -rf "$work_dir" "$cache_dir"' EXIT

closure_paths=$work_dir/closure-paths
public_paths=$work_dir/public-paths
r2_paths=$work_dir/r2-paths
cache_results=$work_dir/cache-results
keep_urls=$work_dir/keep-urls
secret_key=$work_dir/secret.key

mkdir -p "$cache_results"
roots=()
while IFS= read -r root; do
  roots+=("$root")
done < "$roots_file"

nix path-info --recursive "${roots[@]}" | sort -u > "$closure_paths"

check_public_cache() {
  local store_path=$1
  local store_name=${store_path#/nix/store/}
  local store_hash=${store_name%%-*}
  local status

  status=$(
    curl \
      --location \
      --silent \
      --retry 3 \
      --retry-delay 1 \
      --connect-timeout 10 \
      --max-time 30 \
      --output /dev/null \
      --write-out '%{http_code}' \
      "https://cache.nixos.org/${store_hash}.narinfo"
  ) || status=000

  case "$status" in
    200) printf '%s\n' "$store_path" > "$cache_results/${store_hash}.hit" ;;
    404) printf '%s\n' "$store_path" > "$cache_results/${store_hash}.miss" ;;
    *)
      printf 'Unexpected HTTP %s for cache.nixos.org/%s.narinfo\n' "$status" "$store_hash" >&2
      return 1
      ;;
  esac
}
export cache_results
export -f check_public_cache

xargs -n 1 -P 4 bash -c "check_public_cache \"\$1\"" _ < "$closure_paths"

find "$cache_results" -type f -name '*.hit' -exec cat {} + | sort > "$public_paths"
find "$cache_results" -type f -name '*.miss' -exec cat {} + | sort > "$r2_paths"

total_count=$(wc -l < "$closure_paths" | tr -d ' ')
public_count=$(wc -l < "$public_paths" | tr -d ' ')
r2_count=$(wc -l < "$r2_paths" | tr -d ' ')

echo "Closure paths: $total_count"
echo "Already on cache.nixos.org: $public_count"
echo "Will upload to R2: $r2_count"

if [ ! -s "$r2_paths" ]; then
  echo "No R2-only paths to publish."
  exit 0
fi

if [ "${DRY_RUN:-0}" = 1 ]; then
  echo "Dry run: skipping signing."
else
  echo "$BINARY_CACHE_SECRET_KEY" > "$secret_key"
  nix store sign --key-file "$secret_key" --stdin < "$r2_paths"
fi

nix --quiet copy --to "file://$cache_dir?compression=zstd" --stdin < "$r2_paths"

while IFS= read -r store_path; do
  store_name=${store_path#/nix/store/}
  store_hash=${store_name%%-*}
  narinfo=$cache_dir/${store_hash}.narinfo

  [ -f "$narinfo" ] && awk '$1 == "URL:" { print $2; exit }' "$narinfo"
done < "$r2_paths" | sort -u > "$keep_urls"

while IFS= read -r store_path; do
  store_name=${store_path#/nix/store/}
  store_hash=${store_name%%-*}
  narinfo=$cache_dir/${store_hash}.narinfo

  if [ -f "$narinfo" ]; then
    url=$(awk '$1 == "URL:" { print $2; exit }' "$narinfo")
    rm -f "$narinfo"

    if [ -n "$url" ] && ! grep -Fxq "$url" "$keep_urls"; then
      rm -f "$cache_dir/$url"
    fi
  fi
done < "$public_paths"

endpoint_url=$S3_ENDPOINT
case "$endpoint_url" in
  http://*|https://*) ;;
  *) endpoint_url=https://$endpoint_url ;;
esac

if command -v aws >/dev/null 2>&1; then
  aws_cmd=(aws)
else
  aws_cmd=(nix run --accept-flake-config nixpkgs#awscli2 --)
fi

if [ "${DRY_RUN:-0}" = 1 ]; then
  cache_bytes=$(du -sb "$cache_dir" | cut -f1)
  cache_files=$(find "$cache_dir" -type f | wc -l | tr -d ' ')
  cache_narinfos=$(find "$cache_dir" -name '*.narinfo' | wc -l | tr -d ' ')

  echo "Dry run: would upload $cache_bytes bytes in $cache_files files."
  echo "Dry run: retained $cache_narinfos narinfo files."
  exit 0
fi

"${aws_cmd[@]}" s3 sync "$cache_dir/" "s3://$R2_BUCKET/" \
  --endpoint-url "$endpoint_url" \
  --only-show-errors
