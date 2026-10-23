# Our Little Towne

A small Godot 4.7.2 desktop multiplayer prototype: a dedicated local server owns
one shared field, and each connected client controls its own player.

## Run on a local network

1. Open `project.godot` in Godot 4.7.2 and run the project (F6 runs an individual
   scene; use F5 for the complete application).
2. On the server computer, choose a UDP port (default **7000**) and click
   **Start server**. Keep that instance running. The graphical server observes
   the field and does not occupy a player slot.
3. Each player runs another instance, enters a name, the server computer's local
   IP address (for example `192.168.1.10`), and the same port, then clicks
   **Join server**. The menu lists this computer's network addresses. On Windows,
   `ipconfig` also shows them; use the address of the network shared by the players.
4. To play on the server computer, open a second instance and join **127.0.0.1**.
5. Use **WASD** to move and **Space** to emit a colored pulse. Everyone sees all
   players and pulses. **Esc** or **Disconnect** returns a client to the menu.
   **Stop server** ends the session for all players.

Allow the Godot executable (or exported game) through the server computer's
firewall on your private network, including inbound **UDP** traffic on the chosen
port. All computers must be on a network that permits communication between them;
Wi-Fi guest networks can isolate devices. Router port forwarding is unnecessary
for players on the same local network.

The server accepts up to **eight players**. Access is open to anyone who can
reach its UDP port; this prototype has no password or user accounts. World state
is held in memory for the current server session. Existing character/world save
files are not used by this field prototype.

## Server without a window

The same project or exported game runs as either a server or a client. Godot
options go before `--`; application options go after it:

```powershell
# From the repository directory; substitute your Godot executable's path.
& "C:\path\to\godot.exe" --headless --path . -- --server --port=7000

# Optional direct client startup; normally clients use the menu.
& "C:\path\to\godot.exe" --path . -- --connect=192.168.1.10 --port=7000 --name=Alice
```

For an exported desktop executable:

```powershell
.\OurLittleTowne.exe --headless -- --server --port=7000
.\OurLittleTowne.exe -- --connect=192.168.1.10 --port=7000 --name=Alice
```

A dedicated-server export also starts the server automatically. Headless servers
keep running until their process is stopped. A client whose connection fails,
server disappears, or join times out returns to the menu and can retry.

## Core structure

- `network_manager.gd`: persistent ENet connection, player registration, server
  simulation, input validation, snapshots, pulse events, and connection cleanup.
- `main_menu.gd` / `.tscn`: start/join form, startup options, and connection status.
- `main_game.gd` / `.tscn`: shared field, client controls, pulse animation, and HUD.
- `player.gd` / `.tscn`: colored avatar and label, interpolated toward server state.
- `project.godot`: portable main-scene path, configured inputs, and compatibility
  renderer suitable for this simple 2D scene.

The earlier character creation, world selection, and lobby scenes remain as
reference prototypes. They are not used by the current application and still
refer to the old networking flow. `MULTIPLAYER_IMPLEMENTATION.md` describes the
current protocol; older analysis documents describe the previous prototype.

## Check multiplayer changes

With Godot 4.7.2 and Python 3 available:

```powershell
python tests/run_network_checks.py --godot "C:\path\to\godot.exe"
```

The runner starts separate real ENet server/client processes on an available
local UDP port. It checks independent movement, normalized speed, field bounds,
matching state, invalid/stale input, pulse delivery and cooldown, late joins,
disconnect/reconnect, the actual join form and field scene, eight-client capacity,
server loss, and failed-connection recovery. Logs are kept
in `.test-output/` (ignored by Git). This checks localhost networking; a second
physical computer is needed to check your network's firewall and routing.
