# Top file for a plain Salt master or Aria Automation Config: VMs with the grain role=wordpress get the state.
# SUSE Multi-Linux Manager does not use this file; there the "wordpress" configuration channel is assigned
# through an activation key (see suma/README.md).
base:
  'role:wordpress':
    - match: grain
    - wordpress
