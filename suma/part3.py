#!/usr/bin/env python3
"""Part 3: Aria-style day-2 automation with SUSE Multi-Linux Manager (API calls used in the demo).

  part3.py group                      system group "wordpress": wordpress formula (form data) instead of the state
                                      channel; activation key 1-wordpress adds new VMs to the group
  part3.py recurring                  hourly recurring highstate on the group (drift enforcement)
  part3.py clm                        Content Lifecycle project "wordpress": SLES 16.1 sources, dev -> prod, build
  part3.py promote                    promote dev -> prod
  part3.py use-prod <minion>          move a system and the activation key to the prod channels
  part3.py chain <minion> [--run]     action chain wordpress-maintenance: upgrade outdated packages, highstate,
                                      smoke test (suma/smoke-test.sh); scheduled only with --run
  part3.py status                     show group, formula data, recurring actions, CLM environments, chains

Env: as suma/wordpress.py (SUMA_URL, SUMA_USER, SUMA_PASSWORD_FILE, SUMA_INSECURE=1).
"""
import base64, datetime, os, pathlib, ssl, sys, xmlrpc.client

HERE = pathlib.Path(__file__).resolve().parent
GROUP, KEY, PROJECT, CHAIN = "wordpress", "1-wordpress", "wordpress", "wordpress-maintenance"
SOURCES = ["sle-product-sles-16.1-x86_64", "multi-linux-managertools-sle-16-x86_64-sles-16.1"]
FORM = {"wordpress": {"site_title": "Managed by SUSE Multi-Linux Manager",
                      "tagline": "Day-2 change rolled out with Salt", "admin_email": "admin@example.com"}}

url = os.environ.get("SUMA_URL", "https://suma.5glinux.com").rstrip("/") + "/rpc/api"
ctx = ssl._create_unverified_context() if os.environ.get("SUMA_INSECURE") == "1" else None
api = xmlrpc.client.ServerProxy(url, context=ctx)
sk = api.auth.login(os.environ.get("SUMA_USER", "admin"),
                    pathlib.Path(os.environ["SUMA_PASSWORD_FILE"]).read_text().strip())
now = datetime.datetime.now


def sid_of(minion):
    return api.system.getId(sk, minion)[0]["id"]


def group_id():
    groups = {g["name"]: g for g in api.systemgroup.listAllGroups(sk)}
    return (groups.get(GROUP) or api.systemgroup.create(sk, GROUP, "WordPress VMs: wordpress formula"))["id"]


def group():
    gid = group_id()
    api.formula.setFormulasOfGroup(sk, gid, ["wordpress"])
    if not api.formula.getGroupFormulaData(sk, gid, "wordpress"):
        api.formula.setGroupFormulaData(sk, gid, "wordpress", FORM)
    members = [s["id"] for s in api.systemgroup.listSystemsMinimal(sk, GROUP)]
    for s in api.system.listSystems(sk):
        if s["name"].startswith("wp-") and s["id"] not in members:
            api.systemgroup.addOrRemoveSystems(sk, GROUP, [s["id"]], True)
        if [c for c in api.system.config.listChannels(sk, s["id"]) if c["label"] == "wordpress"]:
            api.system.config.removeChannels(sk, [s["id"]], ["wordpress"])     # formula replaces the state channel
    if [c for c in api.activationkey.listConfigChannels(sk, KEY) if c["label"] == "wordpress"]:
        api.activationkey.removeConfigChannels(sk, [KEY], ["wordpress"])
    api.activationkey.addServerGroups(sk, KEY, [gid])
    print(f"group {GROUP} (id {gid}): formula wordpress, activation key {KEY} adds new systems to it")


def recurring():
    gid = group_id()
    if not api.recurring.listByEntity(sk, "group", gid):
        api.recurring.highstate.create(sk, {"entity_type": "group", "entity_id": gid,
                                            "name": "wordpress-hourly-highstate", "cron_expr": "0 15 * * * ?",
                                            "test": False})
    print("recurring:", [(a["name"], a.get("cron_expr")) for a in api.recurring.listByEntity(sk, "group", gid)])


def clm():
    if PROJECT not in [p["label"] for p in api.contentmanagement.listProjects(sk)]:
        api.contentmanagement.createProject(sk, PROJECT, "WordPress platform", "Frozen SLES 16.1 content, dev -> prod")
    have = [s["channelLabel"] for s in api.contentmanagement.listProjectSources(sk, PROJECT)]
    for ch in SOURCES:
        if ch not in have:
            api.contentmanagement.attachSource(sk, PROJECT, "software", ch)
    envs = [e["label"] for e in api.contentmanagement.listProjectEnvironments(sk, PROJECT)]
    if "dev" not in envs:
        api.contentmanagement.createEnvironment(sk, PROJECT, "", "dev", "Development", "New content lands here")
    if "prod" not in envs:
        api.contentmanagement.createEnvironment(sk, PROJECT, "dev", "prod", "Production", "Promoted after validation")
    api.contentmanagement.buildProject(sk, PROJECT, "Snapshot of SLES 16.1 for WordPress")
    print("build started; promote with: part3.py promote")


def promote():
    api.contentmanagement.promoteProject(sk, PROJECT, "dev")
    print("promotion to prod started")


def use_prod(minion):
    base, tools = (f"{PROJECT}-prod-{ch}" for ch in SOURCES)
    print("change channels action", api.system.scheduleChangeChannels(sk, sid_of(minion), base, [tools], now()))
    api.activationkey.setDetails(sk, KEY, {"base_channel_label": base})
    old = [c for c in api.activationkey.getDetails(sk, KEY).get("child_channel_labels", []) if c != tools]
    if old:
        api.activationkey.removeChildChannels(sk, KEY, old)
    api.activationkey.addChildChannels(sk, KEY, [tools])
    print(f"{KEY} now uses {base}")


def chain(minion, run=False):
    sid = sid_of(minion)
    if CHAIN in [c["label"] for c in api.actionchain.listChains(sk)]:
        api.actionchain.deleteChain(sk, CHAIN)
    api.actionchain.createChain(sk, CHAIN)
    upgrades = [p["to_package_id"] for p in api.system.listLatestUpgradablePackages(sk, sid)]
    if upgrades:
        api.actionchain.addPackageUpgrade(sk, sid, upgrades, CHAIN)
    api.actionchain.addApplyHighstate(sk, sid, CHAIN)
    script = base64.b64encode((HERE / "smoke-test.sh").read_bytes()).decode()   # chain script runs are base64
    api.actionchain.addScriptRun(sk, sid, CHAIN, "root", "root", 120, script)
    print(f"{CHAIN}: {len(upgrades)} package upgrade(s), highstate, smoke test")
    if run:
        api.actionchain.scheduleChain(sk, CHAIN, now())
        print("scheduled")


def status():
    gid = group_id()
    print("group members:", [s.get("name") for s in api.systemgroup.listSystemsMinimal(sk, GROUP)])
    print("formula data:", api.formula.getGroupFormulaData(sk, gid, "wordpress"))
    print("recurring:", [(a["name"], a.get("cron_expr"), a.get("active")) for a in api.recurring.listByEntity(sk, "group", gid)])
    print("clm:", [(e["label"], e.get("status"), e.get("version")) for e in api.contentmanagement.listProjectEnvironments(sk, PROJECT)])
    print("chains:", [c["label"] for c in api.actionchain.listChains(sk)])
    print("activation key base:", api.activationkey.getDetails(sk, KEY)["base_channel_label"])


cmd, args = (sys.argv[1] if len(sys.argv) > 1 else "status"), sys.argv[2:]
{"group": group, "recurring": recurring, "clm": clm, "promote": promote, "status": status,
 "use-prod": lambda: use_prod(args[0]), "chain": lambda: chain(args[0], "--run" in args)}[cmd]()
api.auth.logout(sk)
