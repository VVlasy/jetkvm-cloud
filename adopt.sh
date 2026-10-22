#!/usr/bin/env bash
# Marks the hand-rolled jetkvm resources as owned by a Helm release, so that
# `helm upgrade --install` takes them over instead of failing with
# "rendered manifests contain a resource that already exists".
#
# Usage: ./adopt.sh [release-name] [namespace]
set -euo pipefail

RELEASE="${1:-jetkvm}"
NS="${2:-jetkvm}"

# kind/name pairs the chart renders with values-vvlasy.yaml
RESOURCES=(
  deployment/cloud-api
  service/cloud-api
  ingress/cloud-api
  deployment/cloud-ui
  service/cloud-ui
  ingress/cloud-ui
  statefulset/postgres
  service/postgres
)

for r in "${RESOURCES[@]}"; do
  if ! kubectl -n "$NS" get "$r" >/dev/null 2>&1; then
    echo "skip  $r (not found)"
    continue
  fi
  kubectl -n "$NS" label --overwrite "$r" app.kubernetes.io/managed-by=Helm >/dev/null
  kubectl -n "$NS" annotate --overwrite "$r" \
    meta.helm.sh/release-name="$RELEASE" \
    meta.helm.sh/release-namespace="$NS" >/dev/null
  echo "adopt $r"
done

echo
echo "Note: configmap/cloud-ui-nginx is intentionally not adopted. The chart does not"
echo "mount it; delete it after the upgrade (or before setting ui.nginxConfig)."
echo
echo "Now run:"
echo "  helm upgrade --install $RELEASE charts/jetkvm-cloud -n $NS -f values-vvlasy.yaml"
