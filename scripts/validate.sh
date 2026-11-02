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
  cores=$(yq '.spec.template.spec.domain.cpu.cores' "$f")
  cpu_limit=$(yq '.spec.template.spec.domain.resources.limits.cpu' "$f")
  guest=$(yq '.spec.template.spec.domain.memory.guest' "$f")
  mem_limit=$(yq '.spec.template.spec.domain.resources.limits.memory' "$f")

  [ "$(basename "$f" .yaml)" = "$name" ] || fail "$f" "file name must match metadata.name ($name)"
  yq -e ".allowedNamespaces | contains([\"$ns\"])" "$POLICY" >/dev/null || fail "$f" "namespace $ns is not allowed"

  for label in $(yq '.requiredLabels[]' "$POLICY"); do
    yq -e ".metadata.labels.\"$label\"" "$f" >/dev/null 2>&1 || fail "$f" "missing required label $label"
  done

  # CPU/memory must be within policy, and the guest size must match the limits (catches half-edited files)
  (( cores >= cpu_min && cores <= cpu_max )) || fail "$f" "cpu.cores=$cores outside ${cpu_min}-${cpu_max}"
  [ "$cpu_limit" = "$cores" ] || fail "$f" "limits.cpu ($cpu_limit) must equal cpu.cores ($cores)"
  gi=$(to_gi "$guest")
  awk "BEGIN{exit !($gi >= $mem_min && $gi <= $mem_max)}" || fail "$f" "memory $guest outside ${mem_min}-${mem_max}Gi"
  [ "$mem_limit" = "$guest" ] || fail "$f" "limits.memory ($mem_limit) must equal memory.guest ($guest)"

  if [ "$errors" -eq "$before" ]; then echo "ok  $name  cpu=$cores mem=$guest"; fi
done

[ "$errors" -eq 0 ] || { echo "$errors policy violation(s)"; exit 1; }
