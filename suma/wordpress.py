#!/usr/bin/env python3
"""Publishes the portable WordPress Salt state to SUSE Multi-Linux Manager and drives registration via its API.

  wordpress.py setup               create/update state channel "wordpress" + activation key "1-wordpress"
  wordpress.py accept <minion-id>  accept a pending Salt minion key (the security gate before registration)
  wordpress.py highstate <minion>  schedule a highstate (only needed if registration did not apply one)
  wordpress.py status              show the channel, key and registered systems

Env: SUMA_URL (default https://suma.5glinux.com), SUMA_USER (admin), SUMA_PASSWORD_FILE (password file),
SUMA_INSECURE=1 to accept the server's self-signed CA. No secrets are stored in the repository.
"""
import datetime, os, pathlib, re, ssl, sys, xmlrpc.client

HERE = pathlib.Path(__file__).resolve().parent
SALT = HERE.parent / "salt" / "wordpress"
CHANNEL, KEY = "wordpress", "wordpress"            # activation keys get the org prefix: 1-wordpress
BASE = os.environ.get("SUMA_BASE_CHANNEL", "sle-product-sles-16.1-x86_64")

url = os.environ.get("SUMA_URL", "https://suma.5glinux.com").rstrip("/") + "/rpc/api"
ctx = ssl._create_unverified_context() if os.environ.get("SUMA_INSECURE") == "1" else None
api = xmlrpc.client.ServerProxy(url, context=ctx)
sk = api.auth.login(os.environ.get("SUMA_USER", "admin"),
                    pathlib.Path(os.environ["SUMA_PASSWORD_FILE"]).read_text().strip())


def channel_sls():
    """init.sls with map.jinja inlined: a state channel holds one init.sls."""
    init = (SALT / "init.sls").read_text()
    mapj = (SALT / "map.jinja").read_text()
    return re.sub(r'\{% from tpldir ~ "/map.jinja" import .* %\}\n', lambda _: mapj + "\n", init, count=1)


def setup():
    labels = [c["label"] for c in api.configchannel.listGlobals(sk)]
    if CHANNEL not in labels:
        api.configchannel.create(sk, CHANNEL, "WordPress (Salt state)",
                                 "Apache + PHP + MariaDB + WordPress, same state as the Aria cloud template", "state")
    api.configchannel.updateInitSls(sk, CHANNEL, {"contents": channel_sls()})
    print(f"state channel {CHANNEL}: init.sls updated")

    keys = {k["key"]: k for k in api.activationkey.listActivationKeys(sk)}
    full = next((k for k in keys if k.endswith("-" + KEY)), None)
    if not full:
        full = api.activationkey.create(sk, KEY, "WordPress VMs: SLES 16.1 channels + wordpress state", BASE, [], False)
    children = [c["label"] for c in api.channel.software.listChildren(sk, BASE)]
    if children:
        api.activationkey.addChildChannels(sk, full, children)
    api.activationkey.addConfigChannels(sk, [full], [CHANNEL], True)
    api.activationkey.enableConfigDeployment(sk, full)
    print(f"activation key {full}: base {BASE}, children {children}, config channel {CHANNEL}, config deployment on")


def accept(minion):
    pending = api.saltkey.pendingList(sk)
    if minion not in pending:
        sys.exit(f"{minion} not pending; pending keys: {pending}")
    api.saltkey.accept(sk, minion)
    print("accepted", minion)


def system_id(minion):
    ids = [s["id"] for s in api.system.getId(sk, minion)]
    if not ids:
        sys.exit(f"{minion} is not registered yet")
    return ids[0]


def highstate(minion):
    action = api.system.scheduleApplyHighstate(sk, system_id(minion), datetime.datetime.now(), False)
    print(f"highstate scheduled for {minion}: action {action}")


def status():
    print("config channels:", [c["label"] for c in api.configchannel.listGlobals(sk)])
    print("activation keys:", [k["key"] for k in api.activationkey.listActivationKeys(sk)])
    print("pending minion keys:", api.saltkey.pendingList(sk))
    for s in api.system.listSystems(sk):
        print(f"system {s['name']} (id {s['id']}), base channel:",
              api.system.getSubscribedBaseChannel(sk, s["id"]).get("label"))


cmd, args = (sys.argv[1] if len(sys.argv) > 1 else "status"), sys.argv[2:]
{"setup": setup, "status": status, "accept": lambda: accept(*args), "highstate": lambda: highstate(*args)}[cmd]()
api.auth.logout(sk)
