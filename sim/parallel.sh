#!/bin/zsh
# sim/parallel.sh SEEDS JOBS [extra args, e.g. char=archer mode=dungeon floor=2] — splits seeds over JOBS godot processes, prints per-run lines + totals
n=${1:-50}; jobs=${2:-8}; shift 2
out=$(mktemp -d)
for j in $(seq 0 $((jobs - 1))); do
  only=$(seq $((j + 1)) $jobs $n | paste -sd, -)
  godot --headless --path "$(dirname $0)/.." -s sim/sim.gd -- seeds=$n only=$only verbose=1 "$@" > $out/$j.log 2>&1 &
done
wait
cat $out/*.log | grep "kite" | sort -t s -k3 -n
for c in knight archer; do
  for m in skip do; do
    tot=$(cat $out/*.log | grep -c "$c $m kite")
    won=$(cat $out/*.log | grep "$c $m kite" | grep -c ": won")
    [ $tot -gt 0 ] && echo "TOTAL $c $m quests: won $won/$tot"
  done
done
