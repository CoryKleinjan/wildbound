# Wildbound (Godot 4)

A creature-collecting RPG in the style of the Gen 3 handheld games, built so two people can play together on one computer.

- **Solo:** you carry up to 6 creatures.
- **Co-op:** each player carries up to 3 creatures. Every battle is a double battle with one creature from each player side by side, and each player picks their own creature's moves.

All creatures, names, maps and art are original (drawn procedurally in code). Battle rules follow Generation 3 (Ruby/Sapphire/Emerald).

## Play

- **Ready-made builds:** download Windows, macOS or Linux from the [Releases page](https://github.com/CoryKleinjan/wildbound/releases) (macOS is unsigned; right-click > Open the first time).
- **From source:** open this folder in Godot 4.4 and press Play (F5).

| | Solo | Co-op Player 1 | Co-op Player 2 |
|---|---|---|---|
| Move | Arrows / WASD | WASD | Arrows |
| A (confirm) | Z / Enter / Space / F | F | Enter |
| B (back, hold to run) | X / Shift / G | G | Right Shift |
| Menu | Esc / C / R | R | Backspace |

Gamepads work too (pad 1 = Player 1, pad 2 = Player 2). Saves go to Godot's user folder (`user://wildbound-save.json`).

## What's in it

- 200 creatures across all 17 types, with evolutions, learnsets, abilities and 7 legendaries.
- 12 towns joined by 12 routes, 8 gyms (badge needed to leave each gym town onward) and the League in Summitcrown (needs all 8 badges).
- Each town has its own look (`data/town_styles.json`, applied by `scripts/art/town_style.gd` on top of whatever tile art is loaded): autumn fields in Harrowfield, snow and pines in Summit Crown, palms and white sand in Coralhaven, and so on. Cinder City is the big city, with avenues, street lamps, a fountain plaza and a two-floor department store (`tools/build_towns.py`).
- Every town door leads inside: your house, Rest Lodges (nurse + storage machine), Trail Marts (clerk at the counter) and homes with people to talk to. Rooms are built by `tools/build_interiors.py` into `data/interiors.json`.
- Trainers with line of sight, a rival, wild encounters, catching with Capture Orbs, Rest Lodges, Marts, storage, bag, party, summary (stats, IVs, EVs, nature), a Creaturedex and saving.

## Gen 3 mechanics (`scripts/engine/`)

Gen 3 stat formulas with IVs/EVs/natures, the `CalculateBaseDamage` order with integer flooring, physical/special by type, crit stages, the accuracy/evasion table, turn order with priority and speed, sleep/freeze/paralysis/burn/poison/toxic/confusion/flinch, Leech Seed, Protect, weather, 34 abilities, the Gen 3 catch formula with four shake checks, the escape formula, EXP split with the trainer bonus and all six growth curves.

## Layout

- `scripts/engine/` battle engine (`battle.gd`, `creature.gd`, `rng.gd`) with no rendering.
- `scripts/game/` overworld, battle screen, menus, title and save state.
- `scripts/art/` procedural creature sprites, trainers and tiles.
- `scripts/core/` drawing helpers, input, dialog and list menus. Everything is drawn on a 240x160 screen scaled to the window.
- `data/*.json` creatures, moves, items, abilities and all 33 maps (edit these to change content).

## Tests

```
godot --headless --path . -s res://tests/engine_test.gd   # formulas + 400 random battles
godot --headless --path . -s res://tests/world_test.gd    # every map reachable, gates and warps valid
```

`tests/drive.gd` drives the real game with key presses and screenshots (see its header).

## Next steps

- Online co-op (Godot's high-level multiplayer) on top of the same engine: the engine already takes one action per battle position.
- Held items and berries, caves and surfing, sound and music.
