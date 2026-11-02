#!/usr/bin/env bash
# Prints a markdown before/after table of VM sizing changes between two git refs.
# Usage: scripts/change-summary.sh <base-ref> [head-ref]
set -euo pipefail

base=$1
head=${2:-HEAD}
# vCPUs = cores x sockets x threads (works for both the old cores-based and the hot-plug sockets-based shape)
q='[(.spec.template.spec.domain.cpu | (.cores // 1) * (.sockets // 1) * (.threads // 1)), .spec.template.spec.domain.memory.guest] | join(" / ")'

echo "### VM change plan"
echo
echo "| VM | Before (vCPU / memory) | After (vCPU / memory) |"
echo "|----|------------------------|-----------------------|"
for f in $(git diff --name-only "$base" "$head" -- 'vms/*.yaml'); do
  before=$(git show "$base:$f" 2>/dev/null | yq "select(.kind == \"VirtualMachine\") | $q" 2>/dev/null || true)
  after=$(git show "$head:$f" 2>/dev/null | yq "select(.kind == \"VirtualMachine\") | $q" 2>/dev/null || true)
  [ -n "$before$after" ] || continue
  echo "| $(basename "$f" .yaml) | ${before:-_new_} | ${after:-_deleted_} |"
done
echo
echo "After merge, Fleet applies the change to Harvester. CPU and memory *increases* are hot-plugged into the running VM (no reboot, up to 4x the boot size). Decreases, or growth past that, restart the VM automatically (auto-restart label)."
