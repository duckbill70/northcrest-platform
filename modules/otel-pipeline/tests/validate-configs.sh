#!/usr/bin/env bash
# Validates every collector config with `otelcol-contrib validate`, which
# builds the full pipeline graph and checks each component's settings
# without starting anything or needing credentials.
#
# otelcol-contrib is used because it is published as a plain binary; the
# Google-Built Collector is a subset of contrib at the same version. Keep
# OTELCOL_VERSION close to the version in var.collector_image.
set -euo pipefail

version="${OTELCOL_VERSION:-0.165.0}"
here="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

base="https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${version}"
tarball="otelcol-contrib_${version}_linux_amd64.tar.gz"
curl -sSfL -o "$work/$tarball" "$base/$tarball"
# Each release asset has a .sha256 file holding just the hex digest.
expected="$(curl -sSfL "$base/$tarball.sha256" | awk '{print $1}')"
(cd "$work" && echo "$expected  $tarball" | sha256sum -c -)
tar -xzf "$work/$tarball" -C "$work" otelcol-contrib

# Placeholder values for the environment each config expects.
export OTEL_PROJECT_ID=ncair-ci-observability
export OTEL_PIPELINE_PROJECT=ncair-ci-observability
export OTEL_BASELINE_SAMPLING_PERCENT=20
export OTEL_GATEWAY_ENDPOINT=127.0.0.1:14317
export OTEL_HOST_ROOT=/ # /hostfs on the VM; must exist when validating
export OTEL_CORS_ORIGINS='["https://ncair-ci-customer.web.app"]'
export NORTHCREST_BUSINESS_UNIT=customer-channels
export NORTHCREST_TIER=commercial

status=0
for config in "$here"/config/*.yaml; do
  echo "::group::$(basename "$config")"
  if "$work/otelcol-contrib" validate --config="file:$config"; then
    echo "valid"
  else
    status=1
  fi
  echo "::endgroup::"
done
exit $status
