# Baseline applied to every demo VM via a SUSE Multi-Linux Manager configuration channel.
# Equivalent of a vRO "post-provisioning" workflow, but declarative and re-applied on every highstate.
baseline_packages:
  pkg.installed:
    - pkgs:
      - qemu-guest-agent   # lets Harvester show the guest IP and do clean shutdowns
      - chrony

qemu-guest-agent:
  service.running:
    - enable: True
    - require:
      - pkg: baseline_packages

chronyd:
  service.running:
    - enable: True
    - require:
      - pkg: baseline_packages

/etc/motd:
  file.managed:
    - contents: |
        Managed by SUSE Multi-Linux Manager (Salt). Local changes will be reverted.
