#!/usr/bin/env bash
# Checks every VirtualMachine under vms/ against policy/limits.yaml.
# Exits non-zero (failing the PR check) if any rule is violated.
set -euo pipefail

POLICY=policy/limits.yaml
errors=0

to_gi() {  # 4Gi -> 4, 512Mi -> 0.5
  case "$1" in
    *Gi) echo "${1%Gi}" ;;
    *Mi) awk "BEGIN{print ${1%Mi}/1024}" ;;
    *)   echo "unsupported unit: $1" >&2; echo -1 ;;
  esac
}

fail() { echo "::error file=$1::$2"; errors=$((errors + 1)); }

cpu_min=$(yq '.cpu.min' "$POLICY");      cpu_max=$(yq '.cpu.max' "$POLICY")
mem_min=$(yq '.memoryGi.min' "$POLICY"); mem_max=$(yq '.memoryGi.max' "$POLICY")

for f in vms/*.yaml; do
  [ "$(yq '.kind' "$f")" = "VirtualMachine" ] || continue
  before=$errors
  name=$(yq '.metadata.name' "$f")
  ns=$(yq '.metadata.namespace' "$f")
  sockets=$(yq '.spec.template.spec.domain.cpu.sockets' "$f")
  cores=$(yq '.spec.template.spec.domain.cpu.cores' "$f")
  guest=$(yq '.spec.template.spec.domain.memory.guest' "$f")
  hotplug=$(yq '.metadata.annotations."harvesterhci.io/enableCPUAndMemoryHotplug"' "$f")

  [ "$(basename "$f" .yaml)" = "$name" ] || fail "$f" "file name must match metadata.name ($name)"
  yq -e ".allowedNamespaces | contains([\"$ns\"])" "$POLICY" >/dev/null || fail "$f" "namespace $ns is not allowed"

  for label in $(yq '.requiredLabels[]' "$POLICY"); do
    yq -e ".metadata.labels.\"$label\"" "$f" >/dev/null 2>&1 || fail "$f" "missing required label $label"
  done

  # Hot-plug shape: vCPUs are sockets (1 core each), memory is memory.guest, no explicit limits
  [ "$hotplug" = "true" ] || fail "$f" "annotation harvesterhci.io/enableCPUAndMemoryHotplug must be \"true\""
  [ "$cores" = "1" ] || fail "$f" "cpu.cores must be 1 (vCPUs are hot-plugged as sockets)"
  yq -e '.spec.template.spec.domain.resources.limits' "$f" >/dev/null 2>&1 && fail "$f" "remove resources.limits (blocks live memory hot-plug)"

  # CPU/memory must be within policy
  (( sockets >= cpu_min && sockets <= cpu_max )) || fail "$f" "vCPUs (cpu.sockets)=$sockets outside ${cpu_min}-${cpu_max}"
  gi=$(to_gi "$guest")
  awk "BEGIN{exit !($gi >= $mem_min && $gi <= $mem_max)}" || fail "$f" "memory $guest outside ${mem_min}-${mem_max}Gi"

  if [ "$errors" -eq "$before" ]; then echo "ok  $name  cpu=$sockets mem=$guest"; fi
done

[ "$errors" -eq 0 ] || { echo "$errors policy violation(s)"; exit 1; }
