#!/bin/sh
# Installs the wordpress formula on a SUSE Multi-Linux Manager 5.x server (container host reachable over SSH):
# state files -> /srv/salt/wordpress, form -> /srv/formula_metadata/wordpress (both persistent volumes).
# Usage: suma/install-formula.sh root@<server-host>
set -eu
host=$1; here=$(cd "$(dirname "$0")/.." && pwd)
tar -C "$here" -cf - salt/wordpress formulas/wordpress | ssh "$host" 'set -e; t=$(mktemp -d); tar -C "$t" -xf -
  mgrctl exec -- mkdir -p /srv/salt/wordpress /srv/formula_metadata/wordpress
  for f in "$t"/salt/wordpress/*; do mgrctl cp "$f" server:/srv/salt/wordpress/; done
  for f in "$t"/formulas/wordpress/*; do mgrctl cp "$f" server:/srv/formula_metadata/wordpress/; done
  rm -rf "$t"; mgrctl exec -- ls /srv/salt/wordpress /srv/formula_metadata/wordpress'
