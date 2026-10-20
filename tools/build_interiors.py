#!/usr/bin/env python3
"""Builds data/interiors.json: a room behind every town door (houses, Rest Lodges, Trail Marts)
and the people inside them.

DB merges the rooms into MAPS and turns each door into a warp, so walking into a door takes you
inside and stepping on the red mat takes you back out. Run from the repo root after editing:
python3 tools/build_interiors.py
"""
import json
import os

ROOT = os.path.join(os.path.dirname(__file__), '..')
MAPS = json.load(open(os.path.join(ROOT, 'data/maps.json')))

# Tile legend (see scripts/game/maps.gd): | wall  _ floor  e exit mat  c counter  t table
# K bookshelf  B bed  P potted plant  q mart shelf  M storage machine

HOUSE = [
    '|||||||||||',
    '|||||||||||',
    '|KK_____B_|',
    '|_______B_|',
    '|___tt____|',
    '|___tt____|',
    '|P_______P|',
    '|_________|',
    '|||||e|||||',
]
LODGE = [
    '|||||||||||||',
    '|||||||||||||',
    '|K_______M_K|',
    '|___ccccc___|',
    '|___________|',
    '|tt_______tt|',
    '|___________|',
    '|P_________P|',
    '||||||e||||||',
]
MART = [
    '|||||||||||',
    '|||||||||||',
    '|_c_______|',
    '|_c__qq_qq|',
    '|_c_______|',
    '|____qq_qq|',
    '|_________|',
    '|P_______P|',
    '|||||e|||||',
]

# Department store (the big city only): two floors joined by stairs (X) at the same spot.
STORE_1F = [
    '|||||||||||||||',
    '|||||||||||||||',
    '|_c________K_X|',
    '|_c___ccc_____|',
    '|_c___________|',
    '|_____________|',
    '|_qq_qq_qq_qq_|',
    '|_____________|',
    '|P___________P|',
    '|||||||e|||||||',
]
STORE_2F = [
    '|||||||||||||||',
    '|||||||||||||||',
    '|_c________V_X|',
    '|_c___________|',
    '|_c___________|',
    '|___________c_|',
    '|_qq_qq_____c_|',
    '|___________c_|',
    '|P___________P|',
    '|||||||||||||||',
]
STAIRS = (13, 2)
STAIRS_LANDING = (12, 2, 'left')

THEMES = {'house': '#e0c8a0', 'lodge': '#f0d8d8', 'mart': '#d0dce8', 'store': '#e8e0d0'}

# Who stands where in each room (x, y, facing). The resident of a house is the door's own text.
HOUSE_RESIDENT = (6, 5, 'left')
HOUSE_GUEST = (2, 6, 'right')
NURSE = (6, 2, 'down')
LODGE_GUEST = (3, 5, 'left')
CLERK = (1, 3, 'right')
SHOPPER = (6, 6, 'up')

RESIDENT_PALETTES = ['mom', 'old', 'gentleman', 'beauty', 'hiker']
GUEST_PALETTES = ['boy', 'girl', 'psychic', 'swimmer', 'battlegirl']

HOUSE_GUEST_LINES = [
    ['I want to be a trainer when I grow up!', 'Do creatures get stronger if you talk to them? I talk to mine every day.'],
    ['A creature that knows four moves is ready for anything.', 'But pick them carefully. Each one only has so much PP!'],
    ['Did you know a creature holding a grudge fights harder?', "...Just kidding. I made that up."],
    ['Some creatures only evolve once they reach a certain level.', "Don't press B during evolution unless you mean it!"],
    ['My big sister has all eight badges. She says the League is no joke.'],
    ['Paralysis lowers Speed to a quarter. Burns halve physical attacks.', 'Status moves win more battles than you would think.'],
]
LODGE_GUEST_LINES = [
    ['The Rest Lodge nurse heals your creatures for free.', 'If you ever black out, you wake up at the last Lodge where you healed.'],
    ['The storage machine holds creatures that do not fit in your party.', 'Ask the nurse to open it for you.'],
    ['A full party heals in a flash here. Never head into a gym tired!'],
    ['I keep a spare Potion in my bag at all times. Old habit.'],
    ['Creatures that sleep a lot are easier to catch. Twice as easy, they say!'],
]
SHOPPER_LINES = [
    ['Capture Orbs are cheap. Buy a stack before heading into the grass!'],
    ['Antidotes save a lot of trouble on long routes.'],
    ['I always buy a few Potions before a gym battle.'],
    ['The clerk said new stock comes in once you earn more badges. Or was that a rumor?'],
]

SPECIAL_HOUSES = {
    # The player's home: Mom lives here and the game starts here.
    ('fernhollow', '4,4'): {'id': 'fernhollow_home', 'name': 'Your House', 'guest': None},
    ('fernhollow', '4,13'): {'id': 'fernhollow_lab', 'name': "Prof. Alder's House"},
}


def rows_ok(rows):
    w = len(rows[0])
    assert all(len(r) == w for r in rows), rows
    return rows


def npc(pos, palette, text, **extra):
    x, y, d = pos
    out = {'x': x, 'y': y, 'dir': d, 'palette': palette, 'text': text}
    out.update(extra)
    return out


def store(town_id, town, door):
    """The two department store floors. Returns (1F, 2F)."""
    one = room(f'{town_id}_store1f', f"{town['name']} Dept. Store 1F", 'store', STORE_1F, town_id, door)
    two = room(f'{town_id}_store2f', f"{town['name']} Dept. Store 2F", 'store', STORE_2F, town_id, door)
    sx, sy = STAIRS
    lx, ly, ld = STAIRS_LANDING
    one['warps'][f'{sx},{sy}'] = {'map': two['id'], 'x': lx, 'y': ly, 'dir': ld}
    two['warps'][f'{sx},{sy}'] = {'map': one['id'], 'x': lx, 'y': ly, 'dir': ld}
    one['npcs'] = [
        npc((7, 2, 'down'), 'beauty', [
            'Welcome to the Cinder Department Store!',
            '1F: medicine counter. 2F: status cures, Capture Orbs and a drink machine. The stairs are in the back.',
        ]),
        npc((1, 3, 'right'), 'clerk', [], action='mart', greeting='Medicine counter! Potions of every strength.',
            stock=['potion', 'superPotion', 'hyperPotion', 'maxPotion', 'revive']),
        npc((5, 7, 'up'), 'gentleman', ['Max Potions! You cannot find those in a little Trail Mart.']),
        npc((10, 5, 'left'), 'girl', ['I came all the way from Fernhollow just to shop here!']),
    ]
    two['npcs'] = [
        npc((1, 3, 'right'), 'clerk', [], action='mart', greeting='Status cures! We even stock Ice Heal.',
            stock=['antidote', 'parlyzHeal', 'awakening', 'burnHeal', 'iceHeal', 'fullHeal']),
        npc((13, 6, 'left'), 'clerk', [], action='mart', greeting='Capture Orbs of every grade, for every budget!',
            stock=['orb', 'greatOrb', 'ultraOrb']),
        npc((7, 8, 'up'), 'hiker', ["The drink machine's Lemonade restores more HP than a Super Potion... almost."]),
    ]
    return one, two


def exit_mat(rows):
    y = len(rows) - 1
    return rows[y].index('e'), y


def room(map_id, name, kind, rows, town_id, door):
    dx, dy = map(int, door.split(','))
    out_warps = {}
    if 'e' in rows[-1]:
        ex, ey = exit_mat(rows)
        out_warps[f'{ex},{ey}'] = {'map': town_id, 'x': dx, 'y': dy + 1, 'dir': 'down'}
    return {
        'id': map_id,
        'name': name,
        'townId': town_id,
        'connections': {},
        'tiles': rows_ok(rows),
        'theme': THEMES[kind],
        'indoor': True,
        'interior': True,
        'music': 'town',
        'warps': out_warps,
        'npcs': [],
    }


rooms = {}
warps = {}
counters = {'house': 0, 'lodge': 0, 'mart': 0, 'store': 0}
for town_id, town in MAPS.items():
    houses = 0
    for door, d in town.get('doors', {}).items():
        kind = d['kind']
        n = counters[kind]
        counters[kind] += 1
        if kind == 'house':
            houses += 1
            special = SPECIAL_HOUSES.get((town_id, door), {})
            map_id = special.get('id', f'{town_id}_house{houses}')
            r = room(map_id, special.get('name', f"{town['name']} House"), kind, HOUSE, town_id, door)
            if map_id == 'fernhollow_home':
                resident = npc(HOUSE_RESIDENT, 'mom', d['text'], action='heal')
            elif map_id == 'fernhollow_lab':
                # Alder is out on Route 1 until he hands over the starters.
                resident = npc(HOUSE_RESIDENT, 'prof', d['text'], action='heal', showIf='starter')
                r['npcs'].append(npc((2, 4, 'right'), 'psychic', [
                    "The Professor? He went out to Route 1 early this morning.",
                    'He studies how creatures behave in the wild. He forgets to eat lunch half the time!',
                ], hideIf='starter'))
            else:
                resident = npc(HOUSE_RESIDENT, RESIDENT_PALETTES[n % len(RESIDENT_PALETTES)], d['text'], action='heal')
            r['npcs'].append(resident)
            if special.get('guest', True) is not None and map_id != 'fernhollow_lab':
                r['npcs'].append(npc(HOUSE_GUEST, GUEST_PALETTES[n % len(GUEST_PALETTES)], HOUSE_GUEST_LINES[n % len(HOUSE_GUEST_LINES)]))
        elif kind == 'store':
            r, upstairs = store(town_id, town, door)
            map_id = r['id']
            rooms[upstairs['id']] = upstairs
        elif kind == 'lodge':
            map_id = f'{town_id}_lodge'
            r = room(map_id, f"{town['name']} Rest Lodge", kind, LODGE, town_id, door)
            r['npcs'].append(npc(NURSE, 'nurse', [], action='lodge'))
            r['npcs'].append(npc(LODGE_GUEST, GUEST_PALETTES[(n + 2) % len(GUEST_PALETTES)], LODGE_GUEST_LINES[n % len(LODGE_GUEST_LINES)]))
        else:
            map_id = f'{town_id}_mart'
            r = room(map_id, f"{town['name']} Trail Mart", kind, MART, town_id, door)
            r['npcs'].append(npc(CLERK, 'clerk', [], action='mart'))
            r['npcs'].append(npc(SHOPPER, RESIDENT_PALETTES[(n + 1) % len(RESIDENT_PALETTES)], SHOPPER_LINES[n % len(SHOPPER_LINES)]))
        assert map_id not in rooms and map_id not in MAPS, map_id
        rooms[map_id] = r
        ex, ey = exit_mat(r['tiles'])
        warps.setdefault(town_id, {})[door] = {'map': map_id, 'x': ex, 'y': ey - 1, 'dir': 'up'}

out = {'maps': rooms, 'warps': warps}
json.dump(out, open(os.path.join(ROOT, 'data/interiors.json'), 'w'), indent=1)
print('interiors:', len(rooms), 'rooms,', sum(len(r['npcs']) for r in rooms.values()), 'npcs', counters)
