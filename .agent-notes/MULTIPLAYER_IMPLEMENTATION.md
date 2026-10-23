# Local multiplayer implementation

## Roles and authority

`NetworkManager` is an autoload on every instance, so its RPC path remains
`/root/NetworkManager` while the menu and field scenes change. ENet uses UDP 7000
by default, with a configurable port and eight remote player slots.

The server is an observer, not a player. Its 60 Hz physics loop owns all positions,
uses a fixed movement speed of 240 pixels/second, and clamps player centers inside
the field with a 16 pixel margin. Clients send direction vectors, never positions
or player IDs. RPC sender IDs identify the player. Non-finite vectors are ignored,
vector length is capped at one, and input older than 0.5 seconds stops movement.
Client-to-client packet relaying is disabled.

The client samples WASD at physics ticks and sends input at 30 Hz, or immediately
when direction changes. It sends zero input when its window loses focus. Visible
avatars interpolate toward the latest server positions; there is no local
prediction, so movement response includes a network round trip.

## Joining and state

After ENet reports a successful connection, the client sends its protocol version
and display name to the server. The server assigns a free spawn slot and color,
sanitizes the name to 24 characters, and sends the current world. Late joiners get
the existing players at their current positions. No player is spawned for the
server itself, and no lobby or character-selection step is needed.

Membership updates are reliable on channel 0. Movement snapshots contain the
complete player dictionary at 20 Hz using unreliable ordered delivery on channel
2. Each snapshot carries a monotonically increasing sequence number. The client
ignores old sequences across both channels so delayed updates cannot rewind
positions or resurrect departed players. The first accepted world snapshot
finishes joining; snapshots are stored in the autoload even while a scene loads.

## Pulses

Space sends a reliable request on channel 0. The server permits one pulse per
player every 0.75 seconds and broadcasts the player's server position and color.
The server observer and clients draw the same expanding ring for 0.65 seconds.
Pulses are visual effects, not damage or persistent world objects.

## Failure and cleanup

Disconnecting removes the player and all input, cooldown, and spawn-slot state on
the server, then reliably publishes the remaining roster. Clients clear their
world on disconnect and can reconnect with a new peer ID. Failed joins time out
after eight seconds. A client with no server snapshots for three seconds ends its
session even if the server process crashed without sending a disconnect packet.
Connection attempts carry a local generation counter so an earlier timeout
cannot cancel a later successful attempt.

This is an open local-network prototype. User accounts, passwords, save-game
persistence, server discovery, and Internet hosting are future additions. Desktop
clients and servers should use the same project build and Godot version.
