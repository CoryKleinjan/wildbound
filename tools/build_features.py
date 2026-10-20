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

with open(os.path.join(ROOT, 'data', 'features.json'), 'w') as f:
    json.dump(OUT, f, indent=1)
print('features: %d moves, %d items, %d abilities, %d species patched, %d new maps, %d map patches'
      % (len(OUT['moves']), len(OUT['items']), len(OUT['abilities']), len(OUT['species']), len(OUT['maps']),
         len(OUT['mapPatches'])))
for sid, into, method, kw in evo_changes:
    print('  evolution: %s -> %s by %s %s' % (sid, into, method, kw.get('item', '')))
