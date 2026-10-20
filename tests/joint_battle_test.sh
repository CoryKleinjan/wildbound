#!/usr/bin/env bash
# Joint double battles: a host and a joined friend stand together on Route 1, then each starts a
# wild battle in turn and both mash A through it. Saves screenshots and logs to $1; check that both
# screens show the double battle and that the friend's saved exp went up. Overwrites user:// saves.
set -u
cd "$(dirname "$0")/.."
G=${GODOT:-godot}
OUT=${1:-/tmp/wildbound-joint}; rm -rf $OUT; mkdir -p $OUT
ZS=""; for i in $(seq 1 40); do ZS="$ZS key:Z wait:25"; done
xvfb-run -a $G --path . --rendering-driver opengl3 -s res://tests/drive.gd -- $OUT/h \
  'gd:var gs = GameState.new_game("solo", ["Wren"]) ;; gs.players[0].party.append(Creatures.create_creature("sproutle", 30)) ;; gs.flags.starter = true ;; gs.flags.intro_mom = true ;; GameState.save(gs)' \
  wait:30 key:Z wait:10 key:Z top:OverworldScene "until:K:80:Net.guest_in_world()" wait:200 \
  'gd:game.top.load_map("route1", 10, 12, "up") ;; game.in_view(1, game.views[1].stack[0].load_map.bind("route1", 11, 12, "up"))' wait:60 \
  "gd:game.top._start_wild()" wait:120 shot:host_battle $ZS "print:Game.views[1].gs.players[0].party[0].exp" \
  "gd:game.in_view(1, game.views[1].stack[0]._start_wild)" wait:120 shot:host_battle2 $ZS wait:300 > $OUT/host.log 2>&1 &
sleep 5
xvfb-run -a $G --path . --rendering-driver opengl3 -s res://tests/drive.gd -- $OUT/c \
  'gd:GameState.SAVE_PATH = "user://p2-joint.json" ;; var gs = GameState.new_game("solo", ["Mira"]) ;; gs.players[0].party.append(Creatures.create_creature("cindercub", 30)) ;; GameState.save(gs)' \
  wait:30 key:Z wait:10 key:DOWN key:DOWN key:Z wait:150 key:Z wait:200 key:Z wait:300 shot:friend_battle $ZS wait:200 shot:friend_battle2 $ZS wait:600 \
  "gd:return GameState.load_game().players[0].party[0].exp" > $OUT/client.log 2>&1
wait
