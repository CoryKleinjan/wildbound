#!/usr/bin/env python3
"""Builds data/story.json: the story's extra NPCs, Hollow Order trainers and rival lines.

Story text lives here; positions are picked automatically next to each map's road so the
story survives map edits. Run from the repo root: python3 tools/build_story.py
"""
import json
import os

ROOT = os.path.join(os.path.dirname(__file__), '..')
MAPS = json.load(open(os.path.join(ROOT, 'data/maps.json')))
SPECIES = json.load(open(os.path.join(ROOT, 'data/species.json')))
MISC = json.load(open(os.path.join(ROOT, 'data/misc.json')))
ROUTE_LEVELS = MISC['routeLevels']
WALKABLE = set('.,=Fhlm:ju_e')


def stage_for_level(sp, level):
    while SPECIES[sp].get('evolves') and SPECIES[sp]['evolves']['level'] <= level:
        sp = SPECIES[sp]['evolves']['into']
    return sp


def team(roots, levels):
    return [[stage_for_level(r, l), l] for r, l in zip(roots, levels)]


def occupied(m):
    taken = set()
    for a in m.get('npcs', []) + m.get('trainers', []):
        taken.add((a['x'], a['y']))
    for key in list(m.get('signs', {})) + list(m.get('doors', {})) + list(m.get('warps', {})):
        x, y = map(int, key.split(','))
        taken.add((x, y))
    return taken


def tile(m, x, y):
    if y < 0 or y >= len(m['tiles']) or x < 0 or x >= len(m['tiles'][0]):
        return '#'
    return m['tiles'][y][x]


def spot(map_id, frac, used, road_side=True):
    """A free walkable tile beside the road, about `frac` of the way along the map's long axis.
    Returns (x, y, dir) with dir facing the road."""
    m = MAPS[map_id]
    h, w = len(m['tiles']), len(m['tiles'][0])
    horizontal = w > h
    taken = occupied(m) | used
    best = None
    for y in range(2, h - 2):
        for x in range(2, w - 2):
            if tile(m, x, y) not in '.F' or (x, y) in taken:
                continue
            if any(abs(x - tx) + abs(y - ty) < 3 for tx, ty in taken):
                continue
            for d, (dx, dy) in {'up': (0, -1), 'down': (0, 1), 'left': (-1, 0), 'right': (1, 0)}.items():
                if tile(m, x + dx, y + dy) != '=' or not road_side:
                    continue
                pos = (x / w) if horizontal else (1 - y / h)
                score = abs(pos - frac)
                if best is None or score < best[0]:
                    best = (score, x, y, d)
    assert best, f'no spot on {map_id}'
    used.add((best[1], best[2]))
    return best[1], best[2], best[3]


USED = {}


def place(map_id, frac):
    return spot(map_id, frac, USED.setdefault(map_id, set()))


def grunt(map_id, n, frac, roots, extra=None):
    lo, hi = ROUTE_LEVELS[int(map_id.replace('route', ''))]
    x, y, d = place(map_id, frac)
    lines = GRUNT_LINES[n % len(GRUNT_LINES)]
    t = {
        'id': f'order_{map_id}_{n}', 'name': 'Order Grunt', 'palette': 'orderGrunt', 'x': x, 'y': y, 'dir': d, 'sight': 3,
        'pay': 40, 'party': team(roots, [hi - 1, hi][:len(roots)] if len(roots) <= 2 else [hi - 2, hi - 1, hi]),
        'intro': lines[0], 'defeat': lines[1], 'after': lines[2],
    }
    t.update(extra or {})
    return map_id, t


GRUNT_LINES = [
    ["Halt! The Hollow Order is searching this area. Wild-hearted kids aren't welcome!", "You fight like a creature with no leash...", "Magister Vane says creatures were made to obey. Someday you'll see it."],
    ["A Star Shard hums somewhere near here. Get lost before you get hurt!", "Ugh, the Admins are going to hear about this.", "When the Starchime rings, the world will have one will. His."],
    ["You've seen our grey cloaks? Then you've seen too much!", "No fair! My creatures listened to you more than me!", "Free creatures are wasted creatures. That's what the Order teaches."],
    ["The Order doesn't need trainers. We need shards!", "Fine, fine. Keep walking.", "Every Warden we wake gives up a shard. Then the chime is ours."],
]

TRAINERS = []
TRAINERS.append(grunt('route2', 0, 0.35, ['musklet', 'shadepup']))
TRAINERS.append(grunt('route2', 1, 0.7, ['pilfur', 'seepling']))
TRAINERS.append(grunt('route3', 2, 0.5, ['lurkit', 'stingrub']))
TRAINERS.append(grunt('route5', 3, 0.3, ['jellip', 'pilfur']))
TRAINERS.append(grunt('route5', 0, 0.55, ['blightcap', 'umbrat']))
sx, sy, sd = place('route5', 0.85)
TRAINERS.append(('route5', {
    'id': 'order_sable_1', 'name': 'Order Admin Sable', 'palette': 'orderAdmin', 'x': sx, 'y': sy, 'dir': sd, 'sight': 4, 'pay': 90,
    'party': team(['sootling', 'pilfur', 'umbrat'], [24, 24, 25]),
    'intro': "So you're the trainer my grunts keep whining about. I'm Sable, Admin of the Hollow Order. The volcano past Cinder City holds a Warden's shard, and I won't let a child get in the way.",
    'defeat': "Tch. Cinder Peak will answer us whether you like it or not.",
    'after': "Terrasolis sleeps under Cinder Peak. One good shake and its shard comes loose.",
}))
TRAINERS.append(grunt('route6', 1, 0.5, ['fenspawn', 'lurkit']))
TRAINERS.append(grunt('route8', 2, 0.3, ['musklet', 'omenkin', 'pilfur']))
TRAINERS.append(grunt('route8', 3, 0.7, ['ozlug', 'shadepup', 'stingrub']))
cx, cy, cd = place('route9', 0.6)
TRAINERS.append(('route9', {
    'id': 'order_corvin_1', 'name': 'Order Admin Corvin', 'palette': 'orderAdmin', 'x': cx, 'y': cy, 'dir': cd, 'sight': 4, 'pay': 120,
    'party': team(['omenkin', 'umbrat', 'grimlet', 'jellip'], [36, 36, 37, 38]),
    'intro': "These storms over Skyreach? Zenithar is restless, and restless Wardens shed shards. I'm Corvin. Admin. Please don't make this tedious.",
    'defeat': "Tedious after all. Sable warned me about you.",
    'after': "Three shards, then four. Lumenvale's observatory has the Star Map that shows where the rest are buried.",
}))
TRAINERS.append(grunt('route10', 0, 0.35, ['seepling', 'lurkit', 'grimlet']))
TRAINERS.append(grunt('route10', 1, 0.7, ['blightcap', 'umbrat', 'musklet']))
TRAINERS.append(grunt('route11', 2, 0.3, ['omenkin', 'jellip', 'pilfur']))
ax, ay, ad = place('route11', 0.7)
TRAINERS.append(('route11', {
    'id': 'order_admins', 'name': 'Admins Sable & Corvin', 'palette': 'orderAdmin', 'x': ax, 'y': ay, 'dir': ad, 'sight': 4, 'pay': 160,
    'double': True,
    'party': team(['sootling', 'umbrat', 'omenkin', 'grimlet'], [43, 43, 44, 44]),
    'intro': "SABLE: You again! We have the Star Map now. CORVIN: Then let's finish this properly. Two of us, one of you.",
    'defeat': "CORVIN: ...We have six shards. It's enough. SABLE: The Magister is already at Summit Crown. Go and watch him win.",
    'after': "SABLE: When the Starchime rings, none of this will matter.",
}))

# Magister Vane stands in front of the League door and leaves once beaten.
door = next(k for k, w in MAPS['summitcrown']['warps'].items() if w['map'] == 'league')
dx, dy = map(int, door.split(','))
TRAINERS.append(('summitcrown', {
    'id': 'order_vane', 'name': 'Magister Vane', 'palette': 'orderBoss', 'x': dx, 'y': dy + 1, 'dir': 'down', 'sight': 2, 'pay': 300,
    'leaveAfter': True,
    'party': team(['umbrat', 'grimlet', 'pallwick', 'seepling', 'omenkin', 'fenspawn'], [48, 48, 49, 49, 50, 51]),
    'intro': "So the wild-hearted child climbed all this way. Above us the Starchime waits, and I hold six shards of the Wardens. One more chime and every creature in Wildbound will answer to a single will. Mine. Show me why I should not.",
    'defeat': "The shards... they're going dark. The chime will not ring for someone who chains it.",
    'after': "",
}))

# Rival Kai's lines follow the story.
TRAINER_PATCHES = {
    'r2_kai': {
        'intro': "There you are! Did you see those grey cloaks digging by the shrine? Whatever. Battle first, questions later!",
        'defeat': "Argh, again?! Okay, okay. I'm heading to Stonecrest. Grandpa says the Order is looking for something called a Star Shard.",
        'after': "Grey cloaks, Star Shards... Grandpa's worried. That's never good.",
    },
    'rival_r7': {
        'intro': "Hey! I chased an Order Admin all the way from Cinder Peak. Before I go after her again, let's see who's grown stronger!",
        'defeat': "You're still ahead of me... Fine. Then you'll be the one who stops them. Don't let me down.",
        'after': "The Order wants the Starchime to ring early. Grandpa says that could change everything.",
    },
    'rival_r12': {
        'intro': "This is it, Victory Road. Vane is up at the summit. One last battle between us before we face him!",
        'defeat': "That's my rival. Go. I'll be right behind you.",
        'after': "Whatever happens up there, I've got your back.",
    },
}

# Story NPCs: one per town, with lines that change after the champion is crowned.
NPC_TEXT = {
    'stonecrest': ('hiker', ["Strangers in grey cloaks came through the quarry last week.", "They carried off a stone that glowed like a star. Called it a 'shard'."]),
    'duskmere': ('gentleman', ["A man in grey asked me to join the Hollow Order.", "He said soon every creature would obey without question. What a sad world that would be."]),
    'voltara': ('ace', ["The power plant keeps browning out at night.", "Someone's been draining power to 'tune' something. The Order, if you ask me."]),
    'cindercity': ('hiker', ["The ground's been rumbling under Cinder Peak.", "Old folks say Terrasolis sleeps there. I hope nobody wakes it."]),
    'harrowfield': ('girl', ["A boy with a teal jacket ran through here chasing an Order Admin!", "He said his name was Kai. He seemed to know you."]),
    'bramblegate': ('old', ["The Order took the old shrine bell from our square.", "Bells, chimes, shards... They're obsessed with the Starchime."]),
    'skyreach': ('bird', ["Storms every day now. Zenithar must be restless.", "My Flying creatures won't even leave the roost."]),
    'saltmarsh': ('old', ["PROF. ALDER: There you are! I've been following the Order's trail.", "Seven Wardens watch over Wildbound. When one stirs, it sheds a Star Shard.", "With enough shards, Vane could force the Starchime to ring and take its wish for himself.", "The Order will go after the observatory in Lumenvale next. Please, be careful."]),
    'lumenvale': ('psychic', ["The Order broke into the observatory and stole the Star Map!", "It shows where every Warden rests. They're heading north, toward Summit Crown."]),
    'coralhaven': ('swimmer', ["The tide keeps rising higher every day. Thalassor is stirring.", "Whatever the Order is doing up north, the sea can feel it."]),
    'summitcrown': ('rival', ["KAI: The Starchime is up there, past the League.", "Vane is waiting in front of the League doors. You're the only one strong enough to stop him."]),
}
NPC_AFTER = {
    'saltmarsh': ["PROF. ALDER: The Starchime rang for you, Champion. I've never been prouder.", "They say the Wardens now roam Victory Road. Perhaps you'll meet one!"],
    'summitcrown': ["KAI: Champion, huh? Don't get comfortable. I'm coming for that title!"],
}

NPCS = {}
for map_id, (palette, text) in NPC_TEXT.items():
    x, y, d = spot(map_id, 0.5, USED.setdefault(map_id, set()))
    npc = {'x': x, 'y': y, 'dir': 'down', 'palette': palette, 'text': text}
    if map_id in NPC_AFTER:
        npc['variants'] = [{'if': 'champion', 'text': NPC_AFTER[map_id]}]
    NPCS.setdefault(map_id, []).append(npc)

out = {'npcs': NPCS, 'trainers': {}, 'trainerPatches': TRAINER_PATCHES}
for map_id, t in TRAINERS:
    out['trainers'].setdefault(map_id, []).append(t)
for map_id, ts in out['trainers'].items():
    for t in ts:
        for sp, _ in t['party']:
            assert sp in SPECIES, sp
json.dump(out, open(os.path.join(ROOT, 'data/story.json'), 'w'), indent=1)
print('story:', sum(len(v) for v in NPCS.values()), 'npcs,', len(TRAINERS), 'trainers')
for map_id, t in TRAINERS:
    print(f"  {map_id:12} {t['name']:22} at {t['x']},{t['y']} facing {t['dir']}  {t['party']}")
