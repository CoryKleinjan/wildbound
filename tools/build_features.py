#!/usr/bin/env python3
"""Builds data/features.json: the Emerald-style systems layered on top of the generated world.

It adds moves, items and abilities, patches species (abilities, evolutions, egg groups, TM and
tutor compatibility, wild held items, extra level-up moves and egg moves), places field
obstacles, item balls, berry soil, cave entrances, new buildings and new maps (sea route,
seafloor, caves, Safari Zone, Day Care, Contest Hall, Dept. Store, Battle Tower, Secret Base,
Sky Spire), and lists fishing and surfing tables. The game merges this file in DB._apply_features.

Run from the repo root after editing data or this file: python3 tools/build_features.py
"""
import json
import os
import random
import sys
from collections import deque

sys.path.insert(0, os.path.dirname(__file__))
import features_data as FD  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), '..')


def load(name):
    with open(os.path.join(ROOT, 'data', name + '.json')) as f:
        return json.load(f)


MAPS = load('maps')
SPECIES = load('species')
MOVES = load('moves')
ITEMS = load('items')
MISC = load('misc')
STORY = load('story')
ROUTE_LEVELS = MISC['routeLevels']
RNG = random.Random(3)

WALKABLE = set('.,=Fhlm:ju_eacdys')
# Tiles the player can cross with field moves (for reachability checks).
FIELD = set('TRB~DW')
DX = [(0, -1), (0, 1), (-1, 0), (1, 0)]
LEGENDARIES = [k for k, v in SPECIES.items() if v.get('rarity') == 'legendary']

OUT = {
    'version': 1, 'moves': {}, 'movePatches': FD.MOVE_PATCHES, 'abilities': {}, 'items': {},
    'species': {}, 'maps': {}, 'mapPatches': {}, 'tms': FD.TMS, 'hms': FD.HMS, 'hmBadges': FD.HM_BADGES,
    'tutors': [], 'flyPoints': {}, 'decorations': {}, 'shops': {}, 'contest': {}, 'tower': {},
}

# ---------- moves, abilities, items ----------
for m in FD.NEW_MOVES:
    assert m['id'] not in MOVES, m['id']
    if m['id'] in FD.SOUND:
        m['sound'] = True
    OUT['moves'][m['id']] = m
ALL_MOVES = dict(MOVES)
ALL_MOVES.update(OUT['moves'])
for mid in FD.SOUND:
    if mid in MOVES:
        OUT['movePatches'].setdefault(mid, {})['sound'] = True
for k, (name, desc) in FD.NEW_ABILITIES.items():
    OUT['abilities'][k] = {'name': name, 'desc': desc}
for it in FD.all_items():
    OUT['items'][it['id']] = it
for i, mid in enumerate(FD.TMS):
    assert mid in ALL_MOVES, mid
    OUT['items']['tm%02d' % (i + 1)] = {
        'id': 'tm%02d' % (i + 1), 'name': 'TM%02d %s' % (i + 1, ALL_MOVES[mid]['name']), 'price': 3000,
        'effect': {'kind': 'tm', 'move': mid}, 'desc': 'Teaches %s. %s' % (ALL_MOVES[mid]['name'], ALL_MOVES[mid]['desc']),
        'pocket': 'tms'}
for i, mid in enumerate(FD.HMS):
    assert mid in ALL_MOVES, mid
    OUT['items']['hm%02d' % (i + 1)] = {
        'id': 'hm%02d' % (i + 1), 'name': 'HM%02d %s' % (i + 1, ALL_MOVES[mid]['name']), 'price': 0,
        'effect': {'kind': 'tm', 'move': mid, 'hm': True},
        'desc': 'Teaches %s. Usable outside battle with badge %d.' % (ALL_MOVES[mid]['name'], FD.HM_BADGES[mid]),
        'pocket': 'tms'}
# Existing items get a pocket.
for k, it in ITEMS.items():
    OUT['items'].setdefault(k, {})['pocket'] = 'balls' if it['effect']['kind'] == 'ball' else 'items'
ALL_ITEMS = dict(ITEMS)
for k, v in OUT['items'].items():
    ALL_ITEMS[k] = {**ALL_ITEMS.get(k, {}), **v}
TM_ID = {mid: 'tm%02d' % (i + 1) for i, mid in enumerate(FD.TMS)}
TM_ID.update({mid: 'hm%02d' % (i + 1) for i, mid in enumerate(FD.HMS)})


# ---------- species ----------
def bst(sp):
    return sum(sp['base'].values())


def base_form(sid):
    prev = {v['evolves']['into']: k for k, v in SPECIES.items() if v.get('evolves')}
    while sid in prev:
        sid = prev[sid]
    return sid


def is_final(sid):
    return not SPECIES[sid].get('evolves')


PATCH = {sid: {} for sid in SPECIES}

# Abilities: give every new ability to at least one species, mostly in the empty second slot.
ABILITY_FOR_TYPE = {
    'Normal': ['pickup', 'cuteCharm', 'oblivious', 'vitalSpirit', 'stickyHold', 'illuminate'],
    'Fire': ['flameBody', 'magmaArmor', 'whiteSmoke', 'drought'], 'Water': ['waterVeil', 'rainDish', 'suctionCups', 'damp'],
    'Grass': ['stench', 'leafGuard'], 'Electric': ['plus', 'minus', 'lightningRod'], 'Ice': ['oblivious', 'magmaArmor'],
    'Fighting': ['purePower', 'vitalSpirit'], 'Poison': ['stench', 'liquidOoze', 'stickyHold', 'immunity'],
    'Ground': ['sandVeil', 'arenaTrap'], 'Flying': ['cloudNine'], 'Psychic': ['trace', 'magnetPull', 'sereneGrace'],
    'Bug': ['speedBoost', 'shellArmor', 'colorChange'], 'Rock': ['sandStream', 'magnetPull'],
    'Ghost': ['cursedBody'], 'Dragon': ['roughSkin', 'marvelScale'], 'Dark': ['shadowTag', 'roughSkin'],
    'Steel': ['magnetPull', 'whiteSmoke', 'hyperCutter'],
}
SPECIAL_ABILITIES = {
    'thalassor': ['drizzle'], 'terrasolis': ['drought'], 'zenithar': ['airLock'],
}
singles = [k for k, v in SPECIES.items() if len(v['abilities']) == 1 and k not in LEGENDARIES]
singles.sort(key=lambda k: SPECIES[k]['dex'])
for sid, abil in SPECIAL_ABILITIES.items():
    PATCH[sid]['abilities'] = abil
need = [a for a in FD.NEW_ABILITIES if a not in ('drizzle', 'drought', 'airLock')]
# Hand-picked ones first (they shape a species): Wonder Guard on the weakest Bug/Ghost, Truant on
# the strongest Normal, Huge Power on the weakest-attack Normal/Water.
weak_bug = min((k for k, v in SPECIES.items() if set(v['types']) & {'Bug', 'Ghost'} and is_final(k)
                and k not in LEGENDARIES), key=lambda k: bst(SPECIES[k]))
strong_normal = max((k for k, v in SPECIES.items() if 'Normal' in v['types'] and k not in LEGENDARIES),
                    key=lambda k: bst(SPECIES[k]))
low_atk = min((k for k, v in SPECIES.items() if set(v['types']) & {'Water', 'Normal'} and is_final(k)
               and k not in (strong_normal,)), key=lambda k: SPECIES[k]['base']['atk'])
for sid, abil in [(weak_bug, 'wonderGuard'), (strong_normal, 'truant'), (low_atk, 'hugePower')]:
    PATCH[sid]['abilities'] = [abil]
    need.remove(abil)
assigned = {weak_bug, strong_normal, low_atk}


def give_second(sid, abil):
    cur = PATCH[sid].get('abilities') or list(SPECIES[sid]['abilities'])
    if abil in cur:
        return
    PATCH[sid]['abilities'] = [cur[0], abil]


def evo_line(sid):
    line = [base_form(sid)]
    while SPECIES[line[-1]].get('evolves'):
        line.append(SPECIES[line[-1]]['evolves']['into'])
    return line


for abil in need:
    want_types = [t for t, lst in ABILITY_FOR_TYPE.items() if abil in lst] or ['Normal']
    pick = None
    for pool in (singles, [k for k in SPECIES if k not in LEGENDARIES]):
        for sid in pool:
            if sid in assigned or not set(SPECIES[sid]['types']) & set(want_types):
                continue
            pick = sid
            break
        if pick:
            break
    if pick is None:
        pick = next(s for s in singles if s not in assigned)
    for s in evo_line(pick):
        give_second(s, abil)
        assigned.add(s)
# Forecast has no fitting creature; give it to the weather-themed Normal one if there is one.
OUT['abilities'].pop('leafGuard', None)
OUT['abilities'].pop('cursedBody', None)

# Evolution methods: stones, friendship and trade (Gen 3 style).
STONE_FOR_TYPE = {'Fire': 'fireStone', 'Water': 'waterStone', 'Electric': 'thunderStone', 'Grass': 'leafStone'}
starters = set()
for s in MISC['starters']:
    starters.update(evo_line(s))
gym_mons = set()
for m in MAPS.values():
    for t in m.get('trainers', []):
        for e in t['party']:
            gym_mons.add(e[0])
two_stage = []
for k, v in SPECIES.items():
    e = v.get('evolves')
    if not e or k in starters:
        continue
    into = e['into']
    if SPECIES[into].get('evolves'):
        continue
    if base_form(k) != k and len(evo_line(k)) > 2:
        continue
    two_stage.append(k)
two_stage.sort(key=lambda k: SPECIES[k]['dex'])
used = set()
evo_changes = []


def set_evo(sid, method, **kw):
    e = dict(SPECIES[sid]['evolves'])
    e.update({'method': method, **kw})
    PATCH[sid]['evolves'] = e
    used.add(sid)
    evo_changes.append((sid, e['into'], method, kw))


for t, stone in STONE_FOR_TYPE.items():
    for sid in two_stage:
        if sid in used or t not in SPECIES[SPECIES[sid]['evolves']['into']]['types']:
            continue
        if SPECIES[sid]['evolves']['level'] < 24:
            continue
        set_evo(sid, 'stone', item=stone)
        break
for stone, types in [('moonStone', ['Psychic', 'Normal', 'Ghost']), ('sunStone', ['Grass', 'Fire', 'Bug'])]:
    for sid in two_stage:
        into = SPECIES[sid]['evolves']['into']
        if sid in used or not set(SPECIES[into]['types']) & set(types) or SPECIES[sid]['evolves']['level'] < 24:
            continue
        set_evo(sid, 'stone', item=stone)
        break
# Friendship: low-level evolutions of cute Normal/Psychic/Fairy-like creatures.
fr = 0
for sid in two_stage:
    if fr >= 3 or sid in used:
        continue
    if set(SPECIES[sid]['types']) & {'Normal', 'Psychic', 'Electric'} and SPECIES[sid]['evolves']['level'] <= 30:
        set_evo(sid, 'friendship')
        fr += 1
# Trade: the strongest-feeling Fighting/Rock/Ghost/Psychic/Steel middle stages.
tr = 0
mids = [k for k, v in SPECIES.items() if v.get('evolves') and base_form(k) != k and k not in starters]
mids.sort(key=lambda k: SPECIES[k]['dex'])
for sid in mids:
    if tr >= 4 or sid in used:
        continue
    if set(SPECIES[sid]['types']) & {'Fighting', 'Rock', 'Ghost', 'Psychic', 'Steel'} and SPECIES[sid]['evolves']['level'] >= 30:
        set_evo(sid, 'trade')
        tr += 1

# Egg groups.
BODY_GROUP = {'quad': 'Field', 'bug': 'Bug', 'blob': 'Amorphous', 'bird': 'Flying', 'biped': 'Human-Like',
              'rock': 'Mineral', 'ghost': 'Amorphous', 'fish': 'Water 2', 'serpent': 'Dragon'}
TYPE_GROUP = {'Water': 'Water 1', 'Grass': 'Grass', 'Dragon': 'Dragon', 'Bug': 'Bug', 'Flying': 'Flying',
              'Fighting': 'Human-Like', 'Rock': 'Mineral', 'Steel': 'Mineral', 'Ghost': 'Amorphous',
              'Poison': 'Amorphous', 'Ice': 'Field', 'Fire': 'Field', 'Electric': 'Fairy', 'Normal': 'Field',
              'Psychic': 'Fairy', 'Ground': 'Field', 'Dark': 'Field'}
for k, v in SPECIES.items():
    if k in LEGENDARIES:
        PATCH[k]['eggGroups'] = ['Undiscovered']
        continue
    g1 = BODY_GROUP[v['sprite']['body']]
    if g1 == 'Dragon' and 'Dragon' not in v['types']:
        g1 = 'Water 1' if 'Water' in v['types'] else 'Field'
    g2 = TYPE_GROUP[v['types'][0]]
    PATCH[k]['eggGroups'] = sorted({g1, g2})
    PATCH[k]['friendship'] = 35 if k in starters and False else 70
    PATCH[k]['eggCycles'] = 20 if bst(v) < 400 else (30 if bst(v) < 500 else 40)


# TM / HM / tutor compatibility.
def compatible(sid, mid):
    sp = SPECIES[sid]
    types = set(sp['types'])
    b = sp['base']
    mvt = ALL_MOVES[mid]['type']
    body = sp['sprite']['body']
    feats = set(sp['sprite'].get('features', []))
    physical = b['atk'] >= b['spa']
    fully = is_final(sid)
    universal = {'toxic', 'hiddenPower', 'protect', 'frustration', 'return', 'doubleTeam', 'facade', 'secretPower',
                 'rest', 'endure', 'sunnyDay', 'rainDance'}
    if mid in universal:
        return True
    if mid == 'attract':
        return sp['genderRatio'] >= 0
    if mid == 'hyperBeam':
        return fully and bst(sp) >= 420
    if mid == 'thief':
        return body not in ('rock',) or 'Dark' in types
    if mid == 'cut':
        return bool(types & {'Grass', 'Bug', 'Normal', 'Dark', 'Steel', 'Ground', 'Dragon'}) or 'spikes' in feats
    if mid == 'fly':
        return 'Flying' in types or ('wings' in feats and body in ('bird', 'serpent'))
    if mid in ('surf', 'dive', 'waterfall'):
        if 'Water' in types:
            return mid != 'waterfall' or b['atk'] >= 50
        return mid == 'surf' and (body in ('serpent',) and 'Dragon' in types or (b['hp'] >= 90 and body == 'quad'))
    if mid == 'strength':
        return physical and b['atk'] >= 60 and body not in ('bird', 'bug', 'fish', 'ghost')
    if mid == 'rockSmash':
        return b['atk'] >= 55 and body in ('quad', 'biped', 'rock', 'serpent') or bool(types & {'Fighting', 'Rock', 'Ground'})
    if mid == 'flash':
        return bool(types & {'Electric', 'Psychic', 'Fire'}) or 'cheeks' in feats
    if mvt in types:
        return True
    coverage = {
        'iceBeam': {'Water', 'Ice'}, 'blizzard': {'Water', 'Ice'}, 'hail': {'Water', 'Ice'},
        'thunderbolt': {'Electric', 'Normal'} if b['spa'] >= 60 else {'Electric'}, 'thunder': {'Electric'},
        'shadowBall': {'Ghost', 'Psychic', 'Dark', 'Normal'}, 'psychic': {'Psychic', 'Ghost'},
        'earthquake': {'Ground', 'Rock', 'Steel', 'Fighting', 'Dragon'}, 'dig': {'Ground', 'Normal', 'Rock', 'Bug'},
        'brickBreak': {'Fighting', 'Normal', 'Rock', 'Ground', 'Steel', 'Dragon', 'Dark'},
        'aerialAce': {'Flying', 'Bug', 'Normal', 'Dark', 'Grass', 'Fighting', 'Steel'},
        'ironTail': {'Steel', 'Normal', 'Ground', 'Rock', 'Electric', 'Dragon', 'Dark'},
        'rockTomb': {'Rock', 'Ground', 'Steel', 'Fighting'}, 'sandstorm': {'Rock', 'Ground', 'Steel'},
        'flamethrower': {'Fire', 'Dragon'}, 'fireBlast': {'Fire', 'Dragon'}, 'overheat': {'Fire'},
        'sludgeBomb': {'Poison', 'Grass', 'Ghost'}, 'solarBeam': {'Grass', 'Fire'}, 'gigaDrain': {'Grass', 'Bug'},
        'bulletSeed': {'Grass'}, 'calmMind': {'Psychic', 'Ghost', 'Dark', 'Dragon'}, 'bulkUp': {'Fighting', 'Normal', 'Rock'},
        'dragonClaw': {'Dragon', 'Ground', 'Rock', 'Dark'}, 'waterPulse': {'Water', 'Ice'}, 'shockWave': {'Electric'},
        'steelWing': {'Steel', 'Flying'}, 'roar': {'Normal', 'Fire', 'Dark', 'Ground', 'Electric', 'Dragon'},
        'taunt': {'Dark', 'Fighting', 'Ghost', 'Psychic'}, 'torment': {'Dark', 'Ghost', 'Fighting'},
        'lightScreen': {'Psychic', 'Electric', 'Fairy'}, 'reflect': {'Psychic', 'Steel', 'Rock'},
        'safeguard': {'Psychic', 'Normal', 'Grass', 'Water'}, 'skillSwap': {'Psychic'}, 'focusPunch': {'Fighting'},
    }
    if mid in coverage and types & coverage[mid]:
        if mid in ('brickBreak', 'aerialAce', 'ironTail', 'rockTomb', 'dig', 'dragonClaw', 'focusPunch', 'bulkUp', 'earthquake'):
            return physical or 'Fighting' in types
        return True
    if mid == 'focusPunch':
        return body == 'biped' and physical
    return False


TUTOR_MOVES = [m for m, _ in FD.TUTORS]
TUTOR_RULE = {
    'megaPunch': lambda sp: sp['sprite']['body'] == 'biped', 'counter': lambda sp: sp['sprite']['body'] == 'biped',
    'seismicToss': lambda sp: sp['sprite']['body'] == 'biped', 'doubleEdge': lambda sp: sp['sprite']['body'] in ('quad', 'serpent', 'rock'),
    'bodySlam': lambda sp: sp['sprite']['body'] in ('quad', 'biped', 'blob'),
    'thunderWave': lambda sp: bool(set(sp['types']) & {'Electric', 'Normal', 'Psychic', 'Dragon'}),
    'rockSlide': lambda sp: bool(set(sp['types']) & {'Rock', 'Ground', 'Steel', 'Fighting'}) or sp['sprite']['body'] == 'rock',
    'explosion': lambda sp: sp['sprite']['body'] in ('rock', 'blob') or 'Rock' in sp['types'],
    'substitute': lambda sp: True, 'swordsDance': lambda sp: sp['base']['atk'] >= 70 and sp['sprite']['body'] in ('quad', 'biped', 'bug'),
    'metronome': lambda sp: sp['sprite']['body'] in ('biped', 'blob'),
    'dreamEater': lambda sp: bool(set(sp['types']) & {'Psychic', 'Ghost', 'Dark'}),
}
for k, sp in SPECIES.items():
    PATCH[k]['tms'] = sorted(TM_ID[mid] for mid in FD.TMS + FD.HMS if compatible(k, mid))
    PATCH[k]['tutor'] = [mid for mid in TUTOR_MOVES if TUTOR_RULE[mid](sp)]
# Every species gets at least one HM so co-op parties of three aren't stuck.
for k in SPECIES:
    if not any(t.startswith('hm') for t in PATCH[k]['tms']):
        PATCH[k]['tms'].append('hm06' if SPECIES[k]['base']['atk'] >= SPECIES[k]['base']['spa'] else 'hm05')
        PATCH[k]['tms'].sort()

# New level-up moves (so the new moves appear in the wild) and egg moves.
LEARNABLE_NEW = [m for m in OUT['moves'].values() if m['id'] not in
                 set(FD.TMS + FD.HMS + ['blastBurn', 'hydroCannon', 'frenzyPlant', 'psychoBoost', 'sacredFire',
                                        'metronome', 'explosion', 'counter', 'megaPunch', 'dreamEater', 'substitute'])]
by_type = {}
for m in LEARNABLE_NEW:
    by_type.setdefault(m['type'], []).append(m['id'])
for k, sp in sorted(SPECIES.items(), key=lambda kv: kv[1]['dex']):
    learn = [list(e) for e in sp['learnset']]
    known = {e[1] for e in learn}
    pool = []
    for t in sp['types']:
        pool += by_type.get(t, [])
    if 'Normal' not in sp['types']:
        pool += [m for m in by_type.get('Normal', []) if ALL_MOVES[m]['power'] == 0][:6]
    pool = [m for m in pool if m not in known]
    r = random.Random(sp['dex'])
    r.shuffle(pool)
    adds = pool[:2]
    top = max(e[0] for e in learn)
    for i, mid in enumerate(adds):
        lvl = min(60, max(5, top + 4 + 6 * i if ALL_MOVES[mid]['power'] >= 80 else 8 + sp['dex'] % 20 + 7 * i))
        learn.append([lvl, mid])
    learn.sort(key=lambda e: e[0])
    PATCH[k]['learnset'] = learn
    eggs = [m for m in pool[2:] if m not in known][:3]
    PATCH[k]['eggMoves'] = eggs
# The starters' finals learn their ultimate moves (Emerald teaches them by tutor).
for s in MISC['starters']:
    fin = evo_line(s)[-1]
    t = SPECIES[fin]['types'][0]
    ult = {'Fire': 'blastBurn', 'Water': 'hydroCannon', 'Grass': 'frenzyPlant'}.get(t)
    if ult:
        PATCH[fin]['learnset'] = sorted(PATCH[fin]['learnset'] + [[55, ult]], key=lambda e: e[0])

# Wild held items.
HELD_BY_TYPE = {'Water': ['mysticWater', 'pearl', 'heartScale'], 'Fire': ['charcoal'], 'Grass': ['miracleSeed', 'oranBerry'],
                'Electric': ['magnet'], 'Ice': ['neverMeltIce'], 'Fighting': ['blackBelt'], 'Poison': ['poisonBarb'],
                'Ground': ['softSand'], 'Flying': ['sharpBeak'], 'Psychic': ['twistedSpoon'], 'Bug': ['silverPowder'],
                'Rock': ['hardStone', 'stardust'], 'Ghost': ['spellTag'], 'Dragon': ['dragonFang', 'dragonScale'],
                'Dark': ['blackGlasses'], 'Steel': ['metalCoat'], 'Normal': ['silkScarf', 'oranBerry']}
for k, sp in SPECIES.items():
    if k in LEGENDARIES:
        continue
    t = sp['types'][-1]
    opts = HELD_BY_TYPE[t]
    berry = ['oranBerry', 'pechaBerry', 'cheriBerry', 'chestoBerry', 'rawstBerry', 'aspearBerry', 'persimBerry',
             'sitrusBerry', 'lumBerry'][sp['dex'] % 9]
    PATCH[k]['heldItems'] = [[berry, 50], [opts[sp['dex'] % len(opts)], 5]]

for k in PATCH:
    if PATCH[k]:
        OUT['species'][k] = PATCH[k]


# ---------- maps ----------
def grid(m):
    return [list(r) for r in m['tiles']]


def tile(g, x, y):
    if y < 0 or y >= len(g) or x < 0 or x >= len(g[0]):
        return '#'
    return g[y][x]


def occupied(mid):
    m = MAPS.get(mid) or OUT['maps'].get(mid)
    taken = set()
    for a in m.get('npcs', []) + m.get('trainers', []):
        taken.add((a['x'], a['y']))
    for a in STORY['npcs'].get(mid, []) + STORY['trainers'].get(mid, []):
        taken.add((a['x'], a['y']))
    for key in list(m.get('signs', {})) + list(m.get('doors', {})) + list(m.get('warps', {})):
        x, y = map(int, key.split(','))
        taken.add((x, y))
    p = OUT['mapPatches'].get(mid, {})
    for a in p.get('npcs', []) + p.get('statics', []) + p.get('trainers', []):
        taken.add((a['x'], a['y']))
    for it in p.get('items', []):
        taken.add((it['x'], it['y']))
    for key in list(p.get('warps', {})) + p.get('soil', []):
        x, y = map(int, key.split(','))
        taken.add((x, y))
    return taken


def entries(mid, g):
    m = MAPS.get(mid) or OUT['maps'][mid]
    h, w = len(g), len(g[0])
    out = []
    conns = dict(m.get('connections', {}))
    conns.update(OUT['mapPatches'].get(mid, {}).get('connections', {}))
    for side in conns:
        for i in range(max(w, h)):
            p = {'up': (i, 0), 'down': (i, h - 1), 'left': (0, i), 'right': (w - 1, i)}[side]
            if p[0] < w and p[1] < h and tile(g, *p) in WALKABLE:
                out.append(p)
    return out


def reach(g, starts, blocked=frozenset(), passable=WALKABLE | FIELD):
    seen = set()
    q = deque()
    for s in starts:
        if s not in seen:
            seen.add(s)
            q.append(s)
    while q:
        x, y = q.popleft()
        for dx, dy in DX:
            nx, ny = x + dx, y + dy
            if tile(g, nx, ny) == 'v' and dy == 1:
                ny += 1
            if (nx, ny) in seen or (nx, ny) in blocked or tile(g, nx, ny) not in passable:
                continue
            seen.add((nx, ny))
            q.append((nx, ny))
    return seen


def patch(mid):
    return OUT['mapPatches'].setdefault(mid, {})


def write_tiles(mid, g):
    patch(mid)['tiles'] = [''.join(r) for r in g]


def get_grid(mid):
    p = OUT['mapPatches'].get(mid, {})
    if 'tiles' in p:
        return [list(r) for r in p['tiles']]
    if mid in OUT['maps']:
        return grid(OUT['maps'][mid])
    return grid(MAPS[mid])


def check_still_reachable(mid, before, after, allowed_lost):
    starts = entries(mid, after) or [next(iter(before))]
    r = reach(after, starts)
    lost = {p for p in before if tile(after, *p) in WALKABLE} - r - allowed_lost
    return not lost


def baseline(mid):
    g = get_grid(mid)
    st = entries(mid, g)
    if not st:
        return g, set()
    return g, reach(g, st)


def route_no(mid):
    return int(mid.replace('route', '')) if mid.startswith('route') else 0


# --- obstacle pockets with items ---
def place_pocket(mid, obstacle, item_id, count=1):
    """Turns a dead-end walkable tile into a pocket closed by `obstacle`, with an item inside."""
    g, before = baseline(mid)
    taken = occupied(mid)
    h, w = len(g), len(g[0])
    cands = []
    for y in range(2, h - 2):
        for x in range(2, w - 2):
            if g[y][x] not in '.F' or (x, y) in taken:
                continue
            if any(abs(x - tx) + abs(y - ty) < 3 for tx, ty in taken):
                continue
            walls = sum(1 for dx in (-1, 0, 1) for dy in (-1, 0, 1) if (dx or dy) and tile(g, x + dx, y + dy) == '#')
            cands.append((-walls, RNG.random(), x, y))
    cands.sort()
    for _, _, x, y in cands[:60]:
        for dx, dy in DX:
            gx, gy = x + dx, y + dy  # the obstacle tile
            ox, oy = gx + dx, gy + dy  # where the player stands to clear it
            if tile(g, gx, gy) not in '.F' or tile(g, ox, oy) not in '.F=' or (gx, gy) in taken:
                continue
            ng = [r[:] for r in g]
            ng[gy][gx] = obstacle
            for ddx in (-1, 0, 1):
                for ddy in (-1, 0, 1):
                    tx, ty = x + ddx, y + ddy
                    if (tx, ty) in ((x, y), (gx, gy)):
                        continue
                    if 0 < tx < w - 1 and 0 < ty < h - 1 and ng[ty][tx] in '.F,':
                        ng[ty][tx] = '#'
            if obstacle == 'B':
                # A boulder needs a free tile behind it to be pushed into: push it into the pocket.
                pass
            lost = {(x, y)} | {(x + a, y + b) for a in (-1, 0, 1) for b in (-1, 0, 1)}
            if not check_still_reachable(mid, before, ng, lost):
                continue
            if (ox, oy) not in reach(ng, entries(mid, ng)):
                continue
            write_tiles(mid, ng)
            add_item(mid, x, y, item_id, count)
            return True
    print('warning: no pocket on', mid, file=sys.stderr)
    return False


ITEM_SEQ = [0]


def add_item(mid, x, y, item_id, count=1, hidden=False):
    assert item_id in ALL_ITEMS, item_id
    ITEM_SEQ[0] += 1
    patch(mid).setdefault('items', []).append(
        {'id': '%s_i%d' % (mid, ITEM_SEQ[0]), 'x': x, 'y': y, 'item': item_id, 'count': count, 'hidden': hidden})


def free_spot(mid, near_road=False, tiles='.F', avoid=3, rng=RNG):
    g = get_grid(mid)
    taken = occupied(mid)
    h, w = len(g), len(g[0])
    _, r = baseline(mid)
    opts = []
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            if g[y][x] not in tiles or (x, y) in taken or (r and (x, y) not in r):
                continue
            if any(abs(x - tx) + abs(y - ty) < avoid for tx, ty in taken):
                continue
            # Never wall off a corridor: every neighbour stays reachable without this tile.
            if near_road and not any(tile(g, x + dx, y + dy) == '=' for dx, dy in DX):
                continue
            if r and not check_still_reachable(mid, r, [row[:x] + ['#'] + row[x + 1:] if yy == y else row
                                                     for yy, row in enumerate(g)], {(x, y)}):
                continue
            opts.append((x, y))
    assert opts, 'no free spot on ' + mid
    return rng.choice(opts)


def face_road(g, x, y):
    for d, (dx, dy) in zip(['up', 'down', 'left', 'right'], DX):
        if tile(g, x + dx, y + dy) == '=':
            return d
    return 'down'


def add_npc(mid, palette, text, near_road=True, **extra):
    g = get_grid(mid)
    x, y = free_spot(mid, near_road=near_road)
    n = {'x': x, 'y': y, 'dir': face_road(g, x, y), 'palette': palette, 'text': text}
    n.update(extra)
    patch(mid).setdefault('npcs', []).append(n)
    return n


# --- new buildings in towns ---
def add_building(mid, interior_id, roof='q'):
    """Places a 4x3 building (roof, roof, wall+door) on open grass; returns the door position."""
    g, before = baseline(mid)
    taken = occupied(mid)
    h, w = len(g), len(g[0])
    cands = []
    for y in range(1, h - 4):
        for x in range(1, w - 4):
            ok = all(g[y + dy][x + dx] in '.F' for dx in range(4) for dy in range(3))
            if not ok or tile(g, x + 2, y + 3) not in '.F=':
                continue
            if any(x - 1 <= tx <= x + 4 and y - 1 <= ty <= y + 3 for tx, ty in taken):
                continue
            ng = [r[:] for r in g]
            for dx in range(4):
                ng[y][x + dx] = roof
                ng[y + 1][x + dx] = roof
                ng[y + 2][x + dx] = 'd' if dx == 2 else 'w'
            lost = {(x + dx, y + dy) for dx in range(4) for dy in range(3)}
            if not check_still_reachable(mid, before, ng, lost):
                continue
            score = abs(y + 3 - h * 0.75) + RNG.random()
            cands.append((score, x, y, ng))
    assert cands, 'no room for a building in ' + mid
    _, x, y, ng = min(cands, key=lambda c: c[0])
    write_tiles(mid, ng)
    dx, dy = x + 2, y + 2
    patch(mid).setdefault('warps', {})['%d,%d' % (dx, dy)] = {'map': interior_id, 'x': 7, 'y': 10, 'dir': 'up'}
    return dx, dy


def interior(id, name, rows, exit_to, exit_xy, npcs=(), theme='#e0d8c8', **extra):
    h = len(rows)
    w = len(rows[0])
    assert all(len(r) == w for r in rows), id
    ex = rows[-1].index('e')
    m = {'id': id, 'name': name, 'tiles': rows, 'connections': {}, 'indoor': True, 'theme': theme,
         'warps': {'%d,%d' % (ex, h - 1): {'map': exit_to, 'x': exit_xy[0], 'y': exit_xy[1] + 1, 'dir': 'down'}},
         'npcs': list(npcs)}
    m.update(extra)
    OUT['maps'][id] = m
    return m


ROOM = ['|||||||||||||||'] + ['|_____________|'] * 10 + ['|||||||e|||||||']


def building(town, id, name, npcs, rows=ROOM, **extra):
    door = add_building(town, id)
    return interior(id, name, rows, town, door, npcs, **extra)


def npc(x, y, palette, text, dir='down', **extra):
    d = {'x': x, 'y': y, 'dir': dir, 'palette': palette, 'text': text}
    d.update(extra)
    return d


# Day Care (Harrowfield): the lady takes creatures, the man outside hands over eggs.
building('harrowfield', 'daycare', 'Day Care', [
    npc(7, 4, 'old', ["I'm the Day Care Lady. We can raise creatures for you."], service='daycare'),
    npc(3, 6, 'girl', ['Two creatures of the same egg group may leave an egg if they get along.'])])
add_npc('harrowfield', 'gentleman', ['I\'m the Day Care Man.'], service='daycareMan')
# Contest Hall and Dept. Store (Lumenvale).
building('lumenvale', 'contesthall', 'Showcase Hall', [
    npc(5, 4, 'beauty', ['Welcome to the Showcase Hall!'], service='contest'),
    npc(10, 4, 'psychic', ['This is the Berry Blender. Shall I blend a berry into a Treat Block?'], service='blender'),
    npc(3, 7, 'girl', ['Feed creatures Treat Blocks to boost their Cool, Beauty, Cute, Smart or Tough condition.']),
    npc(11, 8, 'gentleman', ['Moves score more appeal in a contest of their own category.', 'Using the same move twice in a row bores the judge.'])])
building('lumenvale', 'deptstore', 'Lumenvale Dept. Store', [
    npc(3, 4, 'clerk', ['TM corner! Pick a technique.'], service='shop', shop='tms'),
    npc(7, 4, 'clerk', ['Battle goods and medicine.'], service='shop', shop='battle'),
    npc(11, 4, 'clerk', ['Decorations for your Secret Base!'], service='shop', shop='deco'),
    npc(7, 8, 'boy', ['Vitamins raise base stats. X items only last for one battle.'])])
# Battle Tower (Summit Crown, after becoming Champion).
building('summitcrown', 'battletower', 'Battle Tower', [
    npc(7, 4, 'nurse', ['Welcome to the Battle Tower!'], service='tower'),
    npc(11, 4, 'clerk', ['Exchange Battle Points for prizes!'], service='shop', shop='bp'),
    npc(3, 7, 'ace', ['Every seventh battle is against the Tower Tycoon.', 'Your creatures fight at level 50 here.'])])
# Safari Zone gate (Saltmarsh).
safari_door = add_building('saltmarsh', 'safarizone')
patch('saltmarsh')['warps']['%d,%d' % safari_door].update({'x': 19, 'y': 19, 'script': 'safari'})
# Secret Base interior (one base; it moves with you).
OUT['maps']['secretbase'] = {
    'id': 'secretbase', 'name': 'Secret Base', 'indoor': True, 'theme': '#c8b088', 'connections': {},
    'tiles': ['|||||||||||', '|____P____|', '|_________|', '|_________|', '|_________|', '|_________|', '|_________|',
              '|_________|', '|||||e|||||'],
    'warps': {'5,8': {'map': 'fernhollow', 'x': 0, 'y': 0, 'dir': 'down', 'script': 'baseExit'}}, 'npcs': [],
    'secretBase': True}

# ---------- route 13 (sea), seafloor, Sky Spire ----------
SEA = [
    '########################################',
    '#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##########',
    '#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#~~~~~~~~#',
    '#~~~~~~~~~~~~~DD~~~~~~~~~~~~~~#~~~qqq~~#',
    '#~~~~~..~~~~~~DD~~~~~~~~~~~~~~#~~~wdw~~#',
    '#~~~~~..~~~~~~~~~~~~~~~~~~~~~~#~~~...~~#',
    '#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#~~~~~~~~#',
    '#aaaaa~~~~~~~~~~~~~~~~~~~~~~~~#~~~~~~~~#',
    '#aaaaaa~~~~~~~~~~~~~~~~~~~~~~~##W######',
    '#aaaaaaa~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#',
    '==aaaaaa~~~~~~~~~~~~~DD~~~~~~~~~~~~~~~~#',
    '==aaaaaa~~~~~~~~~~~~~DD~~~~~~~~~~~~~~~~#',
    '#aaaaaa~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#',
    '#aaaaa~~~~~~~~~~..~~~~~~~~~~~~~~~~~~~~~#',
    '#aaaa~~~~~~~~~~~..~~~~~~~~~~~~~DD~~~~~~#',
    '#aaa~~~~~~~~~~~~~~~~~~~~~~~~~~~DD~~~~~~#',
    '#aa~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#',
    '#a~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#',
    '#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#',
    '########################################',
]
SEA[8] = SEA[8][:39] + '#'
assert all(len(r) == 40 for r in SEA), [len(r) for r in SEA]
water_sp = sorted([k for k, v in SPECIES.items() if 'Water' in v['types'] and k not in LEGENDARIES],
                  key=lambda k: bst(SPECIES[k]))
OUT['maps']['route13'] = {
    'id': 'route13', 'name': 'Route 13', 'route': 13, 'tiles': SEA, 'theme': '#d8d0c0',
    'connections': {'left': {'map': 'saltmarsh', 'offset': 0}},
    'warps': {'35,4': {'map': 'skyspire', 'x': 7, 'y': 14, 'dir': 'up'}},
    'encounters': [], 'trainers': [
        {'id': 'r13_t0', 'name': 'Swimmer Nerys', 'palette': 'swimmer', 'x': 4, 'y': 8, 'dir': 'right', 'sight': 3,
         'pay': 40, 'party': [[water_sp[-12], 36], [water_sp[-9], 37]], 'double': False,
         'intro': 'The sea is my training ground!', 'defeat': 'Washed out...', 'after': 'Deep water hides the way to the seafloor.'},
        {'id': 'r13_t1', 'name': 'Swimmer Cal', 'palette': 'swimmer', 'x': 3, 'y': 14, 'dir': 'up', 'sight': 3,
         'pay': 40, 'party': [[water_sp[-14], 37], [water_sp[-6], 38]], 'double': False,
         'intro': 'Race you to the waterfall!', 'defeat': 'You swim fast.', 'after': 'Waterfall can climb that cascade to the lagoon.'},
    ],
    'weather': 'rain',
}
# Saltmarsh opens its east edge onto the beach.
g = get_grid('saltmarsh')
g[10][25] = '='
g[11][25] = '='
write_tiles('saltmarsh', g)
patch('saltmarsh')['connections'] = {'right': {'map': 'route13', 'offset': 0}}

FLOOR = [list('x' * 40) for _ in range(20)]


def carve(x0, y0, x1, y1, ch='c'):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            FLOOR[y][x] = ch


carve(12, 2, 16, 9)
carve(11, 5, 19, 8, ',')
carve(13, 3, 16, 4)
carve(14, 9, 23, 11)
carve(18, 11, 28, 16)
carve(19, 12, 27, 15, ',')
carve(28, 13, 33, 16)
for (x, y) in [(14, 3), (15, 3), (14, 4), (15, 4), (21, 10), (22, 10), (21, 11), (22, 11), (31, 14), (32, 14), (31, 15), (32, 15)]:
    FLOOR[y][x] = 'D'
FLOOR[17][23] = 'y'
carve(23, 16, 23, 16)
FLOOR = [''.join(r) for r in FLOOR]
OUT['maps']['seafloor'] = {
    'id': 'seafloor', 'name': 'Seafloor', 'tiles': FLOOR, 'connections': {}, 'underwater': True, 'cave': True,
    'warps': {'23,17': {'map': 'seacavern', 'x': 7, 'y': 9, 'dir': 'up'}}, 'encounterRate': 10,
    'encounters': [{'species': s, 'min': 34, 'max': 40, 'weight': w} for s, w in zip(water_sp[-10:-4], [30, 20, 15, 15, 10, 10])],
}
OUT['maps']['seacavern'] = {
    'id': 'seacavern', 'name': 'Sea Cavern', 'cave': True, 'connections': {},
    'tiles': ['xxxxxxxxxxxxxxx', 'xxxxxcccccxxxxx', 'xxxxcccccccxxxx', 'xxxcccccccccxxx', 'xxccc~~~~~cccxx', 'xxccc~~~~~cccxx',
              'xxcccc~~~ccccxx', 'xxxcccccccccxxx', 'xxxxcccccccxxxx', 'xxxxxxcccxxxxxx', 'xxxxxxxyxxxxxxx'],
    'warps': {'7,10': {'map': 'seafloor', 'x': 23, 'y': 16, 'dir': 'down'}},
    'statics': [{'id': 'leg_thalassor', 'species': 'thalassor', 'level': 50, 'x': 7, 'y': 2, 'requires': 'champion',
                 'text': 'A deep rumble shakes the cavern...'}],
}
OUT['maps']['skyspire'] = {
    'id': 'skyspire', 'name': 'Sky Spire', 'indoor': True, 'theme': '#b8c0d0', 'connections': {},
    'tiles': ['|||||||||||||||', '|_____________|', '|______y______|', '|_____________|', '|o___________o|', '|_____________|',
              '|_____________|', '|o___________o|', '|_____________|', '|_____________|', '|o___________o|', '|_____________|',
              '|_____________|', '|_____________|', '|_____________|', '|||||||e|||||||'],
    'warps': {'7,15': {'map': 'route13', 'x': 35, 'y': 5, 'dir': 'down'},
              '7,2': {'map': 'skyspire2', 'x': 7, 'y': 7, 'dir': 'up'}},
    'trainers': [{'id': 'spire_t0', 'name': 'Ace Sora', 'palette': 'ace', 'x': 4, 'y': 6, 'dir': 'right', 'sight': 4,
                  'pay': 60, 'party': [['zarathorn', 48], ['plumehawk', 48]], 'double': False,
                  'intro': 'Only the strongest climb the Spire!', 'defeat': 'You may pass.', 'after': 'The sky dragon rests above.'}],
}
OUT['maps']['skyspire2'] = {
    'id': 'skyspire2', 'name': 'Sky Spire Summit', 'indoor': True, 'theme': '#d0d8f0', 'connections': {},
    'tiles': ['|||||||||||||||', '|_____________|', '|_____________|', '|_____________|', '|_____________|',
              '|_____________|', '|_____________|', '|______y______|', '|||||||||||||||'],
    'warps': {'7,7': {'map': 'skyspire', 'x': 7, 'y': 3, 'dir': 'down'}},
    'statics': [{'id': 'leg_zenithar', 'species': 'zenithar', 'level': 50, 'x': 7, 'y': 2, 'requires': 'champion',
                 'text': 'A great dragon coils at the top of the Spire!'}],
}
for k in ['zarathorn', 'plumehawk']:
    assert k in SPECIES, k

# ---------- caves ----------
GRANITE = [
    'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
    'xccccccccxxxxxxxxxxxxxcccccccx',
    'xcccccccxxxxxxxxxxxxxxcccccccx',
    'xcccccRcccccccccccxxxxccccyccx',
    'xxxccccccccccccccccccccccccccx',
    'xxxxxxxcccxxxxxxxxxxxxxccxxxxx',
    'xcccccxcccxxxxxxxxxxxxxBBxxxxx',
    'xcccccccccxxxxxcccccccccccccxx',
    'xccccccxxxxxxxxcccccccccccccxx',
    'xxccccxxxxxxxxxcccxxxxxxccccxx',
    'xxccccxxxxxxxxxcccxxxxxxccccxx',
    'xxccccccccccccccccxxxxxxccccxx',
    'xxxxxxxxxxxxcccxxxxxxxxxxRRxxx',
    'xxxxxxxxxxxxcccxxxxxxxxxccccxx',
    'xxxxxxxxxxxxcccxxxxxxxxxccccxx',
    'xxxxxxxxxxxxcccxxxxxxxxxxxxxxx',
    'xxxxxxxxxxxxcycxxxxxxxxxxxxxxx',
    'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
]
rock_sp = sorted([k for k, v in SPECIES.items() if set(v['types']) & {'Rock', 'Ground', 'Ghost', 'Dark', 'Steel'}
                  and v.get('area') is not None and k not in LEGENDARIES], key=lambda k: SPECIES[k]['area'])
OUT['maps']['granitecave'] = {
    'id': 'granitecave', 'name': 'Granite Cave', 'cave': True, 'dark': True, 'tiles': GRANITE, 'connections': {},
    'warps': {'26,3': {'map': 'granitecave_b1', 'x': 2, 'y': 2, 'dir': 'down'}}, 'encounterRate': 10,
    'encounters': [{'species': s, 'min': 11, 'max': 15, 'weight': w} for s, w in zip(rock_sp[:5], [30, 25, 20, 15, 10])],
    'items': [],
}
OUT['maps']['granitecave_b1'] = {
    'id': 'granitecave_b1', 'name': 'Granite Cave B1F', 'cave': True, 'dark': True, 'connections': {},
    'tiles': ['xxxxxxxxxxxxxxxxxxxx', 'xycccxxxxxxxxxxxxxxx', 'xcccccccxxxxxccccccx', 'xcc,,,cccccccccccccx',
              'xcc,,,cccxxxxccccccx', 'xccccccccxxxxccccccx', 'xxxxxxcccxxxxxxccxxx', 'xxxxxxcccccccccccxxx',
              'xxxxxxxxxxxxxxxxxxxx'],
    'warps': {'1,1': {'map': 'granitecave', 'x': 26, 'y': 4, 'dir': 'down'}}, 'encounterRate': 10,
    'encounters': [{'species': s, 'min': 30, 'max': 36, 'weight': w} for s, w in zip(rock_sp[5:10], [30, 25, 20, 15, 10])],
    'statics': [{'id': 'leg_orrerion', 'species': 'orrerion', 'level': 50, 'x': 16, 'y': 3, 'requires': 'champion',
                 'text': 'The stars painted on the walls begin to turn...'}],
}
OUT['maps']['desertruins'] = {
    'id': 'desertruins', 'name': 'Desert Ruins', 'cave': True, 'connections': {},
    'tiles': ['xxxxxxxxxxxxxxx', 'xxxxxcccccxxxxx', 'xxxxcccccccxxxx', 'xxxcccccccccxxx', 'xxcccaaaaacccxx', 'xxcccaaaaacccxx',
              'xxcccaaaaacccxx', 'xxxcccccccccxxx', 'xxxxxxxRxxxxxxx', 'xxxxxxxcxxxxxxx', 'xxxxxxxyxxxxxxx'],
    'warps': {}, 'weather': 'sand',
    'statics': [{'id': 'leg_terrasolis', 'species': 'terrasolis', 'level': 50, 'x': 7, 'y': 2, 'requires': 'champion',
                 'text': 'The ground glows red-hot...'}],
}


def cave_mouth(mid, dest, dest_xy, need=None):
    """Opens a cave mouth 'y' in a tree wall with walkable ground below; returns its position."""
    g, before = baseline(mid)
    taken = occupied(mid)
    h, w = len(g), len(g[0])
    cands = []
    for y in range(2, h - 2):
        for x in range(2, w - 2):
            if g[y][x] != '#' or g[y - 1][x] != '#' or g[y + 1][x] not in '.F' or (x, y + 1) in taken:
                continue
            if need and not any(tile(g, a, b) in '.F=' for a, b in ((x, y + 2), (x - 1, y + 1), (x + 1, y + 1))):
                continue
            cands.append((RNG.random(), x, y))
    assert cands, 'no cave mouth on ' + mid
    _, x, y = min(cands)
    g[y][x] = 'y'
    if need:
        g[y + 1][x] = need
    write_tiles(mid, g)
    patch(mid).setdefault('warps', {})['%d,%d' % (x, y)] = {'map': dest, 'x': dest_xy[0], 'y': dest_xy[1], 'dir': 'up'}
    return x, y


gx, gy = cave_mouth('route3', 'granitecave', (13, 15))
OUT['maps']['granitecave']['warps']['13,16'] = {'map': 'route3', 'x': gx, 'y': gy + 1, 'dir': 'down'}
dx_, dy_ = cave_mouth('route5', 'desertruins', (7, 9))
OUT['maps']['desertruins']['warps']['7,10'] = {'map': 'route5', 'x': dx_, 'y': dy_ + 1, 'dir': 'down'}
# The Starchime waits in the League's champion room once you are Champion.
patch('league')['statics'] = [{'id': 'leg_starchime', 'species': 'starchime', 'level': 50, 'x': 7, 'y': 1,
                               'requires': 'champion', 'text': 'The Starchime rings softly...'}]
# Legendaries no longer appear in Victory Road's grass; Solvara and Velunox roam instead.
patch('route12')['encounters'] = [e for e in MAPS['route12']['encounters'] if e['species'] not in LEGENDARIES]
OUT['roamers'] = ['solvara', 'velunox']

# ---------- Safari Zone ----------
SAFARI = [
    '########################################',
    '#,,,,,,,,,,......####......,,,,,,,,,,,,#',
    '#,,,,,,,,,,......####......,,,,,,,,,,,,#',
    '#,,,,,,,,,,..............~~,,,,,,,,,,,,#',
    '#,,,,..........~~~~~~~...~~......,,,,,,#',
    '#.......F......~~~~~~~...........,,,,,,#',
    '#..............~~~~~~~.....F.....,,,,,,#',
    '#....##........~~~~~~~...........,,,,,,#',
    '#....##.......................####.....#',
    '#.........,,,,,,,,,.......,,,,####.....#',
    '#.........,,,,,,,,,.......,,,,.........#',
    '#...F.....,,,,,,,,,.......,,,,.........#',
    '#.........,,,,,,,,,............F.......#',
    '#.......................,,,,,,,,,,.....#',
    '#..####...........F.....,,,,,,,,,,.....#',
    '#..####.................,,,,,,,,,,.....#',
    '#,,,,,,,,..........==...,,,,,,,,,,.....#',
    '#,,,,,,,,..........==..................#',
    '#,,,,,,,,..........==.........~~~~~....#',
    '#..................==.........~~~~~....#',
    '###################e####################',
]
assert all(len(r) == 40 for r in SAFARI)
safari_pool = [k for k, v in SPECIES.items() if v.get('rarity') in ('rare', 'uncommon') and k not in LEGENDARIES
               and v.get('area') is not None]
safari_pool.sort(key=lambda k: (SPECIES[k]['rarity'] != 'rare', SPECIES[k]['dex']))
safari_pool = safari_pool[:12]
OUT['maps']['safarizone'] = {
    'id': 'safarizone', 'name': 'Safari Zone', 'tiles': SAFARI, 'connections': {}, 'safari': True,
    'warps': {'19,20': {'map': 'saltmarsh', 'x': safari_door[0], 'y': safari_door[1] + 1, 'dir': 'down', 'script': 'safariExit'}},
    'encounterRate': 25,
    'encounters': [{'species': s, 'min': 25, 'max': 32, 'weight': 30 if i < 4 else (15 if i < 8 else 5)}
                   for i, s in enumerate(safari_pool)],
}

# ---------- items, pockets, berries, hidden items, obstacles on routes ----------
GYM_TMS = ['rockTomb', 'bulkUp', 'shockWave', 'overheat', 'facade', 'aerialAce', 'calmMind', 'waterPulse']
SHOP_TMS = ['toxic', 'hail', 'sunnyDay', 'rainDance', 'sandstorm', 'protect', 'lightScreen', 'reflect', 'safeguard', 'rest']
GIFT_TMS = ['secretPower', 'return', 'frustration']
BP_TMS = ['hyperBeam', 'earthquake', 'focusPunch', 'skillSwap']
rest = [m for m in FD.TMS if m not in GYM_TMS + SHOP_TMS + GIFT_TMS + BP_TMS]
power = lambda m: ALL_MOVES[m]['power']
rest.sort(key=power)
OUT['gymTms'] = {str(i + 1): TM_ID[m] for i, m in enumerate(GYM_TMS)}
VISIBLE = {
    1: ['potion', 'orb', 'antidote'], 2: ['potion', 'repel', 'oranBerry'], 3: ['superPotion', 'escapeRope', 'xAttack'],
    4: ['greatOrb', 'ether', 'fireStone'], 5: ['thunderStone', 'nestOrb', 'rareCandy'], 6: ['hyperPotion', 'netOrb', 'leafStone'],
    7: ['waterStone', 'ppUp', 'fullHeal'], 8: ['moonStone', 'maxEther', 'timerOrb'], 9: ['sunStone', 'rareCandy', 'revive'],
    10: ['ultraOrb', 'elixir', 'luckyEgg'], 11: ['maxPotion', 'ppUp', 'repeatOrb'], 12: ['fullRestore', 'maxElixir', 'rareCandy'],
}
HIDDEN = ['heartScale', 'pearl', 'stardust', 'nugget', 'bigPearl', 'starPiece', 'heartScale', 'rareCandy']
POCKET_ITEMS = {3: 'quickClaw', 4: 'expShare', 5: 'kingsRock', 6: 'scopeLens', 7: 'focusBand', 8: 'leftovers',
                9: 'shellBell', 10: 'choiceBand', 11: 'brightPowder', 12: 'amuletCoin'}
OBSTACLE = {3: 'T', 4: 'T', 5: 'R', 6: 'R', 7: 'T', 8: 'R', 9: 'T', 10: 'R', 11: 'T', 12: 'R'}
tm_iter = iter(rest)
for r in range(1, 13):
    mid = 'route%d' % r
    for it in VISIBLE[r]:
        x, y = free_spot(mid)
        add_item(mid, x, y, it)
    for _ in range(2 if r > 2 else 1):
        tmid = next(tm_iter, None)
        if tmid:
            x, y = free_spot(mid)
            add_item(mid, x, y, TM_ID[tmid])
    for i in range(2):
        x, y = free_spot(mid, tiles='.F')
        add_item(mid, x, y, HIDDEN[(r + i) % len(HIDDEN)], hidden=True)
    if r in OBSTACLE:
        pocket_tm = next(tm_iter, None)
        place_pocket(mid, OBSTACLE[r], TM_ID[pocket_tm] if pocket_tm else POCKET_ITEMS[r])
        if pocket_tm and r in POCKET_ITEMS:
            place_pocket(mid, OBSTACLE[r], POCKET_ITEMS[r])
leftover_tms = list(tm_iter)
for i, tmid in enumerate(leftover_tms):
    mid = ['route13', 'safarizone', 'granitecave_b1', 'route12'][i % 4]
    x, y = free_spot(mid, tiles='.Fac,')
    add_item(mid, x, y, TM_ID[tmid])
# Caves and sea items.
for mid, its in [('granitecave', ['hpUp', 'escapeRope', 'hardStone']), ('granitecave_b1', ['protein', 'everstone']),
                 ('route13', ['bigPearl', 'diveOrb', 'deepSeaTooth']), ('seafloor', ['heartScale', 'diveOrb', 'pearl']),
                 ('safarizone', ['calcium', 'iron', 'zinc', 'carbos']), ('skyspire', ['dragonScale', 'maxRevive'])]:
    for it in its:
        x, y = free_spot(mid, tiles='.Fac,_')
        add_item(mid, x, y, it)
x, y = free_spot('route13', tiles='.')
add_item('route13', 35, 5, 'masterOrb') if False else None

# Berry soil: a row of soft soil beside the road on several routes, some of it already growing.
BERRY_ROUTES = {1: ['oranBerry', 'pechaBerry'], 2: ['cheriBerry', 'oranBerry'], 3: ['chestoBerry', 'rawstBerry'],
                4: ['aspearBerry', 'leppaBerry'], 6: ['sitrusBerry', 'persimBerry'], 8: ['figyBerry', 'wikiBerry'],
                10: ['magoBerry', 'aguavBerry', 'iapapaBerry'], 11: ['lumBerry', 'sitrusBerry']}
for r, berries in BERRY_ROUTES.items():
    mid = 'route%d' % r
    g, before = baseline(mid)
    taken = occupied(mid)
    best = None
    for y in range(2, len(g) - 2):
        for x in range(2, len(g[0]) - 2 - len(berries)):
            span = [(x + i, y) for i in range(len(berries))]
            if not all(g[yy][xx] in '.F' and (xx, yy) not in taken for xx, yy in span):
                continue
            if not any(tile(g, xx, yy + 1) == '=' or tile(g, xx, yy - 1) == '=' for xx, yy in span):
                continue
            if any(abs(xx - tx) + abs(yy - ty) < 2 for xx, yy in span for tx, ty in taken):
                continue
            best = span
            break
        if best:
            break
    if not best:
        print('warning: no soil on', mid, file=sys.stderr)
        continue
    for (xx, yy), b in zip(best, berries):
        g[yy][xx] = 's'
    write_tiles(mid, g)
    p = patch(mid)
    p['soil'] = ['%d,%d' % s for s in best]
    p['berries'] = {'%d,%d' % s: b for s, b in zip(best, berries)}

# Secret Base spots (a tree with vines) on three routes.
for mid in ['route3', 'route7', 'route11']:
    g, before = baseline(mid)
    taken = occupied(mid)
    for y in range(2, len(g) - 2):
        done = False
        for x in range(2, len(g[0]) - 2):
            if g[y][x] == '#' and g[y - 1][x] == '#' and g[y + 1][x] in '.F' and (x, y + 1) not in taken and \
                    tile(g, x - 1, y) == '#' and tile(g, x + 1, y) == '#':
                g[y][x] = 'z'
                write_tiles(mid, g)
                patch(mid).setdefault('secretSpots', []).append('%d,%d' % (x, y))
                done = True
                break
        if done:
            break

# ---------- NPCs: HM gifts, tutors, rods, bike, trades, relearner, name rater, berries ----------
HM_GIVERS = {'cut': 'stonecrest', 'flash': 'duskmere', 'rockSmash': 'voltara', 'strength': 'cindercity',
             'surf': 'bramblegate', 'fly': 'skyreach', 'dive': 'lumenvale', 'waterfall': 'coralhaven'}
for mv_id, town in HM_GIVERS.items():
    name = ALL_MOVES[mv_id]['name']
    add_npc(town, 'hiker' if mv_id in ('rockSmash', 'strength', 'cut') else 'gentleman',
            ['I have a gift for travelers like you: %s!' % name],
            service='gift', gift=TM_ID[mv_id], flag='gift_' + TM_ID[mv_id],
            after=['%s works outside battle once you have badge %d. Use it from the PARTY menu.' % (name, FD.HM_BADGES[mv_id])])
for mv_id, town in FD.TUTORS:
    add_npc(town, 'old', ["I'm a Move Tutor. I can teach %s, just once." % ALL_MOVES[mv_id]['name']],
            service='tutor', move=mv_id, flag='tutor_' + mv_id)
add_npc('route3', 'boy', ["I found a hollow in a tree full of vines! Let's make it our Secret Base!"],
        service='gift', gift=TM_ID['secretPower'], flag='gift_secretPower',
        after=['Use Secret Power on a vine-covered tree to make a Secret Base.'])
add_npc('duskmere', 'girl', ['Let me look at your lead creature...'], service='friendship')
add_npc('fernhollow', 'mom', ['Take this Navi Gear! It shows the region map and lets trainers call you for rematches.'],
        service='gift', gift='naviGear', flag='gift_naviGear', after=['Trainers you beat may want a rematch. Check the Navi Gear!'])
for rod, town in [('oldRod', 'duskmere'), ('goodRod', 'harrowfield'), ('superRod', 'coralhaven')]:
    add_npc(town, 'swimmer', ['Fishing is the best! Here, take this %s.' % ALL_ITEMS[rod]['name']],
            service='gift', gift=rod, flag='gift_' + rod, after=['Face the water and use the rod from your BAG.'])
add_npc('voltara', 'boy', ["Welcome to Rydel's Cycles! First-time riders get a free bike!"],
        service='gift', gift='bike', flag='gift_bike', after=['Use the Bicycle from your BAG to ride twice as fast.'])
add_npc('route4', 'old', ['I grow berries. Here, take one!'], service='berryGift', flag='berry_daily')
add_npc('route4', 'girl', ['Water berry plants and they yield more!'], service='gift', gift='wailmerPail',
        flag='gift_wailmerPail', after=['Water soil with the Watering Can for a bigger harvest.'])
add_npc('bramblegate', 'gentleman', ["I'm the Move Maniac. Bring me a Heart Scale and I'll help a creature remember a forgotten move."],
        service='relearner')
add_npc('skyreach', 'psychic', ["I'm the Name Rater. Shall I rate your creature's nickname?"], service='nameRater')
add_npc('lumenvale', 'beauty', ['A Contest Pass is required to enter the Showcase Hall. Here, take one!'],
        service='gift', gift='contestPass', flag='gift_contestPass', after=['Treat Blocks raise a creature\'s condition.'])
add_npc('lumenvale', 'girl', ['Here, a Block Case for your Treat Blocks!'], service='gift', gift='blockCase',
        flag='gift_blockCase', after=['Blend berries at the Showcase Hall.'])


def trade_offer(town, want_area, give_area, nick):
    want = sorted([k for k, v in SPECIES.items() if v.get('area') == want_area and base_form(k) == k], key=lambda k: SPECIES[k]['dex'])
    give = sorted([k for k, v in SPECIES.items() if v.get('area') == give_area and base_form(k) == k and k not in want],
                  key=lambda k: SPECIES[k]['dex'])
    w, gsp = want[0], give[-1]
    add_npc(town, 'boy', ["I want a %s. Will you trade me one for my %s?" % (SPECIES[w]['name'], SPECIES[gsp]['name'])],
            service='npcTrade', want=w, give=gsp, nickname=nick, flag='trade_%s' % town)


trade_offer('stonecrest', 2, 4, 'DOTS')
trade_offer('cindercity', 5, 7, 'SEASOR')
trade_offer('coralhaven', 9, 10, 'PLUSES')

# ---------- town data: fly points ----------
for mid, m in MAPS.items():
    if not (m.get('town') or mid == 'fernhollow'):
        continue
    for k, d in m.get('doors', {}).items():
        if d['kind'] == 'lodge':
            x, y = map(int, k.split(','))
            OUT['flyPoints'][mid] = {'x': x, 'y': y + 1, 'name': m['name']}

# ---------- fishing and surfing tables ----------
def water_table(level, n=4):
    lo = [k for k in water_sp if (SPECIES[k].get('area') or 99) <= max(1, level // 4 + 1) or base_form(k) == k]
    pool = sorted(set(lo), key=lambda k: bst(SPECIES[k]))
    if level < 20:
        pool = pool[:n + 2]
    else:
        pool = pool[len(pool) // 3:]
    r = random.Random(level)
    r.shuffle(pool)
    return pool[:n]


for mid in list(MAPS) + list(OUT['maps']):
    g = get_grid(mid)
    if not any(c in '~D' for row in g for c in row):
        continue
    m = MAPS.get(mid) or OUT['maps'][mid]
    r = m.get('route') or route_no(mid)
    if mid in MAPS and m.get('town'):
        r = next((i for i, gy in enumerate(MISC['gyms']) if gy['town'] == mid), 3) * 2 + 2
    if mid == 'fernhollow':
        r = 1
    lv = ROUTE_LEVELS[min(r, 12)][1] if r else 30
    if mid in ('route13', 'safarizone', 'seacavern'):
        lv = 36 if mid != 'safarizone' else 28
    old = water_table(5)
    good = water_table(max(15, lv - 10))
    sup = water_table(max(30, lv))
    p = patch(mid) if mid in MAPS else OUT['maps'][mid]
    p['fishing'] = {
        'old': [{'species': s, 'min': 5, 'max': 10, 'weight': w} for s, w in zip(old[:2], [70, 30])],
        'good': [{'species': s, 'min': max(10, lv - 15), 'max': max(15, lv - 8), 'weight': w} for s, w in zip(good[:3], [60, 20, 20])],
        'super': [{'species': s, 'min': max(20, lv - 5), 'max': max(25, lv + 5), 'weight': w} for s, w in zip(sup[:4], [40, 40, 15, 5])],
    }
    p['waterEncounters'] = [{'species': s, 'min': max(5, lv - 8), 'max': max(8, lv), 'weight': w}
                            for s, w in zip(water_table(lv + 1, 3), [60, 30, 10])]

# ---------- weather ----------
for mid, w in {'route5': 'sand', 'route6': 'ash', 'route9': 'rain', 'route10': 'rain', 'route12': 'fog',
               'coralhaven': 'rain'}.items():
    patch(mid)['weather'] = w

# ---------- shops ----------
OUT['shops'] = {
    'tms': [TM_ID[m] for m in SHOP_TMS],
    'battle': ['xAttack', 'xDefend', 'xSpeed', 'xSpecial', 'xAccuracy', 'direHit', 'guardSpec', 'maxRepel', 'hpUp',
               'protein', 'iron', 'calcium', 'zinc', 'carbos'],
    'deco': ['decoDesk', 'decoChair', 'decoPlant', 'decoRug', 'decoDoll', 'decoCushion', 'decoPoster', 'decoTV',
             'decoStatue', 'decoLamp'],
    'bp': [['rareCandy', 5], ['ppUp', 8], ['leftovers', 48], ['choiceBand', 64], ['focusBand', 48], ['scopeLens', 48],
           ['brightPowder', 48], ['whiteHerb', 32], ['quickClaw', 48], ['kingsRock', 48], ['luckyEgg', 64],
           ['masterOrb', 150]] + [[TM_ID[m], 32] for m in BP_TMS],
    'mart': {'0': ['orb', 'potion', 'antidote', 'parlyzHeal', 'awakening', 'burnHeal', 'repel'],
             '1': ['greatOrb', 'superPotion', 'escapeRope', 'iceHeal'],
             '2': ['revive', 'superRepel', 'netOrb', 'nestOrb'],
             '3': ['ultraOrb', 'fullHeal', 'repeatOrb', 'timerOrb'],
             '4': ['hyperPotion', 'maxRepel', 'luxuryOrb', 'diveOrb'],
             '6': ['maxPotion', 'ether'], '7': ['fullRestore', 'maxRevive']},
}
OUT['decorations'] = {
    'decoDesk': {'name': 'Small Desk', 'price': 3000, 'color': '#a07040', 'solid': True},
    'decoChair': {'name': 'Small Chair', 'price': 2000, 'color': '#c08850', 'solid': True},
    'decoPlant': {'name': 'Pretty Plant', 'price': 3000, 'color': '#48a048', 'solid': True},
    'decoRug': {'name': 'Spin Mat', 'price': 4000, 'color': '#d06060', 'solid': False},
    'decoDoll': {'name': 'Nibbit Doll', 'price': 3000, 'color': '#b89a78', 'solid': True},
    'decoCushion': {'name': 'Fire Cushion', 'price': 2000, 'color': '#f07038', 'solid': False},
    'decoPoster': {'name': 'Blue Poster', 'price': 1000, 'color': '#5880d8', 'solid': True},
    'decoTV': {'name': 'Small TV', 'price': 6000, 'color': '#404858', 'solid': True},
    'decoStatue': {'name': 'Stone Statue', 'price': 8000, 'color': '#909898', 'solid': True},
    'decoLamp': {'name': 'Glow Lamp', 'price': 5000, 'color': '#f8e070', 'solid': True},
}
for k, d in OUT['decorations'].items():
    OUT['items'][k] = {'id': k, 'name': d['name'], 'price': d['price'], 'effect': {'kind': 'deco'},
                       'desc': 'A decoration for your Secret Base.', 'pocket': 'key'}

# ---------- contest move categories ----------
CATEGORY = {'Fire': 'cool', 'Fighting': 'cool', 'Dragon': 'cool', 'Electric': 'cool', 'Steel': 'tough',
            'Water': 'beauty', 'Ice': 'beauty', 'Flying': 'beauty', 'Psychic': 'smart', 'Grass': 'smart',
            'Ghost': 'smart', 'Dark': 'smart', 'Normal': 'cute', 'Bug': 'cute', 'Poison': 'tough',
            'Rock': 'tough', 'Ground': 'tough', 'Mystery': 'tough'}
OUT['contest'] = {
    'moveCategory': {k: CATEGORY[v['type']] for k, v in ALL_MOVES.items()},
    'moveAppeal': {k: (2 if v['power'] == 0 else min(4, 1 + v['power'] // 40)) for k, v in ALL_MOVES.items()},
    'rivals': [['Lady Mira', 'beauty'], ['Boy Teo', 'boy'], ['Psychic Lune', 'psychic'], ['Old Dana', 'old'],
               ['Girl Pia', 'girl'], ['Gent Ash', 'gentleman']],
}

# Tower pool: fully evolved, non-legendary.
OUT['tower'] = {'pool': sorted(k for k in SPECIES if is_final(k) and k not in LEGENDARIES and bst(SPECIES[k]) >= 380)}
OUT['tutors'] = [m for m, _ in FD.TUTORS]


# Dive spots: D tiles on Route 13 line up with D tiles on the seafloor.
OUT['maps']['route13']['diveTo'] = 'seafloor'
OUT['maps']['seafloor']['surfaceTo'] = 'route13'

# ---------- tile letters ----------
# Generation uses c (cave floor), B (boulder), q (roof) and P (base PC); the building interiors already use
# those letters for counters, beds, shelves and plants, so the output swaps them for g, O, i and Q.
SWAP = str.maketrans({'c': 'g', 'B': 'O', 'q': 'i', 'P': 'Q'})
for m in OUT['maps'].values():
    m['tiles'] = [r.translate(SWAP) for r in m['tiles']]
for k, p in OUT['mapPatches'].items():
    if 'tiles' in p:
        old = MAPS[k]['tiles']
        p['tiles'] = [''.join(ch.translate(SWAP) if ch != (old[y][x] if y < len(old) and x < len(old[y]) else None) else ch
                              for x, ch in enumerate(r)) for y, r in enumerate(p['tiles'])]
WALKABLE = set('.,=Fhlm:ju_eagdysX')

# ---------- the rest of Emerald: Itemfinder, Game Corner, Lottery, Trick House, Mirage Island, Berry Master,
# Battle Frontier, mail, the region map ----------
def building_i(town, id, name, npcs, rows=ROOM, **extra):
    door = add_building(town, id, roof='i')
    return interior(id, name, rows, town, door, npcs, **extra)


for it in FD.extra_items():
    OUT['items'][it['id']] = it
ALL_ITEMS.update(OUT['items'])
OUT['shops']['mart']['1'] += ['orangeMail', 'harborMail']
OUT['shops']['mart']['3'] += ['glitterMail', 'mechMail']
OUT['shops']['mart']['4'] += ['woodMail', 'waveMail']

# Itemfinder (Stonecrest) and Coin Case (Cinder City).
add_npc('stonecrest', 'boy', ["Some items are buried where you can't see them. This Itemfinder beeps when one is near!"],
        service='gift', gift='itemfinder', flag='gift_itemfinder',
        after=['Use the Itemfinder from your BAG. It points toward hidden items nearby.'])

# Game Corner (Cinder City): slot machines (Y), coins and prizes.
GAME_CORNER = ['|||||||||||||||',
               '|_____________|',
               '|_Y_Y_Y_Y_Y_Y_|',
               '|_____________|',
               '|_____________|',
               '|_Y_Y_Y_Y_Y_Y_|',
               '|_____________|',
               '|_____________|',
               '|cccc_____cccc|',
               '|_____________|',
               '|_____________|',
               '|||||||e|||||||']
building_i('cindercity', 'gamecorner', 'Game Corner', [
    npc(2, 7, 'clerk', ['Welcome to the Game Corner! Coins are 50 for $1,000.'], service='coins'),
    npc(12, 7, 'clerk', ['Exchange your coins for prizes!'], service='prizes'),
    npc(7, 9, 'gentleman', ['You need a Coin Case to play. Here, have mine!'], service='gift', gift='coinCase',
        flag='gift_coinCase', after=['Face a slot machine and press A to play. Three 7s pay 300 coins!']),
    npc(4, 4, 'girl', ['Press A three times to stop the reels. Line up three of a kind on the middle row!']),
], rows=GAME_CORNER, music='town')
OUT['prizes'] = {
    'items': [['tm%02d' % (FD.TMS.index('thunderbolt') + 1), 4000], ['tm%02d' % (FD.TMS.index('iceBeam') + 1), 4000],
              ['tm%02d' % (FD.TMS.index('flamethrower') + 1), 4000], ['tm%02d' % (FD.TMS.index('psychic') + 1), 3500],
              ['tm%02d' % (FD.TMS.index('shadowBall') + 1), 3500], ['brightPowder', 1500], ['scopeLens', 1500],
              ['quickClaw', 1000], ['kingsRock', 1000], ['rareCandy', 800], ['ppUp', 1200]],
    'creatures': [],
}
# Three prize creatures nobody can catch in the wild.
wild_species = set()
for mm in list(MAPS.values()) + list(OUT['maps'].values()) + list(OUT['mapPatches'].values()):
    for key in ('encounters', 'waterEncounters'):
        for e in mm.get(key, []) or []:
            wild_species.add(e['species'])
    for rod in (mm.get('fishing') or {}).values():
        for e in rod:
            wild_species.add(e['species'])
STARTERS = set(MISC.get('starters', []))
unwild = sorted([k for k in SPECIES if k not in wild_species and k not in LEGENDARIES and base_form(k) not in STARTERS],
                key=lambda k: (bst(SPECIES[k]), k))
prize_mons = unwild[len(unwild) // 3: len(unwild) // 3 + 3] if len(unwild) >= 6 else unwild[:3]
OUT['prizes']['creatures'] = [[sp, 25 + 5 * i, 2000 + 2500 * i] for i, sp in enumerate(prize_mons)]
mirage_mon = unwild[len(unwild) // 3 + 4]

# Lottery corner (Lumenvale Dept. Store).
OUT['maps']['deptstore']['npcs'].append(
    npc(11, 8, 'girl', ["This is the Lottery Corner! We draw a number every day. If it matches the ID No. of one of "
                        "your creatures, you win a prize!"], service='lottery'))

# Berry Master's house (Route 8): two berries a day; his wife hands out a rare one once a day.
building_i('route8', 'berrymaster', "Berry Master's House", [
    npc(7, 4, 'old', ["I'm the Berry Master! I grow berries for anyone who loves them. Take these!"],
        service='berryMaster', flag='berrymaster_daily'),
    npc(4, 6, 'beauty', ["My husband's berries are the best. Have one of my favorites, too."],
        service='berryWife', flag='berrywife_daily'),
], theme='#e8d8b8')

# Mirage Island: shows up on Route 13 on some days (see Field.mirage_visible).
MIRAGE = ['~aaaaa~',
          'aa,,,aa',
          'a,,,,,a',
          'aa,,,aa',
          '~aaaaa~']
OUT['maps']['route13']['mirage'] = {'x': 22, 'y': 2, 'tiles': MIRAGE}
OUT['maps']['route13']['berries'] = {'25,4': 'liechiBerry'}
OUT['maps']['route13']['encounters'] = [{'species': mirage_mon, 'min': 30, 'max': 35, 'weight': 100}]
add_npc('saltmarsh', 'old', ['I look out to sea every morning, hoping to see Mirage Island...'], service='mirageWatch')

# Trick House (Route 7): find the Trick Master, then solve his puzzle rooms.
TRICK_HOUSE = ['|||||||||||||||',
               '|_KK_______KK_|',
               '|_____________|',
               '|_t_________t_|',
               '|_____________|',
               '|______o______|',
               '|_____________|',
               '|_t_________t_|',
               '|_____________|',
               '|_KK_______KK_|',
               '|_____________|',
               '|||||||e|||||||']
building_i('route7', 'trickhouse', 'Trick House', [], rows=TRICK_HOUSE, trickHouse=True, theme='#d8c8e0')
OUT['maps']['trickhouse']['hideSpots'] = ['2,1', '3,1', '11,1', '12,1', '2,3', '12,3', '7,5', '2,7', '12,7', '2,9', '3,9', '11,9', '12,9']
# Puzzle rooms: a maze from the door (bottom) to the stairs (X, top). The way through is blocked by trees to Cut
# (room 1), rocks to smash (room 2) and boulders to push aside with Strength (room 3).
def trick_maze(level, seed):
    r = random.Random(seed)
    W, H = 15, 13
    g = [['|'] * W for _ in range(H)]
    cells = [(x, y) for y in range(1, H - 1, 2) for x in range(1, W - 1, 2)]
    start = (7, 11)
    seen = {start}
    stack = [start]
    g[start[1]][start[0]] = '_'
    while stack:
        x, y = stack[-1]
        nb = [(x + dx, y + dy, dx, dy) for dx, dy in [(0, -2), (0, 2), (-2, 0), (2, 0)]
              if 1 <= x + dx < W - 1 and 1 <= y + dy < H - 1 and (x + dx, y + dy) not in seen]
        if not nb:
            stack.pop()
            continue
        nx, ny, dx, dy = r.choice(nb)
        g[y + dy // 2][x + dx // 2] = '_'
        g[ny][nx] = '_'
        seen.add((nx, ny))
        stack.append((nx, ny))
    g[H - 1][7] = 'e'
    # The stairs: the top-row cell farthest along the maze from the door.
    def bfs(src):
        dist, prev, q = {src: 0}, {}, deque([src])
        while q:
            x, y = q.popleft()
            for dx, dy in DX:
                n = (x + dx, y + dy)
                if g[n[1]][n[0]] == '_' and n not in dist:
                    dist[n] = dist[(x, y)] + 1
                    prev[n] = (x, y)
                    q.append(n)
        return dist, prev
    dist, prev = bfs(start)
    goal = max([c for c in cells if c[1] == 1], key=lambda c: dist[c])
    g[1][goal[0]] = 'X'
    path = [goal]
    while path[-1] != start:
        path.append(prev[path[-1]])
    path.reverse()
    on_path = set(path)
    if level < 3:
        spots = [p for p in path[3:-2] if p[0] % 2 == 0 or p[1] % 2 == 0]
        r.shuffle(spots)
        picks = spots[:3]
        for i, (x, y) in enumerate(picks):
            g[y][x] = 'T' if level == 1 or i == 2 else 'R'
        return [''.join(row) for row in g] if len(picks) == 3 else None
    # Strength: a boulder on a junction of the path, pushed straight on into a dead-end branch.
    placed = 0
    for i in range(2, len(path) - 2):
        (px, py), (jx, jy) = path[i - 1], path[i]
        bx, by = 2 * jx - px, 2 * jy - py
        if g[by][bx] == '_' and (bx, by) not in on_path and g[2 * by - jy][2 * bx - jx] == '_' and placed < 2:
            g[jy][jx] = 'O'
            on_path.add((bx, by))
            placed += 1
    if placed < 2:
        return None
    spots = [p for p in path[3:-2] if g[p[1]][p[0]] == '_' and (p[0] % 2 == 0 or p[1] % 2 == 0)]
    if not spots:
        return None
    x, y = r.choice(spots)
    g[y][x] = 'R'
    return [''.join(row) for row in g]


PUZZLES = []
for lv in (1, 2, 3):
    sd = lv * 100
    rows = None
    while rows is None:
        sd += 1
        rows = trick_maze(lv, sd)
    PUZZLES.append(rows)
TRICK_PRIZES = [['rareCandy', 'nugget'], ['ppUp', 'starPiece'], ['leftovers', 'masterOrb']]
for i, rows in enumerate(PUZZLES):
    assert all(len(r) == 15 for r in rows), (i, [len(r) for r in rows])
    pid = 'trickpuzzle%d' % (i + 1)
    sx = rows[1].index('X')
    OUT['maps'][pid] = {
        'id': pid, 'name': 'Trick House Puzzle %d' % (i + 1), 'tiles': rows, 'indoor': True, 'theme': '#c8b8d8',
        'connections': {}, 'npcs': [], 'music': 'trickhouse',
        'warps': {'7,12': {'map': 'trickhouse', 'x': 7, 'y': 10, 'dir': 'up'},
                  '%d,1' % sx: {'map': 'trickreward', 'x': 7, 'y': 6, 'dir': 'up', 'script': 'trickDone', 'level': i + 1}},
        'trickLevel': i + 1,
    }
    # The way through needs the field moves (and Strength for the third room).
    g = [list(r) for r in rows]
    open_set = set('_eXTRO')
    seen, q = {(7, 12)}, deque([(7, 12)])
    while q:
        x, y = q.popleft()
        for dx, dy in DX:
            nx, ny = x + dx, y + dy
            if 0 <= ny < len(g) and 0 <= nx < 15 and (nx, ny) not in seen and g[ny][nx] in open_set:
                seen.add((nx, ny))
                q.append((nx, ny))
    assert (sx, 1) in seen, 'puzzle %d has no way through' % (i + 1)
OUT['maps']['trickreward'] = {
    'id': 'trickreward', 'name': 'Trick House', 'indoor': True, 'theme': '#d8c8e0', 'connections': {}, 'music': 'trickhouse',
    'tiles': ['|||||||||||||||', '|_____________|', '|_t_________t_|', '|_____________|', '|_____________|',
              '|_____________|', '|_____________|', '|||||||e|||||||'],
    'warps': {'7,7': dict(next(iter(OUT['maps']['trickhouse']['warps'].values())))},
    'npcs': [npc(7, 3, 'psychic', ['You solved my puzzle!'], service='trickPrize')],
}
OUT['trick'] = {'badges': [1, 3, 4], 'prizes': TRICK_PRIZES}

# ---------- Battle Frontier (ferry from Saltmarsh after becoming Champion) ----------
FRONTIER = [list('~' * 40) for _ in range(28)]


def fr(x0, y0, rows):
    for dy, r in enumerate(rows):
        for dx, ch in enumerate(r):
            FRONTIER[y0 + dy][x0 + dx] = ch


fr(1, 1, ['#' * 38] + ['#' + '.' * 36 + '#'] * 21 + ['#' + 'a' * 36 + '#'] * 2)
for x in range(2, 38):
    FRONTIER[11][x] = '='
    FRONTIER[19][x] = '='
for y in range(5, 25):
    FRONTIER[y][19] = '='
    FRONTIER[y][20] = '='
for y in range(23, 27):
    for x in range(18, 22):
        FRONTIER[y][x] = 'a'
FRONTIER[25][16] = FRONTIER[25][17] = 'a'
FACILITIES = [
    ('factory', 'Battle Factory', 4, 7, 'Rent creatures, then win seven battles in a row. You may swap a rental after each win.'),
    ('arena', 'Battle Arena', 11, 7, 'Three-turn matches judged on Mind, Skill and Body. No switching!'),
    ('dome', 'Battle Dome', 26, 7, 'A four-round tournament. See your rival\'s team, then pick two of your three.'),
    ('palace', 'Battle Palace', 33, 7, 'Your creatures fight on their own, as their nature tells them.'),
    ('pike', 'Battle Pike', 4, 15, 'Choose one of three doors in each of 14 rooms. Anything could be behind them...'),
    ('pyramid', 'Battle Pyramid', 33, 15, 'Climb seven dark floors full of wild creatures and trainers. Bring only what you find!'),
    ('exchange', 'Exchange Service Corner', 18, 1, 'Exchange your Battle Points for prizes!'),
]
for fid, name, x, y, desc in FACILITIES:
    fr(x, y, ['iiii', 'iiii', 'wwdw'])
FRONTIER = [''.join(r) for r in FRONTIER]
fwarps = {}
for fid, name, x, y, desc in FACILITIES:
    rid = 'frontier_' + fid
    fwarps['%d,%d' % (x + 2, y + 2)] = {'map': rid, 'x': 7, 'y': 10, 'dir': 'up'}
    if fid == 'exchange':
        npcs = [npc(7, 4, 'clerk', [desc], service='shop', shop='bp'),
                npc(3, 6, 'ace', ['Each facility pays Battle Points for every set of seven wins.'])]
    else:
        npcs = [npc(7, 4, 'nurse', ['Welcome to the %s!' % name, desc], service='frontier', facility=fid),
                npc(11, 7, 'gentleman', ['Every facility uses level-50 creatures. Legendaries can\'t enter.'])]
    interior(rid, name, ROOM, 'battlefrontier', (x + 2, y + 2), npcs, theme='#d0d8e8', music='town')
OUT['flyPoints']['battlefrontier'] = {'x': 19, 'y': 21, 'name': 'Battle Frontier'}
OUT['maps']['battlefrontier'] = {
    'id': 'battlefrontier', 'name': 'Battle Frontier', 'tiles': FRONTIER, 'theme': '#d8d0c0', 'connections': {},
    'warps': fwarps, 'town': False, 'music': 'town',
    'npcs': [npc(17, 25, 'swimmer', ['The ferry leaves for Saltmarsh whenever you\'re ready.'], service='ferry', to='saltmarsh'),
             npc(22, 12, 'ace', ['Welcome to the Battle Frontier! Seven facilities, one goal: become the strongest.']),
             npc(8, 20, 'girl', ['Win seven battles in a row anywhere here and you earn Battle Points.'])],
}
add_npc('saltmarsh', 'swimmer', ['This ferry runs to the Battle Frontier. Only Champions may board.'], service='ferry',
        to='battlefrontier')
# The Pyramid's floors are built in the game; these are the wild creatures inside.
OUT['frontier'] = {
    'pyramidWild': sorted(k for k in SPECIES if k not in LEGENDARIES and 380 <= bst(SPECIES[k]) <= 520)[:40],
    'arrive': {'battlefrontier': [19, 24], 'saltmarsh': None},
}




# ---------- the last of Emerald: Move Deleter, ash and glass flutes, rare fishing spots, TV and outbreaks, the
# trendy phrase, Quiz Lady, Fan Club, art museum, national dex, fossils, Battle Tents, Shoal Cave ----------
INTERIORS = load('interiors')['maps']


def any_grid(mid):
    if mid in OUT['mapPatches'] and 'tiles' in OUT['mapPatches'][mid]:
        return [list(r) for r in OUT['mapPatches'][mid]['tiles']]
    if mid in OUT['maps']:
        return grid(OUT['maps'][mid])
    return grid(MAPS[mid] if mid in MAPS else INTERIORS[mid])


# The maps as they were when they were painted (assets/maps): tiles changed below are drawn over the painting.
PAINTED_GRIDS = {mid: any_grid(mid) for mid in set(MAPS) | set(INTERIORS) | set(OUT['maps'])}
EM = {}
for it in [
    FD.item('sootSack', 'Soot Sack', 0, {'kind': 'key', 'use': 'ash'}, 'Collects volcanic ash as you walk through ashy grass.', 'key'),
    FD.item('blueFlute', 'Blue Flute', 100, {'kind': 'cure', 'statuses': ['slp']}, 'A glass flute that wakes a sleeping creature.'),
    FD.item('whiteFlute', 'White Flute', 0, {'kind': 'key', 'use': 'flute', 'mode': 'more'}, 'Play it to draw wild creatures out. Play again to stop.', 'key'),
    FD.item('blackFlute', 'Black Flute', 0, {'kind': 'key', 'use': 'flute', 'mode': 'fewer'}, 'Play it to keep wild creatures away. Play again to stop.', 'key'),
    FD.item('rootFossil', 'Root Fossil', 0, {'kind': 'key', 'use': 'none', 'fossil': 'orecrag'}, 'A fossil of an ancient creature that lived among roots.', 'key'),
    FD.item('clawFossil', 'Claw Fossil', 0, {'kind': 'key', 'use': 'none', 'fossil': 'kobbrute'}, 'A fossil of an ancient creature with mighty claws.', 'key'),
    FD.item('shoalSalt', 'Shoal Salt', 20, {'kind': 'valuable'}, 'Salt from Shoal Cave. Someone there may want it.'),
    FD.item('shoalShell', 'Shoal Shell', 20, {'kind': 'valuable'}, 'A shell from Shoal Cave. Someone there may want it.'),
]:
    OUT['items'][it['id']] = it
for k, d in {'decoGlassChair': {'name': 'Glass Chair', 'price': 0, 'color': '#a8e0f0', 'solid': True},
             'decoGlassDesk': {'name': 'Glass Desk', 'price': 0, 'color': '#88d0e8', 'solid': True},
             'decoOrnament': {'name': 'Glass Ornament', 'price': 0, 'color': '#e0f0ff', 'solid': True}}.items():
    OUT['decorations'][k] = d
    OUT['items'][k] = {'id': k, 'name': d['name'], 'price': 0, 'effect': {'kind': 'deco'},
                       'desc': 'A decoration for your Secret Base.', 'pocket': 'key'}
ALL_ITEMS.update(OUT['items'])

# Move Deleter (Lumenvale): makes a creature forget a move, even an HM.
patch('lumenvale_house1').setdefault('npcs', []).append(
    npc(7, 7, 'old', ["I'm the Move Deleter. I can make a creature forget a move. Even an HM!"], service='moveDeleter'))

# Glass Workshop (Route 6, in the ash): a Soot Sack, then flutes and glass furniture for ash.
building_i('route6', 'glassworkshop', 'Glass Workshop', [
    npc(7, 4, 'gentleman', ["I'm a glassworker. I make flutes out of volcanic ash."], service='glass'),
    npc(3, 7, 'boy', ['Walk through the ashy grass with the Soot Sack and it fills up on its own.']),
], theme='#e8d8c8')
EM['glass'] = [['blueFlute', 250], ['whiteFlute', 500], ['blackFlute', 500], ['decoGlassChair', 2000], ['decoGlassDesk', 3000]]

# A rare creature that only bites at a few spots on Route 11's water; the spots move with the trendy phrase.
water_spots = [(x, y) for y, row in enumerate(get_grid('route11')) for x, ch in enumerate(row) if ch == '~']
EM['rareFish'] = {'map': 'route11', 'species': 'whirlsage', 'spots': 2, 'tiles': ['%d,%d' % p for p in water_spots],
                  'min': 20, 'max': 25}
add_npc('route11', 'old', ['Fishermen say a rare creature bites only at a few spots on this water.',
                              'Folks say the spots change whenever people start saying something new.'])

# Mass outbreaks: one route a day swarms with a creature from elsewhere (the TV news reports it).
used = set(OUT['prizes']['creatures'][i][0] for i in range(3)) | {mirage_mon, 'orecrag', 'kobbrute', 'whirlsage'}
EM['outbreaks'] = [k for k in unwild if SPECIES[k].get('evolves') and k not in used and k != 'cocoonix']
EM['outbreakRoutes'] = sorted([k for k in list(MAPS) if MAPS[k].get('route') and MAPS[k].get('encounters')], key=route_no)

# TVs in your house and every house.
for mid, m in INTERIORS.items():
    if mid.endswith('_home') or '_house' in mid:
        g = [list(r) for r in m['tiles']]
        if len(g) > 3 and g[2][4] == '_':
            g[2][4] = 'N'
            patch(mid)['tiles'] = [''.join(r) for r in g]

# The trendy phrase (Stonecrest) and the Quiz Lady (Showcase Hall).
add_npc('stonecrest', 'girl', ["What's trendy these days? Tell me what everyone should be saying!"], service='trendy')
OUT['maps']['contesthall']['npcs'].append(
    npc(3, 9, 'beauty', ["I'm the Quiz Lady! Answer my question correctly and win a prize!"], service='quiz'))
EM['quizPrizes'] = ['ppUp', 'rareCandy', 'starPiece', 'nugget', 'heartScale', 'luckyEgg']

# Fan Club (Skyreach): members become fans as you grow stronger; the chairwoman hands out the Effort Ribbon.
building_i('skyreach', 'fanclub', 'Creature Fan Club', [
    npc(7, 3, 'gentleman', ["I'm the Fan Club Chairman. Our members follow the strongest Trainers!"], service='fanClub'),
    npc(3, 6, 'girl', ['Are you famous yet?'], service='fan', fan=0),
    npc(11, 6, 'boy', ['I only cheer for the very best.'], service='fan', fan=1),
    npc(7, 8, 'beauty', ['Champions are so dreamy...'], service='fan', fan=2),
    npc(12, 9, 'old', ['A creature trained to its limits earns my Effort Ribbon.'], service='effortRibbon'),
], theme='#f0d8e0')
EM['fanGifts'] = [['ppUp', 'rareCandy', 'starPiece'], ['nugget', 'ppUp', 'luckyEgg'], ['masterOrb', 'nugget', 'rareCandy']]
EM['fanNeeds'] = [3, 6, 10]

# Art museum (Lumenvale): a painting of each Master Rank contest winner hangs in a frame (G).
MUSEUM = ['|||||||||||||||',
          '|_G_G_G_G_G___|',
          '|_____________|',
          '|_____________|',
          '|_____________|',
          '|_____________|',
          '|_____________|',
          '|_____________|',
          '|_____________|',
          '|_____________|',
          '|_____________|',
          '|||||||e|||||||']
building_i('lumenvale', 'museum', 'Lumenvale Art Museum', [
    npc(7, 4, 'gentleman', ["Welcome to the art museum! We paint the creatures that win Master Rank contests."], service='museum'),
    npc(12, 7, 'girl', ['Each frame holds a different contest category.']),
], rows=MUSEUM, theme='#e8e0d0')

# National dex: Prof. Alder upgrades the dex once you're Champion.
patch('fernhollow_lab').setdefault('npcs', []).append(
    npc(3, 3, 'prof', ['PROF. ALDER: Your dex only covers the creatures of Wildbound.'], service='nationalDex'))

# Fossils: the fossil maniac on Route 5 lets you pick one; the Fossil Lab in Stonecrest revives it.
add_npc('route5', 'hiker', ["I dig fossils out of the desert! I found two, but you can have one."], service='fossilPick')
building_i('stonecrest', 'fossillab', 'Fossil Lab', [
    npc(7, 4, 'psychic', ['We study ancient creatures. Bring me a fossil and I can bring it back to life!'], service='fossilLab'),
    npc(3, 7, 'boy', ['The machine takes a while. Go for a walk and come back.']),
], theme='#d8e0e8')
EM['fossilLevel'] = 20

# Battle Tents: three small Frontier facilities at level 30, three battles a set, an item prize.
for town, fid, name, desc in [
        ('saltmarsh', 'factory', 'Saltmarsh Battle Tent', 'Rent three creatures and win three battles in a row!'),
        ('harrowfield', 'palace', 'Harrowfield Battle Tent', 'Your creatures fight on their own here, as their nature tells them.'),
        ('bramblegate', 'arena', 'Bramblegate Battle Tent', 'Three-turn match-ups judged on Mind, Skill and Body!')]:
    building_i(town, 'tent_' + town, name, [
        npc(7, 4, 'nurse', ['Welcome to the %s!' % name, desc], service='tent', facility=fid),
        npc(11, 7, 'ace', ['Everyone fights at level 30 in a Battle Tent.'])], theme='#e8e0c0')
EM['tentPrizes'] = ['ppUp', 'rareCandy', 'leftovers', 'shellBell', 'quickClaw', 'kingsRock', 'scopeLens', 'brightPowder']

# Shoal Cave (an island on Route 13): the tide rises and falls every six hours (J tiles are water at high tide).
SHOAL = ['xxxxxxxxxxxxxxxxxxxx',
         'xggggxxxxxxxxxggggxx',
         'xgJJgggggggggggJJgxx',
         'xgJJgxxxxxxxxxgJJgxx',
         'xggggxxggggggxggggxx',
         'xxxgxxxgJJJJgxxxgxxx',
         'xxxgggggJJJJgggggxxx',
         'xxxxxxxgggggggxxxxxx',
         'xxxxxxxxxgyxxxxxxxxx',
         'xxxxxxxxxxxxxxxxxxxx']
SHOAL[8] = 'xxxxxxxxxxgxxxxxxxxx'
SHOAL.insert(9, 'xxxxxxxxxxyxxxxxxxxx')
g = get_grid('route13') if 'route13' in OUT['mapPatches'] else grid(OUT['maps']['route13'])
r13 = [list(r) for r in OUT['maps']['route13']['tiles']]
r13[12][16] = 'y'
OUT['maps']['route13']['tiles'] = [''.join(r) for r in r13]
OUT['maps']['route13']['warps']['16,12'] = {'map': 'shoalcave', 'x': 10, 'y': 8, 'dir': 'up'}
OUT['maps']['shoalcave'] = {
    'id': 'shoalcave', 'name': 'Shoal Cave', 'cave': True, 'connections': {}, 'tiles': SHOAL, 'tide': True,
    'warps': {'10,9': {'map': 'route13', 'x': 16, 'y': 13, 'dir': 'down'}}, 'encounterRate': 8,
    'encounters': [{'species': s, 'min': 26, 'max': 32, 'weight': w} for s, w in zip(water_sp[-16:-12], [40, 30, 20, 10])],
    'npcs': [npc(12, 4, 'old', ["Bring me four Shoal Salt and four Shoal Shells and I'll make you a Shell Bell."], service='shellBell')],
    'shoal': [[2, 1, 'shoalSalt'], [17, 1, 'shoalSalt'], [3, 4, 'shoalShell'], [16, 4, 'shoalShell'],
              [9, 6, 'shoalShell'], [10, 5, 'shoalSalt'], [13, 6, 'shoalShell'], [5, 6, 'shoalSalt']],
}
assert all(len(r) == 20 for r in SHOAL)

# ---------- six more legendaries: the golem trio (Braille puzzle) and the event islands ----------
def legend(id, dex, name, types, base, abilities, body, colors, feats, size, eyes, text, learnset, ev):
    sp = {'id': id, 'dex': dex, 'name': name, 'types': types, 'base': dict(zip(['hp', 'atk', 'def', 'spa', 'spd', 'spe'], base)),
          'abilities': abilities, 'catchRate': 3, 'baseExp': 260, 'evYield': ev, 'growth': 'slow', 'genderRatio': -1,
          'sprite': {'body': body, 'main': colors[0], 'accent': colors[1], 'belly': colors[2], 'features': feats,
                     'size': size, 'eyes': eyes},
          'dexText': text, 'area': 11, 'rarity': 'legendary',
          'learnset': [[lv, m] for lv, m in learnset if m in ALL_MOVES], 'evolves': None}
    SPECIES[id] = sp
    LEGENDARIES.append(id)
    sp['eggGroups'] = ['Undiscovered']
    sp['tms'] = sorted(TM_ID[mid] for mid in FD.TMS + FD.HMS if compatible(id, mid))
    sp['tutor'] = [mid for mid in TUTOR_MOVES if TUTOR_RULE[mid](sp)]
    sp['eggMoves'] = []
    OUT['species'][id] = sp
    return id


GOLEMS = [
    legend('cragolem', 201, 'Cragolem', ['Rock'], [80, 100, 200, 50, 100, 50], ['clearBody'], 'rock',
           ['#b07848', '#f0a030', '#d8b088'], ['spikes', 'crest'], 1, 'round',
           'Its body is made of ancient stone. It was sealed away for fear of its strength.',
           [(1, 'explosion'), (9, 'rockThrow'), (17, 'curse'), (25, 'superpower'), (33, 'ancientPower'), (41, 'ironDefense'),
            (49, 'zapCannon'), (57, 'lockOn'), (65, 'hyperBeam')], {'def': 3}),
    legend('glaciolem', 202, 'Glaciolem', ['Ice'], [80, 50, 100, 100, 200, 50], ['clearBody'], 'rock',
           ['#a8d8f0', '#f0a030', '#e8f8ff'], ['spikes', 'crest'], 1, 'round',
           'Made of ice from the ice age. It chills the air to minus 200 degrees.',
           [(1, 'explosion'), (9, 'icyWind'), (17, 'curse'), (25, 'superpower'), (33, 'ancientPower'), (41, 'amnesia'),
            (49, 'zapCannon'), (57, 'lockOn'), (65, 'hyperBeam')], {'spd': 3}),
    legend('ferrolem', 203, 'Ferrolem', ['Steel'], [80, 75, 150, 75, 150, 50], ['clearBody'], 'rock',
           ['#8890a0', '#f0a030', '#c8d0d8'], ['spikes', 'crest'], 1, 'round',
           'Its body is harder than any known metal, tempered by pressure deep underground.',
           [(1, 'explosion'), (9, 'metalClaw'), (17, 'curse'), (25, 'superpower'), (33, 'ancientPower'), (41, 'ironDefense'),
            (41, 'amnesia'), (49, 'zapCannon'), (57, 'lockOn'), (65, 'hyperBeam')], {'def': 2, 'spd': 1}),
]
MYTHRIN = legend('mythrin', 204, 'Mythrin', ['Psychic'], [100, 100, 100, 100, 100, 100], ['synchronize'], 'ghost',
                 ['#f0b0d0', '#80c0f0', '#fff0f8'], ['tail', 'ears'], 0.5, 'round',
                 'Said to hold the code of every creature. It shows itself only to the pure of heart.',
                 [(1, 'pound'), (10, 'megaPunch'), (20, 'metronome'), (30, 'psychic'), (40, 'ancientPower'), (50, 'recover')], {'hp': 3})
ASTRAXIS = legend('astraxis', 205, 'Astraxis', ['Psychic'], [50, 150, 50, 150, 50, 150], ['pressure'], 'biped',
                  ['#e06840', '#40b0c0', '#f0d8c0'], ['antenna', 'tail'], 0.9, 'fierce',
                  'It fell to the ground riding a meteor. A crystal in its chest fires lasers.',
                  [(1, 'leer'), (1, 'wrap'), (5, 'nightShade'), (10, 'teleport'), (15, 'knockOff'), (20, 'swift'), (30, 'extrasensory'),
                   (40, 'cosmicPower'), (50, 'recover'), (55, 'psychoBoost'), (65, 'hyperBeam')], {'atk': 1, 'spa': 1, 'spe': 1})
AUROQUIL = legend('auroquil', 206, 'Auroquil', ['Fire', 'Flying'], [106, 130, 90, 110, 154, 90], ['pressure'], 'bird',
                  ['#e8a030', '#e04838', '#f8e8a0'], ['wings', 'crest', 'tailFlame'], 1, 'fierce',
                  'Its feathers glow in seven colors. A rainbow follows wherever it flies.',
                  [(1, 'gust'), (11, 'recover'), (22, 'fireBlast'), (33, 'sunnyDay'), (44, 'swift'), (55, 'safeguard'),
                   (66, 'sacredFire'), (77, 'calmMind'), (88, 'skyAttack'), (99, 'hyperBeam')], {'spd': 3})

# The Sealed Chamber, under the sea: its Braille walls tell how to wake the golems.
FLOOR = [list(r) for r in OUT['maps']['seafloor']['tiles']]
FLOOR[1][13] = 'y'
OUT['maps']['seafloor']['tiles'] = [''.join(r) for r in FLOOR]
OUT['maps']['seafloor']['warps']['13,1'] = {'map': 'sealedchamber', 'x': 7, 'y': 9, 'dir': 'up'}
CHAMBER = ['xxxxxxxxxxxxxxx',
           'xxZxxxxZxxxxZxx',
           'xxgxxxxgxxxxgxx',
           'xxgggggggggggxx',
           'xxgggggggggggxx',
           'xxgggggggggggxx',
           'xxgggggggggggxx',
           'xxxxggggggxxxxx',
           'xxxxxxgggxxxxxx',
           'xxxxxxxgxxxxxxx',
           'xxxxxxxyxxxxxxx']
OUT['maps']['sealedchamber'] = {
    'id': 'sealedchamber', 'name': 'Sealed Chamber', 'cave': True, 'connections': {}, 'tiles': CHAMBER,
    'warps': {'7,10': {'map': 'seafloor', 'x': 13, 'y': 2, 'dir': 'down'}},
    'braille': {'2,1': 'IN THIS CAVE WE HAVE LIVED. WE OWE ALL TO THE CREATURES.',
                '12,1': 'BUT WE SEALED THE CREATURES AWAY. WE FEARED THEM.',
                '7,1': 'FIRST COMES A CREATURE OF THE SEA. LAST COMES A CREATURE OF STONE. THEN DIG.'},
    'chamber': '7,1',
}
# The three tombs: each Braille wall names a field move to use in front of it.
TOMB = ['xxxxxxxxxxxxxxx',
        'xxxxxxxZxxxxxxx',
        'xxxxxgggggxxxxx',
        'xxxxgggggggxxxx',
        'xxxgggggggggxxx',
        'xxxgggggggggxxx',
        'xxxgggggggggxxx',
        'xxxxgggggggxxxx',
        'xxxxxgggggxxxxx',
        'xxxxxxxgxxxxxxx',
        'xxxxxxxyxxxxxxx']
for golem, route, tid, name, move, text in [
        (GOLEMS[0], 'route4', 'tomb_rock', 'Desert Tomb', 'strength', 'THOSE WITH STRENGTH, MOVE THE STONE.'),
        (GOLEMS[1], 'route8', 'tomb_ice', 'Frost Tomb', 'wait', 'STAND STILL IN THE COLD. WAIT FOR TWO MINUTES.'),
        (GOLEMS[2], 'route7', 'tomb_steel', 'Iron Tomb', 'fly', 'SHOW THE SKY TO THE WALL. USE FLY.')]:
    tx, ty = cave_mouth(route, tid, (7, 9))
    OUT['maps'][tid] = {
        'id': tid, 'name': name, 'cave': True, 'connections': {}, 'tiles': TOMB,
        'warps': {'7,10': {'map': route, 'x': tx, 'y': ty + 1, 'dir': 'down'}},
        'braille': {'7,1': text}, 'tomb': {'wall': '7,1', 'move': move, 'flag': tid + '_open'},
        'statics': [{'id': 'leg_' + golem, 'species': golem, 'level': 40, 'x': 7, 'y': 5, 'requires': tid + '_open',
                     'text': 'The golem\'s eyes light up...'}],
    }

# Event islands, reached by ferry from Saltmarsh with a ticket.
def island(id, name, rows, x, y, **extra):
    m = {'id': id, 'name': name, 'tiles': rows, 'connections': {}, 'theme': '#d8d0c0', 'music': 'town', 'outside': '~',
         'npcs': [npc(x, y, 'swimmer', ['The ferry goes back to Saltmarsh whenever you\'re ready.'], service='ferry', to='saltmarsh')]}
    m.update(extra)
    assert all(len(r) == len(rows[0]) for r in rows), id
    OUT['maps'][id] = m
    return m


island('southernisland', 'Southern Island', [
    '~~~~~~~~~~~~~~~~~~~~',
    '~~~~~aaaaaaaaaa~~~~~',
    '~~~aaa########aaa~~~',
    '~~aaa##......##aaa~~',
    '~~aa##........##aa~~',
    '~~aa#....FF....#aa~~',
    '~~aa#...F..F...#aa~~',
    '~~aa#....FF....#aa~~',
    '~~aa##........##aa~~',
    '~~aaa###....###aaa~~',
    '~~~aaaaa....aaaaa~~~',
    '~~~~aaaaaaaaaaaa~~~~',
    '~~~~~~~aaaaaa~~~~~~~',
    '~~~~~~~~~~~~~~~~~~~~'], 8, 12,
    statics=[{'id': 'leg_eon_' + sp, 'species': sp, 'level': 50, 'x': 9 + i, 'y': 6, 'eon': True,
              'text': 'A creature with a dream-like glow is resting here...'} for i, sp in enumerate(OUT['roamers'])])
island('farawayisland', 'Faraway Island', [
    '~~~~~~~~~~~~~~~~~~~~',
    '~~~aaaaaaaaaaaaaa~~~',
    '~~aa,,,,,,,,,,,,aa~~',
    '~aa,,,,,,,,,,,,,,aa~',
    '~a,,,,,#,,,,#,,,,,a~',
    '~a,,,,,,,,,,,,,,,,a~',
    '~a,,,#,,,,,,,,#,,,a~',
    '~a,,,,,,,,,,,,,,,,a~',
    '~aa,,,,,,,,,,,,,,aa~',
    '~~aa,,,,....,,,,aa~~',
    '~~~aaaaa....aaaaa~~~',
    '~~~~~~~aaaaaa~~~~~~~',
    '~~~~~~~~~~~~~~~~~~~~'], 8, 11, encounterRate=0,
    statics=[{'id': 'leg_' + MYTHRIN, 'species': MYTHRIN, 'level': 30, 'x': 9, 'y': 4,
              'text': 'A tiny pink creature peeks out of the tall grass!'}])
island('birthisland', 'Birth Island', [
    '~~~~~~~~~~~~~~~~~~~~',
    '~~~~~aaaaaaaaaa~~~~~',
    '~~~aaaaaaaaaaaaaa~~~',
    '~~aaaaaaaaaaaaaaaa~~',
    '~~aaaaaaaaaaaaaaaa~~',
    '~~aaaaaaaaaaaaaaaa~~',
    '~~aaaaaaaaaaaaaaaa~~',
    '~~aaaaaaaaaaaaaaaa~~',
    '~~~aaaaaaaaaaaaaa~~~',
    '~~~~aaaaaaaaaaaa~~~~',
    '~~~~~~~aaaaaa~~~~~~~',
    '~~~~~~~~~~~~~~~~~~~~'], 8, 10,
    triangle=[[9, 5], [5, 3], [14, 3], [4, 7], [15, 7], [9, 8], [9, 3], [12, 6]],
    statics=[{'id': 'leg_' + ASTRAXIS, 'species': ASTRAXIS, 'level': 30, 'x': 9, 'y': 4, 'requires': 'birth_puzzle',
              'text': 'The triangle split open, and something came out of it!'}])
island('navelrock', 'Navel Rock', [
    '~~~~xxxxxxxxxxx~~~~~',
    '~~~xxxxxgggxxxxx~~~~',
    '~~xxxxxgggggxxxxx~~~',
    '~~xxxxxxgggxxxxxx~~~',
    '~~xxxxxxxgxxxxxxx~~~',
    '~~xxxggggggxxxxxx~~~',
    '~~xxxgxxxxgggggxx~~~',
    '~~xxxgxxxxxxxxgxx~~~',
    '~~xxxggggggggggxx~~~',
    '~~xxxxxxxxgxxxxxx~~~',
    '~~~aaaaaaagaaaaa~~~~',
    '~~~~aaaaaaaaaaa~~~~~',
    '~~~~~~~~~~~~~~~~~~~~'], 8, 11, cave=False,
    statics=[{'id': 'leg_' + AUROQUIL, 'species': AUROQUIL, 'level': 70, 'x': 9, 'y': 1,
              'text': 'A rainbow-colored bird spreads its wings at the summit!'}])
EM['islands'] = {'southernisland': 'eonTicket', 'farawayisland': 'oldSeaMap', 'birthisland': 'auroraTicket',
                 'navelrock': 'mysticTicket'}
for it in [FD.item('eonTicket', 'Eon Ticket', 0, {'kind': 'key', 'use': 'none'}, 'A ferry ticket to Southern Island.', 'key'),
           FD.item('oldSeaMap', 'Old Sea Map', 0, {'kind': 'key', 'use': 'none'}, 'A faded map that shows the way to a faraway island.', 'key'),
           FD.item('auroraTicket', 'Aurora Ticket', 0, {'kind': 'key', 'use': 'none'}, 'A ferry ticket to Birth Island.', 'key'),
           FD.item('mysticTicket', 'Mystic Ticket', 0, {'kind': 'key', 'use': 'none'}, 'A ferry ticket to Navel Rock.', 'key')]:
    OUT['items'][it['id']] = it
for n in OUT['mapPatches']['saltmarsh']['npcs']:
    if n.get('service') == 'ferry':
        n['islands'] = list(EM['islands'])
# Who hands out the tickets.
add_npc('saltmarsh', 'old', ['I sailed to an island of dreams once... You need an Eon Ticket to go there.'],
        service='ticket', ticket='eonTicket', need='eon')
OUT['maps']['frontier_exchange']['npcs'].append(
    npc(11, 7, 'old', ['Clear a set of seven anywhere in the Frontier and I\'ll give you something old I found.'],
        service='ticket', ticket='oldSeaMap', need='frontier'))
patch('fernhollow_lab')['npcs'].append(
    npc(7, 7, 'boy', ['Catch 120 kinds of creatures and the professor\'s aide has a ticket for you!'],
        service='ticket', ticket='auroraTicket', need='dex'))
add_npc('summitcrown', 'gentleman', ['Enter the Hall of Fame twice and I\'ll give you a Mystic Ticket.'],
        service='ticket', ticket='mysticTicket', need='hof')
for mid, before in PAINTED_GRIDS.items():
    after = any_grid(mid)
    changed = ['%d,%d' % (x, y) for y, row in enumerate(after) for x, ch in enumerate(row)
               if y >= len(before) or x >= len(before[y]) or before[y][x] != ch]
    if changed:
        target = OUT['maps'][mid] if mid in OUT['maps'] else patch(mid)
        target['overpaint'] = changed
OUT['emerald'] = EM


# ---------- validation ----------
def all_maps():
    out = {}
    for k, m in MAPS.items():
        mm = dict(m)
        p = OUT['mapPatches'].get(k, {})
        if 'tiles' in p:
            mm['tiles'] = p['tiles']
        mm['connections'] = {**m.get('connections', {}), **p.get('connections', {})}
        mm['warps'] = {**m.get('warps', {}), **p.get('warps', {})}
        out[k] = mm
    out.update(OUT['maps'])
    return out


AM = all_maps()
errors = []
for k, m in AM.items():
    w = len(m['tiles'][0])
    for i, r in enumerate(m['tiles']):
        if len(r) != w:
            errors.append('%s row %d width %d != %d' % (k, i, len(r), w))
    for wk, wp in m.get('warps', {}).items():
        if wp['map'] not in AM:
            errors.append('%s warp %s to missing %s' % (k, wk, wp['map']))
            continue
        if wp.get('script') == 'baseExit':
            continue
        t = AM[wp['map']]['tiles']
        if not (0 <= wp['y'] < len(t) and 0 <= wp['x'] < len(t[0])) or t[wp['y']][wp['x']] not in WALKABLE:
            errors.append('%s warp %s lands on %r in %s' % (k, wk, t[wp['y']][wp['x']] if 0 <= wp['y'] < len(t) and 0 <= wp['x'] < len(t[0]) else '?', wp['map']))
    for it in OUT['mapPatches'].get(k, {}).get('items', []) + m.get('items', []):
        if m['tiles'][it['y']][it['x']] not in WALKABLE:
            errors.append('%s item %s on %r' % (k, it['id'], m['tiles'][it['y']][it['x']]))
    for n in OUT['mapPatches'].get(k, {}).get('npcs', []) + m.get('npcs', []):
        if m['tiles'][n['y']][n['x']] not in WALKABLE:
            errors.append('%s npc at %d,%d on %r' % (k, n['x'], n['y'], m['tiles'][n['y']][n['x']]))
for k, v in OUT['species'].items():
    for e in v.get('learnset', []):
        assert e[1] in ALL_MOVES, (k, e)
    for e in v.get('eggMoves', []):
        assert e in ALL_MOVES, (k, e)
    for h in v.get('heldItems', []):
        assert h[0] in ALL_ITEMS, (k, h)
for mid in FD.TMS + FD.HMS:
    if not any(TM_ID[mid] in v['tms'] for v in OUT['species'].values()):
        errors.append('nobody learns ' + mid)
if errors:
    print('\n'.join(errors))
    sys.exit(1)

# ---------- region map: where every outdoor map sits, in tiles ----------
def region_layout():
    am = all_maps()
    pos = {'fernhollow': (0, 0)}
    order = ['fernhollow']
    while order:
        a = order.pop(0)
        ax, ay = pos[a]
        A = am[a]
        aw, ah = len(A['tiles'][0]), len(A['tiles'])
        for d, c in A.get('connections', {}).items():
            b = c['map']
            B = am[b]
            bw, bh = len(B['tiles'][0]), len(B['tiles'])
            o = c['offset']
            p = {'up': (ax - o, ay - bh), 'down': (ax - o, ay + ah), 'left': (ax - bw, ay - o), 'right': (ax + aw, ay - o)}[d]
            if b not in pos:
                pos[b] = p
                order.append(b)
    minx = min(p[0] for p in pos.values())
    miny = min(p[1] for p in pos.values())
    out = {}
    for k, (x, y) in pos.items():
        m = am[k]
        out[k] = {'x': x - minx, 'y': y - miny, 'w': len(m['tiles'][0]), 'h': len(m['tiles']),
                  'town': bool(m.get('town') or k == 'fernhollow'), 'name': m['name']}
    # The Battle Frontier is out at sea, east of Route 13.
    r13 = out['route13']
    out['battlefrontier'] = {'x': r13['x'] + r13['w'] + 6, 'y': r13['y'] + 2, 'w': 40, 'h': 28, 'town': True,
                             'name': 'Battle Frontier', 'island': True}
    # Indoor maps and caves point at the outdoor map whose door leads to them.
    parent = {}
    changed = True
    while changed:
        changed = False
        for k, m in am.items():
            for wp in m.get('warps', {}).values():
                dst = wp['map']
                if dst in out or dst in parent:
                    continue
                src = k if k in out else parent.get(k)
                if src:
                    parent[dst] = src
                    changed = True
    return out, parent


OUT['regionMap'], OUT['mapParent'] = region_layout()


with open(os.path.join(ROOT, 'data', 'features.json'), 'w') as f:
    json.dump(OUT, f, indent=1)
print('features: %d moves, %d items, %d abilities, %d species patched, %d new maps, %d map patches'
      % (len(OUT['moves']), len(OUT['items']), len(OUT['abilities']), len(OUT['species']), len(OUT['maps']),
         len(OUT['mapPatches'])))
for sid, into, method, kw in evo_changes:
    print('  evolution: %s -> %s by %s %s' % (sid, into, method, kw.get('item', '')))
