# Porting Wildbound from TypeScript to Godot 4.4 (GDScript)

The TypeScript game in `/home/claude/wildbound/src` is the reference. Port behaviour 1:1: same rules,
same numbers, same layouts, same text. Do not redesign.

Godot binary: `/home/claude/godot/godot` (4.4.1). Project: `/home/claude/wildbound-godot`.

## Running

- Import / parse everything: `cd /home/claude/wildbound-godot && timeout 120 /home/claude/godot/godot --headless --import --path .`
  (prints SCRIPT ERROR / Parse Error lines for broken scripts).
- Headless script tests: `timeout 300 /home/claude/godot/godot --headless --path . -s res://tests/<file>.gd`
  (the script `extends SceneTree`; autoloads DB and Game are available as `root.get_node("DB")` after one `await process_frame`,
  and directly as `DB` / `Game` inside class scripts).
- Drive the real game and take screenshots (needs a GPU-less X server):
  `timeout 120 xvfb-run -a /home/claude/godot/godot --path . --rendering-driver opengl3 -s res://tests/drive.gd -- /tmp/claude-0/shots/<dir> key:Z wait:30 shot:title eval:"Game.top"`
  See the header of `tests/drive.gd` for the step syntax. Screenshots are 720x480 (3x). Ignore ALSA/audio errors.

## Already written (do not rewrite; small fixes are fine if you say so in your report)

- `scripts/main.gd` root Node2D; everything is immediate-mode drawn in its `_draw()`.
- `scripts/autoload/db.gd` = **DB** autoload. `DB.SPECIES`, `DB.MOVES`, `DB.ITEMS`, `DB.ABILITIES`, `DB.MAPS` (the full generated world:
  all 33 maps with tiles, connections, warps, doors, signs, npcs, trainers, encounters, exitGate, leagueGate...), `DB.STARTERS`,
  `DB.NATURE_NAMES`, `DB.NATURE_STATS`, `DB.TYPE_COLORS`, `DB.GYMS`, `DB.ROUTE_LEVELS`, `DB.PALETTES` (trainer palettes),
  `DB.STAT_KEYS`, functions `DB.species(id)`, `DB.move(id)`, `DB.item(id)`, `DB.type_multiplier10(atk, def)`, `DB.is_physical_type(t)`,
  `DB.nature_mod(nature, stat)`, `DB.type_color(t)`. Data comes from `data/*.json` (exported from the TS; whole numbers are ints).
  The TS world generator (`src/game/world.ts` buildWorld) is NOT ported: its output is in DB.MAPS.
- `scripts/autoload/game.gd` = **Game** autoload (TS `Game` in core.ts): `stack`, `input`, `gs`, `time`, `fade`, `push(s)`, `pop(s = null)`,
  `replace(s)`, `top`, `transition(cb: Callable)`, `say(msgs, on_done = Callable(), player = "any")`, `ask(msg, choices, on_choice, player = "any")`,
  `player_tag(player, x, y)`. TS code passed `game` around; in GDScript just use the `Game` autoload instead (drop the parameter).
- `scripts/core/scene.gd` **Scene** (RefCounted; `overlay`, `update(dt)`, `draw()`). Every TS `Scene` class extends it.
- `scripts/core/dialog.gd` **Dialog**, `scripts/core/list_menu.gd` **ListMenu** (opts dict keys snake_case: on_select, on_cancel, on_move,
  footer, max_visible, start, title, player, items, x, y, w).
- `scripts/core/game_input.gd` **GameInput** (`Game.input.p(i).pressed("a")`, `.is_held("b")`, `Game.input.any("a")`, `Game.input.coop`).
  Buttons are strings: up down left right a b start.
- `scripts/core/gfx.gd` **Gfx** static drawing helpers (TS gfx.ts primitives): `Gfx.W/H`, `rect`, `ellipse`, `image(tex, x, y, {scale, flip_h, modulate})`,
  `text(str, x, y, {color, size, align, shadow})`, `text_width`, `wrap`, `panel`, `cursor`, `hp_color`, `bar`, `type_badge`, `status_badge`,
  `shade(color, f)`, `hue_shift(color, deg)`, `STATUS_LABEL`. Coordinates are logical 240x160 pixels, same as TS. Colors: Color or "#hex"
  (`rgba(r,g,b,a)` strings from TS must become `Color(r/255.0, g/255.0, b/255.0, a)`). TS `ctx.globalAlpha` → pass `modulate`.

## Naming conventions (everyone follows these so the parts fit together)

1. **Plain data objects stay Dictionaries with the exact TS keys** (camelCase): a Creature (`uid, species, nickname, level, exp, personality,
   otId, ivs, evs, moves: [{id, pp, maxPp}], hp, status, sleepTurns, toxicCount, owner`), MoveSlot, MonView, BEvent (`{t: "msg", text: ...}`),
   Request, Action, Ref (`{side, slot}`), TrainerInit/BTrainer, BattleInit, GameState (`gs.players[0].party`, `gs.bag`, `gs.flags`...),
   LevelUpResult, map defs from DB.MAPS. `null` stays `null`; optional missing keys are simply absent (use `.get(key, default)`).
   Creature `status` is `null` or a status string. Godot allows `d.key` dot access on Dictionaries; use it.
2. **TS classes become GDScript classes** (`class_name` = TS class name, PascalCase). Their members and methods become snake_case
   (`benchFor` → `bench_for`, `effectiveSpeed` → `effective_speed`, `sideState` → `side_state`). TS getters become GDScript properties with
   `get:` under the same snake_case name (`battler.alive`, `battler.ref`, `battler.ability`, `battler.types`, `Game.top`).
3. **TS module-level functions become static functions** on a class named after the module, snake_case:
   - `src/engine/rng.ts` → `scripts/engine/rng.gd` `class_name Rng` (methods `next`, `int`... → `next_float()`, `int_below(n)`, `random16()`,
     `u32()`, `chance(percent)`, `pick(arr)`; `globalRng` → `Rng.global_rng` static var). (`int` and `next` clash with GDScript, hence the names.)
   - `src/engine/creature.ts` → `scripts/engine/creature.gd` `class_name Creatures`: `Creatures.create_creature(species, level, opts = {})`
     (opts keys as TS CreateOpts), `display_name(c)`, `nature_of`, `ability_of`, `gender_of`, `is_shiny`, `calc_stats`, `max_hp`,
     `exp_for_level(rate, n)`, `move_slot(id)`, `heal_fully`, `add_evs`, `gain_exp`, `exp_to_next`, `evolve`, `pending_evolution`,
     `set_next_uid`, `EV_STAT_CAP`, `EV_TOTAL_CAP`.
   - `src/engine/battle.ts` → `scripts/engine/battle.gd` `class_name Battle` with inner class `Battler` (`Battle.Battler`), static `Battle.view(c)`.
     `new Battle(init)` → `Battle.new(init)`. `submit(chosen: Map<string, Action>)` takes a Dictionary keyed by the same string key the TS used.
     `caught` is an Array of `{mon, player}`. `result`/`phase`/`kind` stay strings (or null).
   - `src/game/gfx.ts` art parts → `scripts/art/creature_art.gd` `class_name CreatureArt`: `creature_sprite(species_id, shiny = false, back = false) -> Texture2D`
     (64x64, cached), `silhouette(tex, color) -> Texture2D`, `is_floating(species_id)`; `scripts/art/trainer_art.gd` `class_name TrainerArt`:
     `draw_char(x, y, dir, step, pal: Dictionary)`, `draw_trainer_big(x, y, pal, back_view)` (palettes are `DB.PALETTES[name]` dicts of hex strings).
   - `src/game/tiles.ts` → `scripts/art/tiles.gd` `class_name Tiles`: `Tiles.tile_texture(ch, x, y, frame, above = "", below = "", theme = "#d8d0c0") -> Texture2D` (16x16, cached).
   - `src/game/maps.ts` → `scripts/game/maps.gd` `class_name Maps`: `Maps.WALKABLE`, `Maps.tile_at(map, x, y)` (maps come from DB.MAPS).
   - `src/game/state.ts` → `scripts/game/game_state.gd` `class_name GameState`: `new_game(mode, starters)`, `party_cap(gs)`, `all_party_mons(gs)`,
     `receive_creature(gs, mon, player)`, `save(gs)`, `has_save()`, `load_game()` (save file `user://wildbound-save.json`).
   - `src/game/menus.ts` → `scripts/game/menus.gd` `class_name Menus` for module functions (`Menus.open_bag(...)`, `Menus.use_item_on(...)`,
     `Menus.open_shop(...)`, `Menus.learn_move_flow(...)`...) plus scene classes each in its own file:
     `party_screen.gd` PartyScreen, `summary_screen.gd` SummaryScreen, `storage_screen.gd` StorageScreen, `evolution_scene.gd` EvolutionScene.
   - `src/game/battleScene.ts` → `scripts/game/battle_scene.gd` `class_name BattleScene`.
   - `src/game/overworld.ts` → `scripts/game/overworld.gd` `class_name OverworldScene`; `src/game/title.ts` → `scripts/game/title.gd`
     `TitleScene` and `scripts/game/starter_scene.gd` `StarterScene`.
   Function parameters keep TS order; drop the leading `game` parameter. Callbacks become `Callable`s (use lambdas `func(): ...`).
4. Integer math: GDScript `int` is 64-bit and `/` on two ints already floors toward zero (same as Math.floor for non-negatives).
   Where TS used `>>> 0`, `Math.imul` or 32-bit wraparound, mask with `& 0xFFFFFFFF` explicitly. Keep every Gen 3 floor where the TS has one.
5. Type everything you reasonably can (`var x: int`, `-> Dictionary`). Tabs for indentation. Keep the TS comments that explain rules.

## Ownership

Four people port in parallel. Only edit the files you own. If you need something from someone else's file that isn't there yet,
code against the names above; it will exist when we integrate. If you believe a name above is wrong for your needs, say so in your report.
