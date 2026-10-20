#!/usr/bin/env bash
# Drop-in co-op check: runs a host and a friend who joins with their own save, side by side under
# xvfb. Saves screenshots and logs to $1. Uses (and overwrites) the two save files in user://.
set -u
cd "$(dirname "$0")/.."
G=${GODOT:-godot}
OUT=${1:-/tmp/wildbound-lan}; rm -rf $OUT; mkdir -p $OUT
xvfb-run -a $G --path . --rendering-driver opengl3 -s res://tests/drive.gd -- $OUT/h \
  'gd:var gs = GameState.new_game("solo", ["Wren"]) ;; GameState.give_starter(gs, 0, "sproutle") ;; gs.flags.starter = true ;; gs.flags.intro_mom = true ;; GameState.save(gs)' \
  wait:30 key:Z wait:10 key:Z wait:90 top:OverworldScene shot:start \
  "until:K:60:Net.guest_in_world()" wait:200 shot:joined \
  "print:Game.views[1].gs.players[0].name" "print:Game.views[1].gs.players[0].party.size()" \
  "print:Vector2i(Game.views[1].stack[0].player.x, Game.views[1].stack[0].player.y)" wait:400 \
  "print:Vector2i(Game.views[1].stack[0].player.x, Game.views[1].stack[0].player.y)" "gd:game.views[1].gs.money = 1234" \
  "gd:game.in_view(1, game.views[1].stack[0].load_map.bind(\"route1\", 10, 20, \"up\"))" wait:60 "print:Game.views[1].gs.map" "print:Game.views[0].gs.map" shot:apart \
  "print:Game.views[1].gs.flags == Game.views[0].gs.flags" wait:200 > $OUT/host.log 2>&1 &
sleep 5
xvfb-run -a $G --path . --rendering-driver opengl3 -s res://tests/drive.gd -- $OUT/c \
  'gd:GameState.SAVE_PATH = "user://p2-save.json" ;; var gs = GameState.new_game("solo", ["Mira"]) ;; GameState.give_starter(gs, 0, "cindercub") ;; GameState.give_starter(gs, 0, "ripplet") ;; gs.flags.starter = true ;; gs.money = 777 ;; GameState.save(gs)' \
  wait:30 key:Z wait:10 key:DOWN key:DOWN key:Z wait:150 shot:joinlist "print:Net.found" \
  key:Z wait:200 "print:Net.connected" shot:joined key:Z:4 wait:30 key:Z:4 wait:30 \
  key:A:60 wait:200 wait:120 shot:route "print:Net.frame.size()" \
  "gd:return GameState.load_game().players[0].name + str(GameState.load_game().players[0].party.size()) + str(GameState.load_game().money)" \
  wait:200 "gd:return GameState.load_game().money" > $OUT/client.log 2>&1
wait
