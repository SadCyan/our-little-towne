"""Run real Godot/ENet server and clients. Requires Python 3, no packages.

Usage: python tests/run_network_checks.py --godot /path/to/godot
"""
import argparse
import json
import math
import os
from pathlib import Path
import socket
import subprocess
import time


class Peer:
    def __init__(self, engine, repo, directory, name, port, role="client"):
        self.report = directory / (name + ".json")
        self.commands = directory / (name + ".command.json")
        self.sequence = 0
        self.output = open(directory / (name + ".log"), "w", encoding="utf-8")
        scene = "res://tests/ui_peer.tscn" if role == "ui" else "res://tests/network_peer.tscn"
        self.process = subprocess.Popen([
            str(engine), "--headless", "--path", str(repo),
            "--log-file", str(directory / (name + ".engine.log")),
            scene, "--", "--role=" + role,
            "--name=" + name, "--port=" + str(port),
            "--report=" + str(self.report), "--commands=" + str(self.commands),
        ], stdout=self.output, stderr=subprocess.STDOUT,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)

    def state(self):
        try:
            return json.loads(self.report.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return {}

    def command(self, action, **payload):
        self.sequence += 1
        message = dict(sequence=self.sequence, action=action, **payload)
        self.commands.write_text(json.dumps(message), encoding="utf-8")
        wait_until(lambda: self.state().get("command") == self.sequence,
                   "command " + action + " acknowledged")

    def close(self):
        if self.process.poll() is None:
            self.process.terminate()
            self.process.wait(timeout=5)
        self.output.close()


def wait_until(condition, label, timeout=10):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if condition():
            return
        time.sleep(0.04)
    raise AssertionError("Timed out: " + label)


def player(peer, name):
    return next((p for p in peer.state().get("players", {}).values()
                 if p["name"] == name), None)


def distance(a, b):
    return math.dist(a["position"], b["position"])


def run(engine):
    repo = Path(__file__).resolve().parents[1]
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    peers = []
    # Keep logs after a failure to make network regressions diagnosable.
    output_root = repo / ".test-output"
    output_root.mkdir(exist_ok=True)
    directory = output_root / ("network-" + str(time.time_ns()))
    directory.mkdir()
    print("Logs:", directory, flush=True)
    try:
        server = Peer(engine, repo, directory, "server", port, "server")
        peers.append(server)
        wait_until(lambda: server.state().get("active"), "server starts")
        assert not server.state()["players"], "dedicated server has no phantom player"
        alice = Peer(engine, repo, directory, "Alice", port)
        bob = Peer(engine, repo, directory, "Bob", port)
        peers.extend([alice, bob])
        wait_until(lambda: all(len(p.state().get("players", {})) == 2
                              for p in [server, alice, bob]), "two clients join")
        assert alice.state()["id"] != bob.state()["id"]
        assert len({tuple(p["position"]) for p in server.state()["players"].values()}) == 2
        print("PASS: separate players, complete shared roster, no host avatar", flush=True)

        alice_start = player(server, "Alice")
        bob_start = player(server, "Bob")
        alice.command("move", direction=[100, 100])
        time.sleep(0.8)
        alice.command("move", direction=[0, 0])
        time.sleep(0.15)
        moved = distance(alice_start, player(server, "Alice"))
        assert 150 < moved < 240, ("server normalizes speed", moved)
        assert distance(bob_start, player(server, "Bob")) < 0.01, "Alice cannot move Bob"
        wait_until(lambda: distance(player(alice, "Alice"), player(bob, "Alice")) < 0.01,
                   "clients converge on server position")
        print("PASS: independent movement, diagonal speed cap, matching snapshots", flush=True)

        alice.command("move", direction=[1, 0])
        time.sleep(0.1)
        alice.command("silence")
        time.sleep(0.7)
        stopped = player(server, "Alice")
        time.sleep(0.3)
        assert distance(stopped, player(server, "Alice")) < 0.01, "stale input stops movement"
        alice.command("invalid_input")
        time.sleep(0.15)
        assert distance(stopped, player(server, "Alice")) < 0.01, "reject NaN/Inf input"
        print("PASS: dropped input stops movement; invalid vectors rejected", flush=True)

        alice.command("pulse_twice")
        wait_until(lambda: all(len(p.state().get("pulses", [])) == 1
                              for p in [server, alice, bob]), "pulse reaches everybody once")
        origins = [p.state()["pulses"][0]["origin"] for p in [server, alice, bob]]
        assert origins[0] == origins[1] == origins[2]
        time.sleep(0.8)
        bob.command("pulse")
        wait_until(lambda: all(len(p.state().get("pulses", [])) == 2
                              for p in [server, alice, bob]), "second player pulses")
        print("PASS: shared pulse origin, cooldown enforced, both players can pulse", flush=True)

        late = Peer(engine, repo, directory, "Late", port)
        peers.append(late)
        wait_until(lambda: all(len(p.state().get("players", {})) == 3
                              for p in [server, alice, bob, late]), "late join sees current world")
        assert distance(player(late, "Alice"), player(server, "Alice")) < 0.01
        late.command("disconnect")
        wait_until(lambda: all(len(p.state().get("players", {})) == 2
                              for p in [server, alice, bob]), "departure removed from every roster")
        print("PASS: late join receives moved players; disconnect removes avatar", flush=True)

        old_id = alice.state()["id"]
        alice.command("disconnect")
        wait_until(lambda: len(server.state().get("players", {})) == 1, "Alice disconnects")
        alice.command("reconnect")
        wait_until(lambda: alice.state().get("active") and len(bob.state().get("players", {})) == 2,
                   "Alice reconnects")
        assert str(old_id) not in server.state()["players"]
        alice.command("move", direction=[-1, 0])
        time.sleep(3)
        alice.command("move", direction=[0, 0])
        time.sleep(0.1)
        assert abs(player(server, "Alice")["position"][0] - 80) < 0.01, "field boundary enforced"
        print("PASS: reconnect replaces old ID; movement stays inside field", flush=True)

        ui_client = Peer(engine, repo, directory, "MenuPlayer", port, "ui")
        peers.append(ui_client)
        wait_until(lambda: ui_client.state().get("active")
                   and len(ui_client.state().get("players", {})) == 3, "menu join loads field")
        time.sleep(0.1)
        alice.command("pulse")
        wait_until(lambda: len(ui_client.state().get("pulses", [])) == 1, "menu client receives pulse")
        ui_client.command("view_pulse")
        assert not ui_client.state()["error"], ui_client.state()["error"]
        print("PASS: join form enters actual field scene with avatars and pulse animation", flush=True)

        guests = []
        for i in range(5):
            guest = Peer(engine, repo, directory, "Guest" + str(i), port)
            peers.append(guest)
            guests.append(guest)
        full_roster = [server, alice, bob, ui_client] + guests
        wait_until(lambda: all(len(p.state().get("players", {})) == 8 for p in full_roster),
                   "eight simultaneous players")
        overflow = Peer(engine, repo, directory, "Overflow", port)
        peers.append(overflow)
        wait_until(lambda: not overflow.state().get("connecting", True)
                   and bool(overflow.state().get("error")), "ninth client rejected")
        assert not overflow.state()["active"] and len(server.state()["players"]) == 8
        print("PASS: eight clients share the world; ninth client fails cleanly", flush=True)

        # Kill abruptly: clients must recover even without a goodbye packet.
        server.close()
        wait_until(lambda: not alice.state().get("active", True)
                   and not bob.state().get("active", True), "server loss detected", timeout=6)
        time.sleep(0.1)
        assert not ui_client.state()["error"].startswith("UI failure"), ui_client.state()["error"]
        assert not alice.state()["players"] and not bob.state()["players"]
        print("PASS: server loss clears clients and permits another connection", flush=True)

        # A failed attempt must clean up and then allow a successful retry.
        alice.command("reconnect")
        wait_until(lambda: not alice.state().get("connecting", True), "connection timeout", timeout=10)
        assert not alice.state()["active"] and not alice.state()["players"]
        replacement = Peer(engine, repo, directory, "replacement", port, "server")
        peers.append(replacement)
        wait_until(lambda: replacement.state().get("active"), "replacement server starts")
        alice.command("reconnect")
        wait_until(lambda: alice.state().get("active"), "retry succeeds")
        print("PASS: unavailable server times out; retry succeeds", flush=True)
        print("All network integration checks passed.", flush=True)
    finally:
        for peer in peers:
            peer.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True, type=Path)
    run(parser.parse_args().godot.resolve())
