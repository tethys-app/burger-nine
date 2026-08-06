#!/usr/bin/env bash
set -euo pipefail

API_URL="${PUBLIC_NEO_API_URL:-http://127.0.0.1:3211}"
BRAND_SLUG="${PUBLIC_BRAND_SLUG:-burger-nine}"
OUTPUT="$(cd "$(dirname "$0")/.." && pwd)/BurgerNine/StoreData/${BRAND_SLUG}.snapshot.json"

command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

brand="$(curl --fail --silent --show-error "${API_URL%/}/v1/brands/${BRAND_SLUG}")"
locations='[]'

while IFS= read -r slug; do
  store="$(curl --fail --silent --show-error "${API_URL%/}/v1/brands/${BRAND_SLUG}/stores/${slug}")"
  catalog="$(curl --fail --silent --show-error "${API_URL%/}/v1/brands/${BRAND_SLUG}/stores/${slug}/catalog")"
  locations="$(jq -c -n --argjson locations "$locations" --argjson store "$store" --argjson catalog "$catalog" '$locations + [{store: $store, catalog: $catalog}]')"
done < <(jq -r '.stores[].slug' <<<"$brand")

mkdir -p "$(dirname "$OUTPUT")"
jq -S -n --argjson brand "$brand" --argjson locations "$locations" '{brand: $brand, locations: $locations}' > "$OUTPUT"
echo "Wrote $OUTPUT"
