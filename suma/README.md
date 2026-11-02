# SUSE Multi-Linux Manager: what happens inside the VM

Harvester + Fleet own the **shape** of the VM (CPU, memory, disks, network).
SUSE Multi-Linux Manager (formerly SUSE Manager) owns **what runs inside it**: repos, patches and configuration via Salt.

## Flow

1. Fleet creates the VM; cloud-init (`vms/suma-bootstrap.secret.yaml`) runs the bootstrap script.
2. The guest registers as a Salt minion using the **activation key** embedded in that script.
3. The activation key assigns:
   - **Software channels** = the repos the VM can use. Use Content Lifecycle Management to promote frozen repo snapshots dev → test → prod.
   - **Configuration channel** `vm-baseline` = the Salt state in `states/vm-baseline/init.sls`.
4. Apply highstate: on demand, on a schedule, or from the pipeline through the API (for example `system.scheduleApplyHighstate`).

## One-time setup (UI or `spacecmd`)

- Create the activation key (SLES 16 base channel + child channels, config channel `vm-baseline`).
- Generate the bootstrap script for that key and publish it as `bootstrap-harvester.sh` under `/pub/bootstrap/`.
- Create the config channel `vm-baseline` (state channel) and paste in `init.sls`.
- Put the real SUSE Multi-Linux Manager hostname in `vms/suma-bootstrap.secret.yaml`.

## Where vRO logic usually lands

- "Install agent / configure NTP / harden" post-provisioning workflows → Salt states in a config channel.
- "Patch these servers in a maintenance window" → SUSE Multi-Linux Manager action chains and recurring actions.
- "Which repo version does prod run?" → Content Lifecycle Management environments.
