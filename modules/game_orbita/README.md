# game_orbita (Órbita, prototype)

Every Mythicus or Legendarius item a player wears is a small cut gem circling
the character. Not loaded by the client: it is not in
`modules/game_interface/interface.otmod`. It ran on a local Linux build of this
client (2026-11-15) driven by a text file, with no server part.

## What it shows

- **Cut**: the gem's outline recalls the piece: helmet, amulet, armor, shield,
  weapon, ring, legs, boots (`images/core_<slot>_<element>.png`).
- **Height**: three turns (`BANDS` in `orbita.lua`). Helmet and amulet circle
  the head (smaller, faster); armor, weapon, shield and ring the chest; legs
  and boots the feet.
- **Colour**: the item's element, the colours of
  `game_shaders/shaders/fragment/rarity_item.frag`.
- **Grade**: a Mythicus is the large gem with a two-ghost trail; a Legendarius
  the small one without. Lower grades show nothing.
- **Depth**: on the far half of the turn the layers are drawn under the
  character (`setOnTop(false)`), on the near half over it.
- **State**: `heat` blends between rest (9 s a turn, faint) and combat (3.4 s,
  bright) over about half a second.
- **Proc**: a gem flashes for 520 ms (core grows, halo widens, a star).
- **Set marks**, by the number of Mythicus: 3 a dashed seal on the floor, 5 a
  glow in the dominant element, 8 the chest turn drawn as a ring.

## How it is drawn

Image attached effects (`g_attachedEffects.registerByImage`), one clone per
layer per gem, attached to the creature; a 30 ms `cycleEvent` moves each with
`setSize`, `setOffset`, `setOpacity` and `setOnTop`. A full set is about 34
layers on one creature.

## What is prototype only

- Who wears what comes from `/orbita_cmd.txt` in the client's work dir, polled
  every 100 ms (`set`, `state`, `proc`, `clear`; see the top of `orbita.lua`).
  The server sends nothing.
- `state` and `proc` were fired by the recording script, not by combat or by a
  bonus.
- Ids 9400 to 9990 of `g_attachedEffects` are taken without checking the other
  modules.
- `images/core_<element>.png` (a plain diamond, the first cut) is registered
  but no longer drawn.

## Left to decide or do

- The server tells each client the rare items of the players on screen (slot,
  grade, element), on equip, on login and when a player comes into view.
- Combat state and procs from the real events.
- Options: hide my own orbit (PvP shows a player's gear to enemies), show only
  mine (a war with 30 players), Mythicus only.
- With 8 pieces the glow adds up: it was toned down for more than 5 gems
  (`n > 5` in `update`), and could go further in combat.
- Helmet and amulet read small on the head turn; legs and boots read well.
- Mounted characters, outfits of other sizes and the four directions were not
  looked at: `CENTER` and `BANDS` assume a standing character facing south.

## Textures

`python3 tools/orbita/make_textures.py modules/game_orbita/images [sheet.png]`
(halos, aura, ring, seal, spark) and
`python3 tools/orbita/make_slots.py modules/game_orbita/images [sheet.png]`
(the eight cuts in the eight colours). Python 3 with Pillow and NumPy.
