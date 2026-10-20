#!/usr/bin/env python3
"""Adds Routes 14-34 and two forests to data/maps.json, bringing the region to Emerald's 34 routes.

Most new routes sit on the main road between a route and the next town, so towns are two or three
routes apart as in Emerald. The rest branch off the new routes as side trips. Nine are sea routes
(Surf, from the Bramblegate badge on), and Route 26 climbs a waterfall up to Victory Road.

Every map is generated here from a seeded layout: the road joins the edge openings, then trees, tall
grass, flowers, ledges, water, islets, trainers, a sign and a couple of items go around it, and each
step is checked so every opening, trainer and item stays reachable. Old maps are never retiled; only
their connections are pointed at the new routes, so their paintings still fit.

Run from the repo root, then rebuild what depends on the maps:
python3 tools/build_routes.py && python3 tools/build_interiors.py && python3 tools/build_story.py \
  && python3 tools/build_features.py
Running it again first removes the routes it added, so it is safe to rerun.
"""
import json
import os
import random
import sys
from collections import deque

ROOT = os.path.join(os.path.dirname(__file__), '..')


def load(name):
    with open(os.path.join(ROOT, 'data', name + '.json')) as f:
        return json.load(f)


MAPS = load('maps')
SPECIES = load('species')
MISC = load('misc')
FEATURES = load('features')
MAP_FIT = load('map_fit')
STYLES = load('town_styles')

WALKABLE = set('.,=Fhlm:ju_eagdysX')
OPP = {'up': 'down', 'down': 'up', 'left': 'right', 'right': 'left'}
DX = {'up': (0, -1), 'down': (0, 1), 'left': (-1, 0), 'right': (1, 0)}
TAG = 'build_routes'

# ---------- undo a previous run ----------
GENERATED = {k for k, m in MAPS.items() if m.get('generatedBy') == TAG}
for k in GENERATED:
    m = MAPS.pop(k)
    if 'between' in m:
        a, d, b, off = m['between']
        MAPS[a]['connections'][d] = {'map': b, 'offset': off}
        MAPS[b]['connections'][OPP[d]] = {'map': a, 'offset': -off}
for m in MAPS.values():
    for d in [d for d, c in m.get('connections', {}).items() if c['map'] not in MAPS]:
        del m['connections'][d]
for k in [k for k, s in STYLES.items() if s.get('generatedBy') == TAG]:
    del STYLES[k]


# ---------- the tiles the game really shows (feature patches, then the painting fit) ----------
def shown_tiles(mid):
    rows = list(MAPS[mid]['tiles'])
    p = FEATURES['mapPatches'].get(mid, {})
    if 'tiles' in p:
        rows = list(p['tiles'])
    fit = MAP_FIT.get(mid)
    if fit and os.path.exists(os.path.join(ROOT, 'assets', 'maps', mid + '.png')):
        newer = set(MAPS[mid].get('overpaint', []) + p.get('overpaint', []))
        rows = [list(r) for r in rows]
        for k, ch in fit.items():
            if k in newer:
                continue
            x, y = map(int, k.split(','))
            if y < len(rows) and x < len(rows[y]):
                rows[y][x] = ch
        rows = [''.join(r) for r in rows]
    return rows


def edge_cells(rows, side):
    h, w = len(rows), len(rows[0])
    n = w if side in ('up', 'down') else h
    out = []
    for i in range(n):
        x, y = {'up': (i, 0), 'down': (i, h - 1), 'left': (0, i), 'right': (w - 1, i)}[side]
        out.append(rows[y][x])
    return out


# ---------- species pools ----------
LEGENDARY = {k for k, v in SPECIES.items() if v.get('rarity') == 'legendary'}
PRE = {}
for k, v in SPECIES.items():
    e = v.get('evolves')
    if e:
        PRE[e['into']] = k


def line_of(sid):
    while sid in PRE:
        sid = PRE[sid]
    return sid


STARTER_LINES = {line_of(s) for s in MISC['starters']}


def min_level(sid):
    """The lowest level a wild one can sensibly have: evolved forms only after their evolution level."""
    if sid not in PRE:
        return 2
    e = SPECIES[PRE[sid]]['evolves']
    return max(min_level(PRE[sid]) + 1, e.get('level') or (min_level(PRE[sid]) + 14))


def max_level(sid):
    """Unevolved forms stop turning up wild well past the level they evolve at."""
    e = SPECIES[sid].get('evolves')
    return (e.get('level') or 30) + 16 if e else 100


USED = {}
for m in MAPS.values():
    for e in m.get('encounters') or []:
        USED[e['species']] = USED.get(e['species'], 0) + 1
# Only creatures already in the grass of the old routes: the rest are evolve-only, fossils, Game Corner prizes, the
# Mirage Island creature, outbreak creatures and the rare fish (tools/build_features.py picks those from creatures
# not on any route), and must stay that way.
WILD = [k for k in SPECIES if k not in LEGENDARY and line_of(k) not in STARTER_LINES and k in USED]
# Surfing creatures: those already met on the water of the old maps (tools/build_features.py tables).
WATER = set()
for k, p in FEATURES['mapPatches'].items():
    if k in MAPS and k not in GENERATED:
        WATER.update(e['species'] for e in p.get('waterEncounters') or [])
        for rod in (p.get('fishing') or {}).values():
            WATER.update(e['species'] for e in rod)
WATER = sorted(WATER - LEGENDARY)



def pool(types, lo, hi, n, rng, favor=()):
    ok = [k for k in WILD if min_level(k) <= hi and max_level(k) >= lo]
    themed = [k for k in ok if set(SPECIES[k]['types']) & set(types)]
    rng.shuffle(themed)
    # Species seen on fewer maps first, so the new routes bring out more of the 200.
    themed.sort(key=lambda k: (k not in favor, USED.get(k, 0) + rng.random() * 2))
    out = themed[:n]
    if len(out) < n:
        rest = [k for k in ok if k not in out]
        rest.sort(key=lambda k: USED.get(k, 0) + rng.random() * 2)
        out += rest[:n - len(out)]
    for k in out:
        USED[k] = USED.get(k, 0) + 1
    return out


WEIGHTS = [20, 20, 10, 10, 10, 10, 5, 5, 4, 4, 1, 1]


def table(species, lo, hi, rng):
    out = []
    for s, w in zip(species, WEIGHTS):
        a = max(lo, min_level(s))
        b = max(a, min(hi, max_level(s)))
        out.append({'species': s, 'min': a, 'max': b, 'weight': w})
    return out


# ---------- the new routes ----------
# kind: route (fields), woods (forest route: dense trees), forest (a forest area), lake (land with a lake or
# river), coast (land on one side, sea on the other), sea (open water with islets).
# at: ('between', A, dir, B) puts the route on the road from A to B; ('branch', parent) hangs it off a free side.
R = [
    dict(id='route14', name='Route 14', kind='route', at=('between', 'route1', 'up', 'route2'), lv=(3, 6),
         types=['Normal', 'Flying', 'Bug'], tr=3, back='field', seed=14),
    dict(id='mossgrove', name='Mossgrove Woods', kind='forest', at=('between', 'route2', 'up', 'stonecrest'), lv=(5, 9),
         types=['Bug', 'Grass', 'Poison'], tr=4, back='forest', size=(24, 44), seed=101,
         style={'grass': {'h': 18, 's': 0.95, 'v': 0.7}, 'tree': {'h': 25, 's': 0.9, 'v': 0.55}, 'path': {'h': -10, 's': 0.8, 'v': 0.7},
                'treeShape': 'pine', 'about': 'Deep old forest: dark moss, shaded pines.'}),
    dict(id='route15', name='Route 15', kind='route', at=('between', 'route3', 'right', 'duskmere'), lv=(11, 14),
         types=['Fighting', 'Ground', 'Normal'], tr=4, back='field', seed=15),
    dict(id='route27', name='Route 27', kind='lake', at=('branch', 'route15'), lv=(12, 15),
         types=['Water', 'Bug', 'Normal'], tr=3, back='field', seed=27),
    dict(id='route16', name='Route 16', kind='woods', at=('between', 'route4', 'up', 'voltara'), lv=(15, 18),
         types=['Grass', 'Bug', 'Ghost'], tr=4, back='forest', seed=16,
         style={'grass': {'h': 30, 's': 0.8, 'v': 0.75}, 'tree': {'h': 40, 's': 0.75, 'v': 0.6}, 'treeShape': 'willow',
                'about': 'Misty willow wood north of Duskmere.'}),
    dict(id='route17', name='Route 17', kind='route', at=('between', 'route5', 'right', 'cindercity'), lv=(19, 22),
         types=['Ground', 'Electric', 'Fire'], tr=4, back='mountain', seed=17, sand=True,
         style={'grass': {'h': -35, 's': 0.7, 'v': 0.95}, 'tree': {'h': -20, 's': 0.7, 'v': 0.85}, 'treeShape': 'rock',
                'about': 'Dry scrub between the desert and the city.'}),
    dict(id='route28', name='Route 28', kind='route', at=('branch', 'route17'), lv=(20, 23),
         types=['Electric', 'Steel', 'Normal'], tr=4, back='field', seed=28, straight=True),
    dict(id='route18', name='Route 18', kind='route', at=('between', 'route6', 'down', 'harrowfield'), lv=(22, 25),
         types=['Fire', 'Rock', 'Ground'], tr=4, back='mountain', seed=18, weather='ash',
         style={'grass': {'h': -55, 's': 0.45, 'v': 0.8}, 'tree': {'h': -40, 's': 0.5, 'v': 0.68},
                'about': 'Ash-dusted slopes below the volcano.'}),
    dict(id='route29', name='Route 29', kind='woods', at=('branch', 'route18'), lv=(23, 26),
         types=['Grass', 'Ghost', 'Dark'], tr=4, back='forest', seed=29,
         style={'grass': {'h': -40, 's': 0.9, 'v': 0.9}, 'tree': {'h': -60, 's': 1.0, 'v': 0.85},
                'about': 'Autumn wood west of the farms.'}),
    dict(id='route19', name='Route 19', kind='woods', at=('between', 'route7', 'right', 'bramblegate'), lv=(26, 29),
         types=['Grass', 'Bug', 'Poison'], tr=5, back='forest', seed=19,
         style={'grass': {'h': 14, 's': 0.95, 'v': 0.76}, 'tree': {'h': 20, 's': 1.0, 'v': 0.62},
                'about': 'Bramble thickets on the way into Bramblegate.'}),
    dict(id='route30', name='Route 30', kind='route', at=('branch', 'route19'), lv=(27, 30),
         types=['Rock', 'Ground', 'Fighting'], tr=4, back='mountain', seed=30, rocks=True,
         style={'grass': {'h': -22, 's': 0.55, 'v': 0.92}, 'tree': {'h': -12, 's': 0.6, 'v': 0.8}, 'treeShape': 'rock',
                'about': 'Rocky hills.'}),
    dict(id='route20', name='Route 20', kind='lake', at=('between', 'route8', 'up', 'skyreach'), lv=(29, 32),
         types=['Water', 'Flying', 'Normal'], tr=5, back='field', seed=20),
    dict(id='elderglen', name='Elderglen Forest', kind='forest', at=('branch', 'route20'), lv=(30, 34),
         types=['Grass', 'Bug', 'Psychic', 'Ghost'], tr=4, back='forest', size=(36, 32), seed=102,
         style={'grass': {'h': 40, 's': 0.75, 'v': 0.7}, 'tree': {'h': 60, 's': 0.7, 'v': 0.55}, 'path': {'h': 250, 's': 0.3, 'v': 0.85},
                'treeShape': 'pine', 'about': 'An ancient forest with blue-green shade.'}),
    dict(id='route21', name='Route 21', kind='coast', at=('between', 'route9', 'right', 'saltmarsh'), lv=(32, 35),
         types=['Water', 'Flying'], tr=5, back='beach', seed=21, weather='rain'),
    dict(id='route22', name='Route 22', kind='lake', at=('between', 'route10', 'up', 'lumenvale'), lv=(35, 38),
         types=['Water', 'Psychic', 'Grass'], tr=5, back='field', seed=22, river=True),
    dict(id='route31', name='Route 31', kind='lake', at=('branch', 'route22'), lv=(36, 39),
         types=['Water', 'Poison', 'Grass'], tr=4, back='night', seed=31, marsh=True,
         style={'grass': {'h': 32, 's': 0.6, 'v': 0.8}, 'tree': {'h': 28, 's': 0.6, 'v': 0.72}, 'water': {'h': -45, 's': 0.55, 'v': 0.78},
                'treeShape': 'willow', 'about': 'A murky marsh.'}),
    dict(id='route23', name='Route 23', kind='sea', at=('between', 'route11', 'right', 'coralhaven'), lv=(38, 41),
         types=['Water', 'Flying'], tr=5, back='beach', seed=23),
    dict(id='route26', name='Route 26', kind='sea', at=('between', 'coralhaven', 'up', 'route12'), lv=(42, 45),
         types=['Water', 'Dragon', 'Ice'], tr=4, back='beach', seed=26, waterfall=True),
    dict(id='route24', name='Route 24', kind='sea', at=('branch', 'route26', ['right'], (24, 32)), lv=(42, 45),
         types=['Water', 'Ice'], tr=4, back='beach', seed=24),
    dict(id='route25', name='Route 25', kind='sea', at=('branch', 'route24', ['right']), lv=(43, 46),
         types=['Water', 'Electric'], tr=4, back='beach', seed=25, weather='rain'),
    dict(id='route32', name='Route 32', kind='sea', at=('branch', 'route25', ['down', 'right']), lv=(44, 47),
         types=['Water', 'Poison'], tr=4, back='beach', seed=32),
    dict(id='route33', name='Route 33', kind='sea', at=('branch', 'route32', ['down', 'right']), lv=(46, 49),
         types=['Water', 'Dragon'], tr=4, back='beach', seed=33),
    dict(id='route34', name='Route 34', kind='sea', at=('branch', 'route33', ['right', 'down', 'up']), lv=(48, 52),
         types=['Water', 'Dragon', 'Ice'], tr=4, back='beach', seed=34, weather='rain'),
]
BY_ID = {r['id']: r for r in R}
SEA = {'sea', 'coast'}


def dims(r):
    if 'size' in r:
        return r['size']
    if r['at'][0] == 'between':
        d = r['at'][2]
        return (22, 40) if d in ('up', 'down') else (40, 20)
    return None


# ---------- layout: sizes, openings and connections ----------
# opening: side -> (start index, width, 'land' | 'water')
for r in R:
    r['open'] = {}
    r['conn'] = {}

for r in R:
    if r['at'][0] != 'between':
        continue
    _, a, d, b = r['at']
    w, h = dims(r)
    r['w'], r['h'] = w, h
    old = MAPS[a]['connections'][d]
    assert old['map'] == b, (a, d, b, old)
    r['between'] = [a, d, b, old['offset']]
    span = h if d in ('left', 'right') else w
    for nb, side in ((a, OPP[d]), (b, d)):
        # The neighbour's edge facing us, and where its opening is.
        nside = OPP[side]
        cells = edge_cells(shown_tiles(nb) if nb in MAPS else None, nside) if nb in MAPS else None
        if cells is None:
            continue  # neighbour is a new route; set when that one is laid out
        idx = [i for i, c in enumerate(cells) if c in WALKABLE]
        assert idx and idx == list(range(idx[0], idx[-1] + 1)), (nb, nside, idx)
        width = len(idx)
        start = min(max(idx[0], 3), span - 3 - width)
        if r['kind'] == 'forest':
            start = min(max(idx[0], 6), span - 6 - width)
        r['open'][side] = (start, width, 'land')
        r['conn'][side] = {'map': nb, 'offset': idx[0] - start}
        # Crossing from the neighbour at its index i lands on our start + (i - idx[0]).
        r.setdefault('nbconn', {})[nb] = (nside, start - idx[0])

# Routes between two new maps (none at the moment) would need both set; check every between is complete.
for r in R:
    if r['at'][0] == 'between':
        assert len(r['open']) == 2, r['id']

# Branch sizes: a side route runs away from its parent.
SIDE_LEN = {'route': 40, 'lake': 40, 'woods': 40, 'sea': 40, 'coast': 40}


def all_outdoor():
    """Every outdoor map with its connections, as the region layout will see them."""
    out = {}
    for k, m in MAPS.items():
        if m.get('indoor') or k.startswith('gym') or k == 'league':
            continue
        conns = dict(m.get('connections', {}))
        conns.update(FEATURES['mapPatches'].get(k, {}).get('connections', {}))
        out[k] = {'w': len(m['tiles'][0]), 'h': len(m['tiles']), 'conns': conns}
    r13 = FEATURES['maps']['route13']
    out['route13'] = {'w': len(r13['tiles'][0]), 'h': len(r13['tiles']), 'conns': dict(r13['connections'])}
    return out


def apply_layout(world):
    """Rewires `world` (all_outdoor() form) with the new routes laid out so far."""
    for r in R:
        if 'w' not in r:
            continue
        world[r['id']] = {'w': r['w'], 'h': r['h'], 'conns': dict(r['conn'])}
        if r['at'][0] == 'between':
            for nb, (nside, off) in r['nbconn'].items():
                if nb in world:
                    world[nb]['conns'][nside] = {'map': r['id'], 'offset': off}
    return world


def layout(world):
    pos = {'fernhollow': (0, 0)}
    q = deque(['fernhollow'])
    while q:
        a = q.popleft()
        ax, ay = pos[a]
        A = world[a]
        for d, c in A['conns'].items():
            b = c['map']
            if b not in world or b in pos:
                continue
            B = world[b]
            o = c['offset']
            pos[b] = {'up': (ax - o, ay - B['h']), 'down': (ax - o, ay + A['h']), 'left': (ax - B['w'], ay - o),
                      'right': (ax + A['w'], ay - o)}[d]
            q.append(b)
    rects = {k: (x, y, world[k]['w'], world[k]['h']) for k, (x, y) in pos.items()}
    if 'route13' in rects:
        x, y, w, h = rects['route13']
        rects['battlefrontier'] = (x + w + 6, y + 2, 40, 28)
    return rects


def overlaps(rects, pad=0):
    out = []
    ks = list(rects)
    for i, a in enumerate(ks):
        ax, ay, aw, ah = rects[a]
        for b in ks[i + 1:]:
            bx, by, bw, bh = rects[b]
            if ax < bx + bw + pad and bx < ax + aw + pad and ay < by + bh + pad and by < ay + ah + pad:
                # Maps joined edge to edge touch on purpose.
                out.append((a, b))
    return out


def touching(world):
    pairs = set()
    for k, m in world.items():
        for c in m['conns'].values():
            pairs.add(tuple(sorted((k, c['map']))))
    return pairs


def bad_overlaps():
    world = apply_layout(all_outdoor())
    rects = layout(world)
    touch = touching(world)
    return [p for p in overlaps(rects) if tuple(sorted(p)) not in touch]


assert not bad_overlaps(), bad_overlaps()

for r in R:
    if r['at'][0] != 'branch':
        continue
    parent = BY_ID[r['at'][1]]
    rng = random.Random(r['seed'])
    sides = [s for s in ('down', 'up', 'right', 'left') if s not in parent['open']]
    rng.shuffle(sides)
    if len(r['at']) > 2:
        sides = [s for s in r['at'][2] if s not in parent['open']]
    placed = False
    for side in sides:
        if r['kind'] == 'forest':
            w, h = r['size']
        else:
            w, h = (40, 20) if side in ('left', 'right') else (22, 40)
        pw, ph = parent['w'], parent['h']
        pspan = ph if side in ('left', 'right') else pw
        cspan = h if side in ('left', 'right') else w
        water = r['kind'] in SEA and parent['kind'] in SEA
        width = 6 if water else 2
        # Keep clear of the parent's other openings along the same edge.
        lo_, hi_ = r['at'][3] if len(r['at']) > 3 else (4, pspan - 4 - width)
        pstart = rng.randint(lo_, hi_)
        cstart = min(max(pstart, 4), cspan - 4 - width)
        r['w'], r['h'] = w, h
        kind = 'water' if water else 'land'
        parent['open'][side] = (pstart, width, kind)
        parent['conn'][side] = {'map': r['id'], 'offset': cstart - pstart}
        r['open'][OPP[side]] = (cstart, width, kind)
        r['conn'][OPP[side]] = {'map': parent['id'], 'offset': pstart - cstart}
        if not bad_overlaps():
            placed = True
            break
        del parent['open'][side], parent['conn'][side]
        r['open'].clear()
        r['conn'].clear()
        del r['w'], r['h']
    assert placed, 'no room for ' + r['id']


# A dead-end side route still leads somewhere: across to its far end, by way of a spot in the middle.
for r in R:
    if len(r['open']) == 1:
        side = next(iter(r['open']))
        rng = random.Random(r['seed'] * 7)
        fx, fy = {'up': (r['w'] // 2, r['h'] - 4), 'down': (r['w'] // 2, 3), 'left': (r['w'] - 5, r['h'] // 2),
                  'right': (3, r['h'] // 2)}[side]
        fx += rng.randint(-4, 4) if side in ('up', 'down') else 0
        fy += rng.randint(-4, 4) if side in ('left', 'right') else 0
        r['goals'] = [(min(max(fx, 3), r['w'] - 5), min(max(fy, 3), r['h'] - 5)),
                      (rng.randint(6, r['w'] - 8), rng.randint(5, r['h'] - 7))]


# ---------- grids ----------
class Grid:
    def __init__(self, w, h, fill):
        self.w, self.h = w, h
        self.g = [[fill] * w for _ in range(h)]

    def get(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.g[y][x]
        return '#'

    def set(self, x, y, ch):
        if 0 < x < self.w - 1 and 0 < y < self.h - 1:
            self.g[y][x] = ch

    def rows(self):
        return [''.join(r) for r in self.g]


def edge_xy(side, i, w, h):
    return {'up': (i, 0), 'down': (i, h - 1), 'left': (0, i), 'right': (w - 1, i)}[side]


def inward(side):
    return {'up': (0, 1), 'down': (0, -1), 'left': (1, 0), 'right': (-1, 0)}[side]


def passable(t, surf):
    return t in WALKABLE or (surf and t in '~W')


def bfs(G, starts, surf, blocked=frozenset()):
    seen = set()
    q = deque()
    for s in starts:
        if s not in blocked:
            seen.add(s)
            q.append(s)
    while q:
        x, y = q.popleft()
        for dx, dy in DX.values():
            nx, ny = x + dx, y + dy
            t = G.get(nx, ny)
            if t == 'v' and dy == 1:
                ny += 1
                t = G.get(nx, ny)
            # A waterfall is climbed upwards only.
            if t == 'W' and dy != -1:
                continue
            if G.get(x, y) == 'W' and dy != -1 and not passable(t, surf):
                continue
            if (nx, ny) in seen or (nx, ny) in blocked or not passable(t, surf):
                continue
            seen.add((nx, ny))
            q.append((nx, ny))
    return seen


def opening_cells(r, side):
    start, width, _ = r['open'][side]
    return [edge_xy(side, start + i, r['w'], r['h']) for i in range(width)]


def can_surf(r):
    """Surf works from the fifth badge (Bramblegate); earlier routes must be crossable on foot."""
    return r['kind'] in SEA or r['lv'][0] >= 29


def targets(r):
    """What must stay joined: each opening, and on a dead-end side route the spots it leads to."""
    out = [(s, opening_cells(r, s)) for s in r['open']]
    out += [('goal', [g]) for g in r.get('goals', [])]
    return out


def all_connected(r, G, blocked=frozenset()):
    """Every opening and goal reaches every other one (ledges and waterfalls are one way)."""
    surf = can_surf(r)
    ts = targets(r)
    for s, cells in ts:
        seen = bfs(G, cells, surf, blocked)
        for t, other in ts:
            if other is not cells and not any(c in seen for c in other):
                # Route 26: the waterfall goes up only, so only bottom-to-top must hold.
                if r.get('waterfall') and s == 'up':
                    continue
                return False
    return True


def reachable(r, G, blocked=frozenset()):
    surf = can_surf(r)
    starts = [c for s in r['open'] for c in opening_cells(r, s)]
    return bfs(G, starts, surf, blocked)


def line(G, a, b, ch, width, rng, keep=''):
    """An L-shaped band from a to b."""
    (x0, y0), (x1, y1) = a, b
    pts = []
    if rng.random() < 0.5:
        pts = [(x, y0) for x in range(min(x0, x1), max(x0, x1) + 1)] + [(x1, y) for y in range(min(y0, y1), max(y0, y1) + 1)]
    else:
        pts = [(x0, y) for y in range(min(y0, y1), max(y0, y1) + 1)] + [(x, y1) for x in range(min(x0, x1), max(x0, x1) + 1)]
    for x, y in pts:
        for dx in range(width):
            for dy in range(width):
                if G.get(x + dx, y + dy) not in keep:
                    G.set(x + dx, y + dy, ch)


def open_edges(r, G):
    """Edge cells of each opening, plus a short run inward, in the opening's ground."""
    for side, (start, width, kind) in r['open'].items():
        ch = '~' if kind == 'water' else ('a' if r['kind'] == 'sea' else '=')
        ix, iy = inward(side)
        for i in range(width):
            x, y = edge_xy(side, start + i, r['w'], r['h'])
            for k in range(4 if kind == 'land' else 3):
                G.g[y + iy * k][x + ix * k] = ch


def mouth(r, side):
    """A point a few tiles inside the opening, on its first cell."""
    start, width, _ = r['open'][side]
    x, y = edge_xy(side, start, r['w'], r['h'])
    ix, iy = inward(side)
    return x + ix * 3, y + iy * 3


def blob(G, cx, cy, rw, rh, ch, rng, ok):
    for y in range(cy - rh, cy + rh + 1):
        for x in range(cx - rw, cx + rw + 1):
            if ((x - cx) / (rw + 0.5)) ** 2 + ((y - cy) / (rh + 0.5)) ** 2 <= 1 + rng.random() * 0.3:
                if ok(G.get(x, y)) and 0 < x < G.w - 1 and 0 < y < G.h - 1:
                    G.set(x, y, ch)


def near(G, x, y, chars, d=1):
    return any(G.get(x + a, y + b) in chars for a in range(-d, d + 1) for b in range(-d, d + 1))


def road(r, G, rng, ch='=', width=2):
    pts = [mouth(r, s) for s in r['open']] + r.get('goals', [])
    hub = (rng.randint(5, r['w'] - 7), rng.randint(5, r['h'] - 7))
    first = pts[0]
    for p in pts[1:]:
        if not r.get('straight'):
            mid = (rng.randint(4, r['w'] - 6), rng.randint(4, r['h'] - 6))
            line(G, first, mid, ch, width, rng)
            line(G, mid, p, ch, width, rng)
        else:
            line(G, first, p, ch, width, rng)
    if len(pts) > 2:
        line(G, hub, pts[0], ch, width, rng)


def scatter_land(r, G, rng, trees, grass, flowers):
    def try_put(fn):
        snap = [row[:] for row in G.g]
        fn()
        if not all_connected(r, G):
            G.g = snap

    for _ in range(trees):
        cx, cy = rng.randint(2, G.w - 3), rng.randint(2, G.h - 3)
        try_put(lambda: blob(G, cx, cy, rng.randint(1, 3), rng.randint(1, 3), '#', rng,
                             lambda t: t == '.'))
    for _ in range(grass):
        cx, cy = rng.randint(2, G.w - 3), rng.randint(2, G.h - 3)
        blob(G, cx, cy, rng.randint(2, 4), rng.randint(1, 3), ',', rng, lambda t: t in '.')
    for _ in range(flowers):
        x, y = rng.randint(1, G.w - 2), rng.randint(1, G.h - 2)
        if G.get(x, y) == '.':
            G.set(x, y, 'F')


def ledges(r, G, rng, n):
    for _ in range(n * 6):
        if n <= 0:
            break
        y = rng.randint(4, G.h - 5)
        x0 = rng.randint(2, G.w - 10)
        ln = rng.randint(4, 8)
        cells = [(x, y) for x in range(x0, x0 + ln)]
        if not all(G.get(x, y) in '.,' and G.get(x, y + 1) in '.,F' and G.get(x, y - 1) in '.,F' for x, y in cells):
            continue
        snap = [row[:] for row in G.g]
        for x, yy in cells:
            G.set(x, yy, 'v')
        if all_connected(r, G):
            n -= 1
        else:
            G.g = snap


def gen_route(r, rng):
    G = Grid(r['w'], r['h'], '.')
    for x in range(G.w):
        G.g[0][x] = G.g[G.h - 1][x] = '#'
    for y in range(G.h):
        G.g[y][0] = G.g[y][G.w - 1] = '#'
    open_edges(r, G)
    road(r, G, rng)
    if r.get('sand'):
        for _ in range(5):
            blob(G, rng.randint(3, G.w - 4), rng.randint(3, G.h - 4), rng.randint(2, 4), rng.randint(1, 3), 'a', rng,
                 lambda t: t == '.')
    dense = r['kind'] == 'woods'
    area = G.w * G.h
    scatter_land(r, G, rng, trees=area // (35 if dense else 70), grass=area // 90 + 3, flowers=area // 60)
    if dense:
        # Thicken the woods: trees fill most of what isn't road, grass or a clearing.
        for y in range(1, G.h - 1):
            for x in range(1, G.w - 1):
                if G.g[y][x] == '.' and not near(G, x, y, '=', 2) and rng.random() < 0.55:
                    snap = G.g[y][x]
                    G.g[y][x] = '#'
                    if not all_connected(r, G):
                        G.g[y][x] = snap
    if r['h'] > r['w']:
        ledges(r, G, rng, 2)
    if r.get('rocks'):
        for _ in range(6):
            x, y = rng.randint(2, G.w - 3), rng.randint(2, G.h - 3)
            if G.get(x, y) == '.':
                G.set(x, y, 'R')
                if not all_connected(r, G):
                    G.set(x, y, '.')
    return G


def gen_forest(r, rng):
    G = Grid(r['w'], r['h'], '#')
    open_edges(r, G)
    pts = [mouth(r, s) for s in r['open']] + r.get('goals', [])
    # A winding trail through several clearings.
    # One clearing in each sixth of the forest, visited nearest first from the way in.
    cols, rows_ = (2, 3) if r['h'] >= r['w'] else (3, 2)
    glades = []
    for i in range(cols):
        for j in range(rows_):
            x0, x1 = 4 + (G.w - 8) * i // cols, 4 + (G.w - 8) * (i + 1) // cols - 1
            y0, y1 = 4 + (G.h - 8) * j // rows_, 4 + (G.h - 8) * (j + 1) // rows_ - 1
            glades.append((rng.randint(x0, x1), rng.randint(y0, y1)))
    stops = [pts[0]]
    while glades:
        cx, cy = stops[-1]
        nxt = min(glades, key=lambda p: abs(p[0] - cx) + abs(p[1] - cy))
        glades.remove(nxt)
        stops.append(nxt)
    stops += pts[1:]
    for a, b in zip(stops, stops[1:]):
        line(G, a, b, '.', 2, rng)
    for p in stops[1:-1]:
        blob(G, p[0], p[1], rng.randint(3, 4), rng.randint(2, 3), '.', rng, lambda t: True)
        blob(G, p[0] + rng.randint(-1, 1), p[1] + rng.randint(-1, 1), rng.randint(2, 3), rng.randint(1, 2), ',', rng,
             lambda t: t == '.')
    # Side glades closed off by Cut trees.
    for _ in range(2):
        for _try in range(40):
            x, y = rng.randint(3, G.w - 4), rng.randint(3, G.h - 4)
            if G.get(x, y) != '#' or not near(G, x, y, '.', 1):
                continue
            d = rng.choice(list(DX.values()))
            gx, gy = x + d[0] * 3, y + d[1] * 3
            if not (3 <= gx < G.w - 3 and 3 <= gy < G.h - 3) or near(G, gx, gy, '.,', 2):
                continue
            G.set(x, y, 'T')
            for k in (1, 2):
                G.set(x + d[0] * k, y + d[1] * k, '.')
            blob(G, gx, gy, 1, 1, '.', rng, lambda t: t == '#')
            r.setdefault('glades', []).append((gx, gy))
            break
    for _ in range(G.w * G.h // 120):
        x, y = rng.randint(1, G.w - 2), rng.randint(1, G.h - 2)
        if G.get(x, y) == '.' and not near(G, x, y, 'T', 2):
            G.set(x, y, 'F')
    for side in r['open']:
        for (x, y) in opening_cells(r, side):
            G.g[y][x] = '='
    return G


def gen_lake(r, rng):
    G = gen_route(r, rng)
    if r.get('river'):
        # A river right across the road: Surf to cross.
        horizontal = r['h'] > r['w']
        c = (G.h if horizontal else G.w) // 2 + rng.randint(-3, 3)
        for k in range(1, (G.w if horizontal else G.h) - 1):
            wob = int(1.5 * ((k * 7919) % 5 - 2) / 2)
            for dd in range(3):
                x, y = (k, c + dd + wob) if horizontal else (c + dd + wob, k)
                G.set(x, y, '~')
    for _ in range(3 if r.get('marsh') else 1):
        cx, cy = rng.randint(6, G.w - 7), rng.randint(6, G.h - 7)
        blob(G, cx, cy, rng.randint(3, 6), rng.randint(2, 4), '~', rng, lambda t: t in '.,F#a')
    if r.get('marsh'):
        for y in range(1, G.h - 1):
            for x in range(1, G.w - 1):
                if G.g[y][x] == '.' and near(G, x, y, '~', 1) and rng.random() < 0.6:
                    G.g[y][x] = ','
    # Water must never sit on an opening edge.
    for side in r['open']:
        for i, (x, y) in enumerate(opening_cells(r, side)):
            ix, iy = inward(side)
            for k in range(2):
                G.g[y + iy * k][x + ix * k] = '='
    assert all_connected(r, G), r['id']
    return G


def gen_sea(r, rng):
    G = Grid(r['w'], r['h'], '~')
    # Edges with a connection are closed except at the opening.
    for side in r['open']:
        n = r['w'] if side in ('up', 'down') else r['h']
        for i in range(n):
            x, y = edge_xy(side, i, r['w'], r['h'])
            G.g[y][x] = '#'
    for side, (start, width, kind) in r['open'].items():
        if kind == 'land':
            # A beach where the land route or town meets the sea.
            x, y = mouth(r, side)
            bx, by = (x, y)
            blob(G, bx, by, 5, 4, 'a', rng, lambda t: t == '~')
            line(G, edge_xy(side, start, r['w'], r['h']), (x, y), '=', 2, rng)
            for k in range(-1, width + 1):
                ex, ey = edge_xy(side, start + k, r['w'], r['h'])
                ix, iy = inward(side)
                for d in range(1, 5):
                    G.set(ex + ix * d, ey + iy * d, 'a' if k in (-1, width) else '=')
    for side, (start, width, kind) in r['open'].items():
        for (x, y) in opening_cells(r, side):
            G.g[y][x] = '=' if kind == 'land' else '~'
    if r.get('waterfall'):
        # A cliff across the middle with a waterfall to climb (Waterfall, the eighth badge).
        cy = r['h'] // 2
        wx = rng.randint(6, r['w'] - 8)
        for x in range(r['w']):
            G.g[cy][x] = '#'
            G.g[cy - 1][x] = '#'
        G.g[cy][wx] = G.g[cy - 1][wx] = 'W'
        G.g[cy][wx + 1] = G.g[cy - 1][wx + 1] = 'W'
    # Islets: sand banks, a few with trees and tall grass.
    for _ in range(r['w'] * r['h'] // 110):
        cx, cy = rng.randint(4, r['w'] - 5), rng.randint(4, r['h'] - 5)
        if near(G, cx, cy, '=#W', 3):
            continue
        rw, rh = rng.randint(1, 4), rng.randint(1, 2)
        blob(G, cx, cy, rw, rh, 'a', rng, lambda t: t == '~')
        if rw >= 3:
            blob(G, cx, cy, rw - 2, max(0, rh - 1), ',', rng, lambda t: t == 'a')
            if rng.random() < 0.5:
                G.set(cx + rw - 1, cy - rh + 1, '#')
    assert all_connected(r, G), r['id']
    return G


def gen_coast(r, rng):
    # Land comes in from the left (Route 9), the sea opens to Saltmarsh on the right.
    G = gen_route(r, rng)
    shore = r['w'] // 3
    for y in range(1, G.h - 1):
        edge = shore + int(2 * ((y * 31) % 5) / 4)
        for x in range(edge, G.w - 1):
            G.g[y][x] = '~'
        G.g[y][edge - 1] = 'a'
        if G.g[y][edge - 2] in '.,F#':
            G.g[y][edge - 2] = 'a'
    # Saltmarsh's side: a pier of sand and road to the opening.
    side = 'right'
    start, width, _ = r['open'][side]
    for k in range(-2, width + 2):
        for d in range(0, 6):
            x, y = r['w'] - 1 - d, start + k
            G.g[y][x] = '=' if 0 <= k < width and d < 5 else ('a' if d < 6 and 0 < y < r['h'] - 1 else G.g[y][x])
    for y in range(G.h):
        if not (start <= y < start + width):
            G.g[y][r['w'] - 1] = '#'
    for _ in range(4):
        cx, cy = rng.randint(shore + 4, r['w'] - 8), rng.randint(3, r['h'] - 4)
        blob(G, cx, cy, rng.randint(1, 3), 1, 'a', rng, lambda t: t == '~')
    assert all_connected(r, G), r['id']
    return G


GEN = {'route': gen_route, 'woods': gen_route, 'forest': gen_forest, 'lake': gen_lake, 'sea': gen_sea, 'coast': gen_coast}

# ---------- trainers, items, signs ----------
NAMES = ['Alden', 'Brisa', 'Corin', 'Dena', 'Ebon', 'Fia', 'Garrick', 'Hale', 'Ines', 'Joss', 'Kira', 'Lio', 'Maren', 'Nico',
         'Odile', 'Pax', 'Quill', 'Rhea', 'Soren', 'Tamsin', 'Ulla', 'Vash', 'Wren', 'Xeno', 'Yara', 'Zed', 'Arlo', 'Bea',
         'Cass', 'Dov', 'Elsa', 'Finn', 'Greta', 'Hugo', 'Isla', 'Jory', 'Kael', 'Lumi', 'Milo', 'Nell', 'Orrin', 'Pia',
         'Rafe', 'Sela', 'Toby', 'Uma', 'Vito', 'Wade', 'Yuki', 'Zora', 'Bram', 'Cleo', 'Dash', 'Edda', 'Fern', 'Gil']
CLASSES = {
    'route': [('Youngster', 'boy'), ('Lass', 'girl'), ('Hiker', 'hiker'), ('Bird Keeper', 'bird'), ('Black Belt', 'blackbelt'),
              ('Battle Girl', 'battlegirl'), ('Camper', 'boy'), ('Picnicker', 'girl'), ('Gentleman', 'gentleman')],
    'woods': [('Bug Catcher', 'boy'), ('Aroma Lady', 'beauty'), ('Hex Maniac', 'hex'), ('Picnicker', 'girl'), ('Camper', 'boy'),
              ('Ranger', 'ace')],
    'lake': [('Fisherman', 'old'), ('Swimmer', 'swimmer'), ('Lass', 'girl'), ('Bird Keeper', 'bird'), ('Psychic', 'psychic'),
             ('Ace Trainer', 'ace')],
    'sea': [('Swimmer', 'swimmer'), ('Swimmer', 'swimmer'), ('Fisherman', 'old'), ('Sailor', 'blackbelt'), ('Bird Keeper', 'bird'),
            ('Ace Trainer', 'ace')],
}
CLASSES['forest'] = CLASSES['woods']
CLASSES['coast'] = CLASSES['sea']
LINES = {
    'route': [('Hey! You look like you want a battle!', 'Hmph. You got lucky.', 'There are more trainers up the road.'),
              ('This road is my training ground!', 'Well, I tried.', 'Tall grass hides the most creatures.'),
              ('I won\'t let you pass that easily!', 'Fine, go ahead.', 'A ledge is a one-way shortcut. Jump down, but never up.'),
              ('Let\'s see how strong your team is!', 'Strong indeed!', 'Rest at a Lodge before you go much farther.')],
    'woods': [('The woods are full of bugs! Battle me!', 'Squashed...', 'Some trees can be cut down to reach hidden glades.'),
              ('Shh... you scared off my creature! Now you battle me.', 'I lost the trail too...', 'Bug creatures love the shade here.'),
              ('Lost in the trees? Me too! Let\'s battle!', 'I\'m still lost.', 'Follow the path and you\'ll find the exit.'),
              ('The forest spirits sent you to me...', 'The spirits are pleased.', 'Ghosts drift between these old trunks.')],
    'lake': [('Nothing\'s biting. Battle me instead!', 'Reeled in...', 'Fishing rods catch creatures that never leave the water.'),
             ('The water here is perfect for training!', 'Splashed!', 'Surf lets you cross the water.'),
             ('I can see the future... and it holds a battle!', 'I did not see that coming.', 'Calm water hides strong creatures.')],
    'sea': [('The open sea is my home!', 'I\'m all washed up...', 'Rest on the islets if your team gets tired.'),
            ('Ahoy! Fancy a battle, landlubber?', 'Sunk!', 'Keep surfing and you\'ll find islands no map shows.'),
            ('Swim with me, battle with me!', 'You\'re faster than the current.', 'Deep water creatures get stronger the farther out you go.')],
}
LINES['forest'] = LINES['woods']
LINES['coast'] = LINES['sea']
ITEMS_BY_LEVEL = [
    (10, ['potion', 'orb', 'antidote', 'repel', 'oranBerry', 'parlyzHeal']),
    (20, ['superPotion', 'greatOrb', 'escapeRope', 'ether', 'awakening', 'xAttack', 'nestOrb']),
    (30, ['superPotion', 'greatOrb', 'superRepel', 'netOrb', 'revive', 'fullHeal', 'ppUp', 'timerOrb']),
    (40, ['hyperPotion', 'ultraOrb', 'revive', 'maxEther', 'elixir', 'diveOrb', 'repeatOrb', 'nugget']),
    (99, ['maxPotion', 'ultraOrb', 'fullRestore', 'maxRevive', 'maxElixir', 'rareCandy', 'ppUp', 'starPiece']),
]
HIDDEN_ITEMS = ['heartScale', 'pearl', 'stardust', 'nugget', 'bigPearl', 'starPiece', 'rareCandy', 'ppUp']
FOREST_FINDS = {'mossgrove': ['miracleSeed', 'silverPowder'], 'elderglen': ['leafStone', 'spellTag']}
ALL_ITEMS = set(load('items')) | set(FEATURES['items'])


def items_for(lv):
    return next(its for cap, its in ITEMS_BY_LEVEL if lv <= cap)


def free_tiles(r, G, taken, tiles):
    out = []
    for y in range(1, G.h - 1):
        for x in range(1, G.w - 1):
            if G.get(x, y) in tiles and (x, y) not in taken:
                out.append((x, y))
    return out


def blocks_nothing(r, G, taken, extra):
    """Putting something on `extra` keeps every opening joined, and everything already placed still reachable."""
    if not all_connected(r, G, frozenset(taken | {extra})):
        return False
    before = reachable(r, G, frozenset(taken))
    after = reachable(r, G, frozenset(taken | {extra}))
    adj = lambda seen, t: any((t[0] + dx, t[1] + dy) in seen for dx, dy in DX.values())
    return adj(after, extra) and all(adj(after, t) for t in taken if adj(before, t))


def place_trainers(r, G, rng, lv, sp):
    out = []
    taken = set()
    classes = CLASSES[r['kind']]
    lines = LINES[r['kind']]
    water_map = r['kind'] in SEA
    road = '~' if water_map else ('.,' if r['kind'] == 'forest' else '=')
    cands = free_tiles(r, G, taken, 'a' if water_map else '.,')
    rng.shuffle(cands)
    names = NAMES[:]
    rng.shuffle(names)
    for x, y in cands:
        if len(out) >= r['tr']:
            break
        if any(abs(x - tx) + abs(y - ty) < 5 for tx, ty in taken):
            continue
        if any(abs(x - ex) + abs(y - ey) < 6 for s in r['open'] for ex, ey in opening_cells(r, s)):
            continue
        # Face a lane the player will use: road on land, open water at sea.
        best = None
        for d, (dx, dy) in DX.items():
            run = 0
            for i in range(1, 5):
                t = G.get(x + dx * i, y + dy * i)
                if t in WALKABLE or t == '~':
                    run += 1
                else:
                    break
            if run >= 2 and any(G.get(x + dx * i, y + dy * i) in road for i in range(1, run + 1)):
                best = (d, run)
                break
        if not best or not blocks_nothing(r, G, taken, (x, y)):
            continue
        taken.add((x, y))
        cls, pal = classes[len(out) % len(classes)] if len(out) < len(classes) else rng.choice(classes)
        name = names.pop()
        n = rng.choice([1, 2, 2, 3]) if lv[0] > 8 else rng.choice([1, 2])
        party = []
        for i in range(n):
            s = rng.choice(sp[:8])
            lvl = max(min_level(s), min(max_level(s), rng.randint(lv[0], lv[1] + 1)))
            party.append([s, lvl])
        double = False
        if len(out) == 2 and r['tr'] >= 4 and not water_map:
            cls, pal, name = 'Twins', 'girl', '%s & %s' % (name, names.pop())
            double = True
            party = [[s, max(min_level(s), lv[1])] for s in rng.sample(sp[:8], 2)]
        intro, defeat, after = lines[len(out) % len(lines)]
        out.append({'id': '%s_t%d' % (r['id'], len(out)), 'name': '%s %s' % (cls, name), 'palette': pal, 'x': x, 'y': y,
                    'dir': best[0], 'sight': min(4, best[1]), 'pay': 12 + lv[0] * 4 // 5, 'party': party, 'double': double,
                    'intro': intro, 'defeat': defeat, 'after': after})
    assert len(out) >= max(2, r['tr'] - 1), (r['id'], len(out))
    return out, taken


def place_items(r, G, rng, lv, taken):
    out = []
    pool = items_for(lv[1])
    picks = rng.sample(pool, 2)
    spots = []
    # Glades behind Cut trees first, then dead-end corners.
    for gx, gy in r.get('glades', []):
        if G.get(gx, gy) == '.':
            spots.append((gx, gy))
    tiles = 'a' if r['kind'] in SEA else '.'
    cands = free_tiles(r, G, taken, tiles)
    cands.sort(key=lambda p: (-sum(1 for dx, dy in DX.values() if not passable(G.get(p[0] + dx, p[1] + dy), False)),
                              rng.random()))
    spots += cands
    seen = set()
    finds = FOREST_FINDS.get(r['id'], [])
    want = picks + finds
    for i, it in enumerate(want + ['__hidden']):
        for x, y in spots:
            if (x, y) in taken or (x, y) in seen or any(abs(x - a) + abs(y - b) < 4 for a, b in seen):
                continue
            if (x, y) in r.get('glades', []) or blocks_nothing(r, G, taken, (x, y)):
                hidden = it == '__hidden'
                hid = HIDDEN_ITEMS[:3] if lv[1] < 20 else HIDDEN_ITEMS
                item = hid[r['seed'] % len(hid)] if hidden else it
                assert item in ALL_ITEMS, item
                out.append({'id': '%s_i%d' % (r['id'], len(out) + 1), 'x': x, 'y': y, 'item': item, 'count': 1,
                            'hidden': hidden})
                seen.add((x, y))
                if not hidden:
                    taken.add((x, y))
                break
    return out


def place_sign(r, G, taken, names):
    side = next(iter(r['open']))
    sx, sy = mouth(r, side)
    for d in range(1, 6):
        for dx, dy in [(d, 0), (-d, 0), (0, d), (0, -d), (d, d), (-d, -d), (d, -d), (-d, d)]:
            x, y = sx + dx, sy + dy
            if G.get(x, y) in '.a,#' and (x, y) not in taken and near(G, x, y, '=', 1):
                snap = G.get(x, y)
                G.set(x, y, 'S')
                if blocks_nothing(r, G, set(taken), (x, y)) and all_connected(r, G):
                    return {'%d,%d' % (x, y): [r['name'].upper(), names]}
                G.set(x, y, snap)
    return {}


def place_name(mid):
    if mid in MAPS:
        return MAPS[mid]['name']
    return BY_ID[mid]['name']


# ---------- build ----------
new_maps = {}
for r in R:
    rng = random.Random(r['seed'])
    G = GEN[r['kind']](r, rng)
    lv = r['lv']
    sp = pool(r['types'], lv[0], lv[1], 10 if r['kind'] in SEA else 11, rng)
    trainers, taken = place_trainers(r, G, rng, lv, sp)
    items = place_items(r, G, rng, lv, set(taken))
    ends = [place_name(c['map']) for c in r['conn'].values()]
    sign = place_sign(r, G, taken | {(i['x'], i['y']) for i in items}, ' <-> '.join(ends))
    rows = G.rows()
    m = {'id': r['id'], 'name': r['name'], 'tiles': rows, 'connections': r['conn'], 'trainers': trainers, 'signs': sign,
         'items': items, 'route': int(r['id'][5:]) if r['id'].startswith('route') else 0,
         'levels': list(lv), 'backdrop': r['back'], 'generatedBy': TAG}
    if not m['route']:
        del m['route']
    if r['kind'] in ('sea', 'coast'):
        m['sea'] = True
    # Land encounters need tall grass; sea routes get theirs from the water (build_features adds those).
    has_grass = any(',' in row for row in rows)
    m['encounterRate'] = 25 if r['kind'] == 'forest' else 22
    m['encounters'] = table(sp, lv[0], lv[1], rng) if has_grass else []
    if any('~' in row for row in rows):
        ok = [k for k in WATER if min_level(k) <= lv[1] and max_level(k) >= lv[0]]
        ok.sort(key=lambda k: (not set(SPECIES[k]['types']) & set(r['types']) - {'Water'}, USED.get(k, 0) + rng.random() * 3))
        m['waterEncounters'] = [dict(e, weight=w) for e, w in zip(table(ok[:5], max(5, lv[0] - 3), lv[1], rng), [40, 25, 15, 12, 8])]
        for k in ok[:5]:
            USED[k] = USED.get(k, 0) + 1
    if r.get('weather'):
        m['weather'] = r['weather']
    if 'between' in r:
        m['between'] = r['between']
    new_maps[r['id']] = m
    if 'style' in r:
        s = dict(r['style'])
        s['generatedBy'] = TAG
        STYLES[r['id']] = s

# Point the old maps at the new routes.
for r in R:
    if 'between' in r:
        for nb, (nside, off) in r['nbconn'].items():
            MAPS[nb]['connections'][nside] = {'map': r['id'], 'offset': off}
MAPS.update(new_maps)

# ---------- checks ----------
errors = []
for k, m in new_maps.items():
    rows = m['tiles']
    h, w = len(rows), len(rows[0])
    for side, c in m['connections'].items():
        other = shown_tiles(c['map']) if c['map'] not in new_maps else new_maps[c['map']]['tiles']
        nh, nw = len(other), len(other[0])
        back = MAPS[c['map']]['connections'].get(OPP[side])
        if not back or back['map'] != k or back['offset'] != -c['offset']:
            errors.append('%s %s not mirrored' % (k, side))
        for i in range(w if side in ('up', 'down') else h):
            ex, ey = edge_xy(side, i, w, h)
            t = rows[ey][ex]
            if t not in WALKABLE and t != '~':
                continue
            if side in ('up', 'down'):
                nx, ny = ex + c['offset'], (nh - 1 if side == 'up' else 0)
            else:
                nx, ny = (nw - 1 if side == 'left' else 0), ey + c['offset']
            u = other[ny][nx] if 0 <= ny < nh and 0 <= nx < nw else '#'
            if (t in WALKABLE) != (u in WALKABLE) or (t == '~') != (u == '~'):
                errors.append('%s leaving %s at %d,%d (%s) lands on %r in %s' % (k, side, ex, ey, t, u, c['map']))
    # And the way back from the old map.
    for t in m['trainers']:
        if rows[t['y']][t['x']] not in WALKABLE:
            errors.append('%s trainer on %r' % (k, rows[t['y']][t['x']]))
    for it in m['items']:
        if rows[it['y']][it['x']] not in WALKABLE:
            errors.append('%s item on %r' % (k, rows[it['y']][it['x']]))
for k, m in MAPS.items():
    if k in new_maps:
        continue
    for side, c in m.get('connections', {}).items():
        if c['map'] not in new_maps:
            continue
        rows = shown_tiles(k)
        other = new_maps[c['map']]['tiles']
        h, w, nh, nw = len(rows), len(rows[0]), len(other), len(other[0])
        for i in range(w if side in ('up', 'down') else h):
            ex, ey = edge_xy(side, i, w, h)
            if rows[ey][ex] not in WALKABLE:
                continue
            if side in ('up', 'down'):
                nx, ny = ex + c['offset'], (nh - 1 if side == 'up' else 0)
            else:
                nx, ny = (nw - 1 if side == 'left' else 0), ey + c['offset']
            u = other[ny][nx] if 0 <= ny < nh and 0 <= nx < nw else '#'
            if u not in WALKABLE:
                errors.append('%s leaving %s at %d,%d lands on %r in %s' % (k, side, ex, ey, u, c['map']))
if bad_overlaps():
    errors.append('region overlaps: %s' % bad_overlaps())
if errors:
    print('\n'.join(errors))
    sys.exit(1)

json.dump(MAPS, open(os.path.join(ROOT, 'data/maps.json'), 'w'), indent=1)
with open(os.path.join(ROOT, 'data/town_styles.json'), 'w') as f:
    f.write('{\n' + ',\n'.join(' %s: %s' % (json.dumps(k), json.dumps(v)) for k, v in STYLES.items()) + '\n}\n')
routes = sum(1 for m in MAPS.values() if m.get('route')) + 1  # + Route 13 (features)
print('routes: %d new maps, %d routes in all' % (len(new_maps), routes))
for k, m in new_maps.items():
    print('  %-10s %-18s %2dx%-2d lv %d-%d, %d wild, %d trainers, %d items, %s' % (
        k, m['name'], len(m['tiles'][0]), len(m['tiles']), m['levels'][0], m['levels'][1], len(m['encounters']),
        len(m['trainers']), len(m['items']), ', '.join('%s:%s' % (d, c['map']) for d, c in m['connections'].items())))
