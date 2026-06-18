#!/usr/bin/env bash
# Verify a published image tag is anonymously pullable from a registry.
#
# Usage: verify_published_image.sh <registry> <repository> <tag>
#   e.g. verify_published_image.sh ghcr.io gmeligio/flutter-android 3.44.1
#
# Resolves the image manifest using ONLY anonymous registry auth (the standard
# WWW-Authenticate -> token -> retry handshake every OCI/Docker registry
# implements). It never logs in, so a success means an unauthenticated
# `docker pull` of the tag would succeed. It resolves the manifest (HEAD on the
# manifests endpoint) and does not download layer blobs — the manifest is the
# part a private package refuses anonymously (see issue #492).
#
# Exit 0 iff the tag is anonymously resolvable; non-zero otherwise.
set -euo pipefail

registry="${1:?registry required (docker.io|ghcr.io|quay.io)}"
repository="${2:?repository required (e.g. owner/image)}"
tag="${3:?tag required}"

# Map the public registry name to its Distribution API host.
case "$registry" in
  docker.io | registry-1.docker.io) host="registry-1.docker.io" ;;
  ghcr.io) host="ghcr.io" ;;
  quay.io) host="quay.io" ;;
  *) host="$registry" ;;
esac

accept="application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.docker.distribution.manifest.v2+json,application/vnd.oci.image.manifest.v1+json"
manifest_url="https://${host}/v2/${repository}/manifests/${tag}"

ref="${registry}/${repository}:${tag}"

# Issue a manifest HEAD and capture both the status line and headers.
headers="$(curl -sS -I -H "Accept: ${accept}" "$manifest_url" || true)"
status="$(printf '%s\n' "$headers" | awk 'toupper($1) ~ /^HTTP/ {code=$2} END {print code}')"

if [[ "$status" == "200" ]]; then
  echo "${ref} → HTTP 200 (resolvable)"
  exit 0
fi

if [[ "$status" == "401" ]]; then
  # Parse the bearer challenge: Bearer realm="...",service="...",scope="..."
  challenge="$(printf '%s\n' "$headers" | grep -i '^www-authenticate:' | head -n1)"
  realm="$(printf '%s' "$challenge" | sed -n 's/.*realm="\([^"]*\)".*/\1/p')"
  service="$(printf '%s' "$challenge" | sed -n 's/.*service="\([^"]*\)".*/\1/p')"
  scope="$(printf '%s' "$challenge" | sed -n 's/.*scope="\([^"]*\)".*/\1/p')"
  # Some registries omit scope on the manifest challenge; default to pull.
  [[ -z "$scope" ]] && scope="repository:${repository}:pull"

  if [[ -n "$realm" ]]; then
    token_json="$(curl -sS "${realm}?service=${service}&scope=${scope}" || true)"
    token="$(printf '%s' "$token_json" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
    [[ -z "$token" ]] && token="$(printf '%s' "$token_json" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')"

    if [[ -n "$token" ]]; then
      retry_status="$(curl -sS -I -o /dev/null -w '%{http_code}' \
        -H "Accept: ${accept}" -H "Authorization: Bearer ${token}" \
        "$manifest_url" || true)"
      if [[ "$retry_status" == "200" ]]; then
        echo "${ref} → HTTP 200 (resolvable)"
        exit 0
      fi
      echo "${ref} → HTTP ${retry_status} (NOT resolvable: anonymous token denied manifest access)" >&2
      exit 1
    fi
  fi
fi

echo "${ref} → HTTP ${status:-000} (NOT resolvable: not anonymously pullable)" >&2
exit 1
