# VMware Aria Orchestrator (vRO) vs SUSE automation stack

SUSE stack in this demo = **Harvester** (VMs on KubeVirt) + **Rancher Fleet** (GitOps) + **Git platform workflows** (GitHub Actions here; GitLab etc. work too) + **SUSE Multi-Linux Manager** (Salt, repos, patching).

| Capability | Aria Orchestrator (vRO) | SUSE stack |
|---|---|---|
| Automation model | Imperative workflows: steps run in order against vCenter and other systems | Declarative: Git holds the desired state, Fleet (VMs) and Salt (guest OS) converge to it |
| Authoring | Visual workflow designer; scripts in JavaScript, plus PowerShell/Python/Node.js actions | YAML (VM specs, Fleet, Actions) and Salt states (YAML + Jinja), scripts in any language. No drag-and-drop designer |
| Source of truth | Workflows and config elements stored in vRO, packages exported for versioning | Git repo: every VM definition and change is a versioned file |
| Self-service request | vRA / Service Broker catalog items calling vRO workflows | Git platform form (`workflow_dispatch`) or Rancher UI; any portal can call the API to open a PR |
| Approvals | vRA approval policies, or user-interaction steps inside a workflow | Pull request review: CODEOWNERS routes to the right team, branch rules enforce it |
| Guardrails / policy | Logic inside the workflow, vRA policies | PR checks (schema + policy script); optionally Kubernetes admission policies (Kubewarden) |
| VM provisioning | vCenter plugin (clone template, customization spec) | Harvester VM manifest (image + cloud-init), applied by Fleet |
| Day-2 VM changes (CPU, memory, disk) | Workflow calls vCenter reconfigure | Edit the YAML in a PR, merge, Fleet applies. Restart needed unless hot-plug is enabled |
| Guest OS configuration | Guest script operations, or calls out to Ansible/Puppet | SUSE Multi-Linux Manager Salt states, re-applied on every highstate (drift corrected) |
| Repos and patching | Out of scope (external tools) | SUSE Multi-Linux Manager: channels, Content Lifecycle Management, scheduled patching, CVE audit |
| Drift detection | None by default | Fleet flags modified resources; Salt highstate reports and fixes config drift |
| Rollback | Write a compensating workflow | Revert the commit (VM shape); Salt state history / CLM environments (guest content) |
| Audit trail | Workflow run logs in vRO | Git history + PR approvals + Actions logs + Kubernetes/Rancher audit log |
| Integrations | Large plugin ecosystem (vCenter, NSX, AD, REST, SQL...) | Kubernetes API for everything on Harvester; Salt modules; REST from Actions or Salt for the rest |
| Multi-site scale | One vRO per environment/cluster | Fleet targets many Harvester clusters from one Rancher; SUSE Multi-Linux Manager proxies for remote sites |
| Skills | vRO JavaScript and object model | Git, YAML, Kubernetes, Salt (all general-purpose, widely known) |

## Mapping vRO concepts

- **Workflow** → GitHub Actions workflow (orchestration) or Salt orchestrate runner (multi-system ordering)
- **Action** → script in the repo or a Salt execution module
- **Plugin** → Kubernetes API (Harvester), Salt modules, plain REST calls
- **Configuration element** → values in Git (policy file, Fleet `fleet.yaml` per-cluster overrides)
- **Policy (scheduled / event)** → scheduled workflows, Salt schedules/reactors, SUSE Multi-Linux Manager recurring actions
- **User interaction (approval)** → pull request review

## Honest gaps

- No visual workflow designer, so teams fluent in vRO JavaScript have to learn Git and YAML.
- Existing vRO workflows are rewritten, not imported. Most of their logic goes away because they mainly clone, reconfigure and call REST APIs, which become declarative here.
- Complex ordered orchestration across many external systems (ITSM, IPAM, DNS) still needs scripting: Actions steps or Salt orchestrate.
