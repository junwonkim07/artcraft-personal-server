#!/usr/bin/env bash
# No cloud credentials or mutations: exercise selection and renderer boundaries.
set -Eeuo pipefail
cd "$(dirname "$0")/.."
revision=$(git rev-parse HEAD)
for provider in vultr hetzner-cloud hetzner-auction ubuntu; do
  result=$(scripts/deploy.sh --provider "$provider" --plan)
  [[ "$result" == *"Target: $provider"* && "$result" == *'Plan only.'* ]]
done
for provider in vercel neon unknown; do
  rc=0
  scripts/deploy.sh --provider "$provider" --apply >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ]
done
rc=0
scripts/cloud-init.sh hetzner-cloud 'main; echo unsafe' >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ]
rc=0
scripts/cloud-init.sh hetzner-auction "$revision" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ]
for provider in vultr hetzner-cloud; do
  result=$(scripts/cloud-init.sh "$provider" "$revision")
  [[ "$result" == '#cloud-config'* && "$result" == *"--provider $provider --apply"* ]]
done
echo 'Deployment selection and cloud-init input checks passed.'
