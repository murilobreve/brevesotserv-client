# game_orbita (Órbita)

Every Mythicus or Legendarius item a player wears is a small cut gem circling
the character. Loaded with `game_interface` (after `game_voice`).

## What it shows

- **Cut**: the gem's outline recalls the piece: helmet, amulet, armor, shield,
  weapon, ring, legs, boots (`images/core_<slot>_<element>.png`). A spellbook
  is a shield.
- **Height**: three turns (`BANDS` in `orbita.lua`). Helmet and amulet circle
  the head (smaller, faster); armor, weapon, shield and ring the chest; legs
  and boots the feet. A mounted character's orbit is lifted with the rider.
- **Colour**: the item's first element, the colours of
  `game_shaders/shaders/fragment/rarity_item.frag`; white for an item with
  no element.
- **Grade**: a Mythicus is the large gem with a two-ghost trail; a Legendarius
  the small one without. Lower grades show nothing.
- **Depth**: on the far half of the turn the layers are drawn under the
  character, on the near half over it.
- **State**: rest (9 s a turn, faint) and combat (3.4 s, bright) blend over
  about half a second. My own character is in combat by the in-fight state;
  another player while their health moved in the last 4 s.
- **Proc**: on my own character, a gem flashes for 520 ms when a bonus of its
  item fires (Vital Barrier, Reflect, Splinter, Cleave, Momentum).
- **Set marks**, by the number of Mythicus: 3 a dashed seal on the floor, 5 a
  glow in the dominant element, 8 the chest turn drawn as a ring.

## Where the sets come from

The server (`data-otservbr-global/scripts/rarity/orbit.lua` in the server
repository), extended opcode 143, JSON. The client says `hi` at game start
and asks for the players that come into view; the server sends a player's
set when it changes (within the rarity bonus tick, 2 s) to the players who
see them. A server without the script never answers and nothing is drawn.

## Options

In the Interface window (`game_textmessage`), under "Rare items in orbit":

| Option | Setting | Whose |
|---|---|---|
| Show on every player / only on my character / off | `orbita_mode` | client |
| Mythicus and Legendarius / Mythicus only | `orbita_mythic_only` | client |
| Other players see my orbit / hide it from them | player kv `orbita/hide` | server |

A hidden set is never sent to anyone but its owner.

## Cost

A gem is 3 to 5 image layers (`g_attachedEffects.registerByImage`, one clone
per layer) moved every 33 ms. With 6 or more orbits on screen the other
players' gems lose trail and glow layers, with 14 or more the halo too, and
the others move every second tick. An engine without image layers (an old
executable) leaves the module off.

## Checked on a local server (2026-11-15)

Three characters with real rarity items: sets on login, on coming into view
and on equipping or removing an item; the three options, hiding seen from
another client; the flash; walking in the four directions; a mount; the
light drawing modes (thresholds forced down). Not checked: many players at
once, and outfits much larger or smaller than a human.

## Textures

`python3 tools/orbita/make_textures.py modules/game_orbita/images`
(halos, aura, ring, seal, spark) and
`python3 tools/orbita/make_slots.py modules/game_orbita/images [sheet.png]`
(the eight cuts in the eight colours). Python 3 with Pillow and NumPy.
