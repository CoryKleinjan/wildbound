#!/usr/bin/env bash
# Runs a host and a joining game side by side under xvfb and saves screenshots and logs to $1.
# Delete any save file first: with a save, the title menu starts at CONTINUE.
set -u
cd "$(dirname "$0")/.."
G=${GODOT:-godot}
OUT=${1:-/tmp/wildbound-lan}; rm -rf $OUT; mkdir -p $OUT
xvfb-run -a $G --path . --rendering-driver opengl3 -s res://tests/drive.gd -- $OUT/h \
  wait:30 key:Z wait:10 key:DOWN key:Z wait:90 shot:lobby \
  "until:K:40:Net.client_id != 0" wait:200 "print:Net.client_id" shot:joined \
  "top:NameEntryScene" shot:p1name key:ESCAPE wait:30 \
  "until:Z:60:Game.gs != null" "print:Game.gs.players" wait:120 shot:fern \
  "print:Net._last_frame.size()" "print:Net.recorder.cmds.size()" "print:var_to_bytes(Net.recorder.cmds).size()" \
  wait:120 > $OUT/host.log 2>&1 &
sleep 4
xvfb-run -a $G --path . --rendering-driver opengl3 -s res://tests/drive.gd -- $OUT/c \
  wait:30 key:Z wait:10 key:DOWN key:DOWN key:Z wait:150 shot:joinlist "print:Net.found" \
  key:Z wait:120 "print:Net.connected" shot:connected \
  wait:400 shot:mirror key:ESCAPE:6 wait:40 key:ESCAPE:6 wait:40 key:ESCAPE:6 wait:40 key:ESCAPE:6 wait:40 key:ESCAPE:6 wait:40 \
  key:ESCAPE:6 wait:40 key:ESCAPE:6 wait:40 key:ESCAPE:6 wait:40 key:ESCAPE:6 wait:40 key:ESCAPE:6 wait:200 shot:mirror2 \
  "print:Net.frame.size()" "print:Net.textures.size()" > $OUT/client.log 2>&1
wait
