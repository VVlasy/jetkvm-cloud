#!/bin/sh
# Runs from the nginx image's /docker-entrypoint.d before nginx starts.
# Replaces the build-time placeholder API URL with CLOUD_API_URL.
set -eu

placeholder="https://__JETKVM_CLOUD_API__"
root="/usr/share/nginx/html"

if ! grep -rqF "$placeholder" "$root"; then
  # Real URL was baked in at build time; nothing to do.
  exit 0
fi

if [ -z "${CLOUD_API_URL:-}" ]; then
  echo "cloud-ui: build contains the API URL placeholder but CLOUD_API_URL is not set" >&2
  exit 1
fi

case "$CLOUD_API_URL" in
  https://*|http://*) ;;
  *) echo "cloud-ui: CLOUD_API_URL must start with http:// or https:// (got '$CLOUD_API_URL')" >&2; exit 1 ;;
esac

# Strip a trailing slash; the UI concatenates paths onto it.
url="${CLOUD_API_URL%/}"
# Escape sed replacement metacharacters (&, \, and the # delimiter)
escaped=$(printf '%s' "$url" | sed 's/[&\\#]/\\&/g')

grep -rlF "$placeholder" "$root" | while IFS= read -r f; do
  sed -i "s#$placeholder#$escaped#g" "$f"
done

echo "cloud-ui: API URL set to $url"
