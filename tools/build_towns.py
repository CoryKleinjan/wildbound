#!/usr/bin/env python3
"""Town layout edits on data/maps.json: rebuilds Cinder City as the big city (with the department
store) and plants each town's signature trees on open grass.

Run from the repo root, then rebuild what depends on the maps:
python3 tools/build_towns.py && python3 tools/build_interiors.py && python3 tools/build_story.py
(The tree planting skips towns that already have it, so running this twice is safe.)
"""
import json
import os

ROOT = os.path.join(os.path.dirname(__file__), '..')
PATH = os.path.join(ROOT, 'data/maps.json')
MAPS = json.load(open(PATH))


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.g = [['.'] * w for _ in range(h)]
        for x in range(w):
            self.g[0][x] = self.g[h - 1][x] = '#'
        for y in range(h):
            self.g[y][0] = self.g[y][w - 1] = '#'

    def fill(self, x, y, w, h, ch):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.g[yy][xx] = ch

    def put(self, x, y, ch):
        self.g[y][x] = ch

    def building(self, x, y, w, roof_h, roof, door_x, door):
        """Roof rows from y, then one wall row with the door. Returns the door position."""
        self.fill(x, y, w, roof_h, roof)
        self.fill(x, y + roof_h, w, 1, 'w')
        self.put(door_x, y + roof_h, door)
        return door_x, y + roof_h

    def rows(self):
        return [''.join(r) for r in self.g]


def build_city():
    """Cinder City, 36x30. The left road (rows 10-11) and the south road (columns 12-13) stay where
    the old map had them so Route 5 and Route 6 still line up, and the gym door stays at 5,16."""
    old = MAPS['cindercity']
    c = Canvas(36, 30)
    # Avenues.
    c.fill(0, 10, 35, 2, '=')       # west gate to the east side
    c.fill(12, 1, 2, 29, '=')       # north to the south gate
    c.fill(1, 21, 34, 2, '=')       # lower avenue
    c.fill(26, 1, 2, 20, '=')       # east street
    # Department store: the big blue building on the north side.
    store = c.building(15, 2, 10, 4, 'b', 19, 'm')
    c.fill(19, 7, 2, 3, '=')
    c.put(20, 6, 'w')
    c.put(18, 7, 'S')
    # Rest Lodge.
    lodge = c.building(29, 3, 5, 2, 'p', 31, 'l')
    c.fill(31, 6, 1, 4, '=')
    # Houses.
    h1 = c.building(2, 2, 5, 2, 'r', 4, 'h')
    c.fill(4, 5, 1, 5, '=')
    h2 = c.building(15, 13, 4, 2, 'r', 17, 'h')
    c.fill(17, 16, 1, 5, '=')
    h3 = c.building(29, 13, 5, 2, 'r', 31, 'h')
    c.fill(31, 16, 1, 5, '=')
    h4 = c.building(20, 24, 4, 2, 'r', 22, 'h')
    # Gym (door kept at 5,16).
    gym = c.building(2, 13, 7, 3, 'k', 5, 'j')
    c.fill(5, 17, 1, 4, '=')
    c.put(1, 17, 'S')
    # Plaza with a fountain between the avenues.
    c.fill(20, 13, 5, 6, '=')
    c.fill(21, 15, 2, 2, '~')
    c.put(20, 19, 'F'); c.put(24, 19, 'F'); c.put(23, 13, 'F')
    c.put(14, 9, 'S')
    # Street lamps along the avenues.
    for x in (3, 9, 16, 23, 30):
        c.put(x, 9, 'L')
    for x in (9, 16, 30):
        c.put(x, 12, 'L')
    for x in (3, 9, 18, 28):
        c.put(x, 23, 'L')
    # Parks and tree lines.
    for x, y in [(8, 3), (9, 3), (8, 6), (1, 8), (34, 8), (1, 24), (2, 24), (5, 26), (6, 26), (30, 25), (31, 25),
                 (16, 26), (17, 26), (9, 14), (9, 15), (34, 17), (25, 26), (26, 26)]:
        c.put(x, y, '#')
    for x, y in [(6, 7), (7, 7), (2, 7), (28, 25), (29, 26), (3, 27), (17, 27)]:
        c.put(x, y, 'F')
    rows = c.rows()

    def key(p):
        return '%d,%d' % p

    m = dict(old)
    m['tiles'] = rows
    m['doors'] = {
        key(store): {'kind': 'store'},
        key(lodge): {'kind': 'lodge'},
        key(h1): {'kind': 'house', 'text': ['The city never sleeps! The lamps stay lit all night.', "Rest here a while. It's quieter than the avenue."]},
        key(h2): {'kind': 'house', 'text': old['doors']['21,15']['text']},
        key(h3): {'kind': 'house', 'text': ['My dad works at the department store. He says the 2F counter gets new orbs every season.']},
        key(h4): {'kind': 'house', 'text': ['We moved here from Fernhollow. So many people! So many shops!']},
    }
    assert key(gym) == '5,16'
    m['signs'] = {
        '1,17': old['signs']['1,17'],
        '14,9': ['CINDER CITY', 'The big city in the shadow of the volcano.'],
        '18,7': ['CINDER DEPARTMENT STORE', 'Two floors of everything a trainer needs!'],
    }
    m['npcs'] = [
        {'x': 7, 'y': 8, 'dir': 'down', 'palette': 'old', 'text': old['npcs'][0]['text']},
        {'x': 6, 'y': 20, 'dir': 'right', 'palette': 'boy', 'text': old['npcs'][1]['text']},
        {'x': 19, 'y': 17, 'dir': 'right', 'palette': 'girl', 'text': ['Have you been to the department store? It has two whole floors!', 'And a drink machine upstairs. Lemonade is my favorite.']},
        {'x': 24, 'y': 11, 'dir': 'down', 'palette': 'gentleman', 'text': old['npcs'][2]['text']},
        {'x': 28, 'y': 22, 'dir': 'left', 'palette': 'beauty', 'text': ['The fountain is fed by a hot spring under the volcano.', 'Touch the water! ...Ow. Okay, maybe not.']},
    ]
    m['name'] = 'Cinder City'
    m['city'] = True
    MAPS['cindercity'] = m


# ---------- signature trees ----------
TREE_COUNT = 8


def plant_trees(map_id):
    m = MAPS[map_id]
    if m.get('planted'):
        return 0
    rows = [list(r) for r in m['tiles']]
    h, w = len(rows), len(rows[0])
    taken = set()
    for a in m.get('npcs', []) + m.get('trainers', []):
        taken.add((a['x'], a['y']))
    for k in list(m.get('doors', {})) + list(m.get('signs', {})) + list(m.get('warps', {})):
        x, y = map(int, k.split(','))
        taken.add((x, y))
    picks = []
    for y in range(2, h - 2):
        for x in range(2, w - 2):
            if rows[y][x] != '.':
                continue
            ok = all(rows[y + dy][x + dx] in '.#F' and (x + dx, y + dy) not in taken
                     for dy in (-2, -1, 0, 1, 2) for dx in (-1, 0, 1) if 0 <= y + dy < h)
            if ok and all(abs(x - px) + abs(y - py) > 3 for px, py in picks):
                picks.append((x, y))
    picks = picks[::max(1, len(picks) // TREE_COUNT)][:TREE_COUNT]
    for x, y in picks:
        rows[y][x] = '#'
    m['tiles'] = [''.join(r) for r in rows]
    m['planted'] = True
    return len(picks)


build_city()
planted = {}
for mid, m in MAPS.items():
    if m.get('town') and mid not in ('fernhollow', 'cindercity'):
        planted[mid] = plant_trees(mid)
json.dump(MAPS, open(PATH, 'w'), indent=1)
print('city:', len(MAPS['cindercity']['tiles'][0]), 'x', len(MAPS['cindercity']['tiles']), 'trees:', planted)
