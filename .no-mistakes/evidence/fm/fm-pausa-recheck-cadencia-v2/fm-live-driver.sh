# Live driver: real fm-watch.sh + real isolated tmux server + real wake queue/drain.
# Crew state is the hermetic fake (no real grok harness here).
live_driver() {
  local watch=${LIVE_WATCH:-$WATCH} dur=${LIVE_DUR:-150} blip=${LIVE_BLIP:-1}
  local status_line=${LIVE_STATUS:-'paused: waiting on the captain to decide'}
  local crew=${LIVE_CREW:-'state: paused · source: status-log · parked'}
  local dir state fakebin out ctl statusf window key sig start now pid t
  dir=$(make_case live-${LIVE_TAG:-x}); state="$dir/state"; fakebin="$dir/fakebin"
  out="$dir/watch.out"; ctl="$dir/pane-mode"; statusf="$state/parked.status"
  rm -f "$fakebin/tmux"; echo "fakebin now: $(ls "$fakebin" | tr "\n" " ")"
  export TMUX_TMPDIR="$dir/tmuxsock"; mkdir -p "$TMUX_TMPDIR"; unset TMUX
  # A pane program named grok, so pane_current_command reads as the harness.
  mkdir -p "$dir/hbin"
  cp "$(command -v bash)" "$dir/hbin/grok"
  cat > "$dir/hbin/pane.sh" <<SH
prev=
while :; do
  m=\$(cat $ctl 2>/dev/null)
  if [ "\$m" != "\$prev" ]; then
    clear
    if [ "\$m" = busy ]; then echo 'thinking about the reply  Ctrl+c:cancel'
    else for j in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do echo "  transcript line \$j"; done; echo "parked on a declared wait (\$m)"; fi
    prev=\$m
  fi
  sleep 0.5
done
SH
  echo idle > "$ctl"
  tmux new-session -d -s fmlab -n fm-parked -x 120 -y 30 "$dir/hbin/grok $dir/hbin/pane.sh"
  sleep 1
  window="fmlab:fm-parked"; key=$(printf '%s' "$window" | tr ':/.' '___')
  echo "pane_current_command=$(tmux display-message -p -t "$window" '#{pane_current_command}')"
  printf 'window=%s\nkind=ship\nharness=grok\nbackend=tmux\n' "$window" > "$state/parked.meta"
  printf '%s\n' "$status_line" > "$statusf"
  sig=$(seen_sig "$statusf"); printf '%s' "$sig" > "$state/.seen-parked_status"
  : > "$state/parked.turn-ended"; prime_turnend_seen "$state/parked.turn-ended"
  # The pane blinks busy for ~2s every ~8s when blip=1.
  ( k=0; while :; do sleep ${LIVE_PERIOD:-12}; [ "$blip" = 1 ] && { k=$((k+1)); echo busy > "$ctl"; if [ -n "${LIVE_RELAUNCH:-}" ]; then printf 'window=%s\nkind=ship\nharness=grok\nbackend=tmux\nspawn_gen=s%s\n' "$window" "$k" > "$state/parked.meta"; : > "$state/parked.turn-ended"; fi; sleep 3; echo "idle after blip $k" > "$ctl"; }; done ) &
  local blipper=$!
  start=$(date +%s)
  while :; do
    now=$(date +%s); [ $((now - start)) -ge "$dur" ] && break
    PATH="$fakebin:$PATH" FM_FAKE_CREW_STATE="$crew" FM_WATCH_HANDLING_SUCCESSOR=1 \
      FM_STATE_OVERRIDE="$state" FM_CREW_STATE_BIN="$fakebin/fm-crew-state.sh" \
      FM_PAUSE_RESURFACE_SECS=${LIVE_RESURFACE:-45} FM_POLL=1 FM_SIGNAL_GRACE=1 \
      FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999 "$watch" >> "$out" 2>&1 &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
      now=$(date +%s); [ $((now - start)) -ge "$dur" ] && { kill "$pid"; wait "$pid" 2>/dev/null; break 2; }
      sleep 1
    done
    wait "$pid" 2>/dev/null
    t=$(( $(date +%s) - start ))
    echo "t=${t}s watcher exited (firstmate woken); ack and re-arm"
    echo "  queued: $(tail -n1 "$state/.wake-queue" 2>/dev/null | cut -f3-5 | tr "\t" " ")"; ack_stopped_cycle "$state" >/dev/null 2>&1 || echo "  (ack failed)"
  done
  echo "--- final pane:"; tmux capture-pane -p -t "$window" | grep -v "^$"; echo "--- watcher tail:"; tail -5 "$out"; kill "$blipper" 2>/dev/null
  tmux kill-server 2>/dev/null
  echo "--- stale wakes queued for $window over ${dur}s (resurface=${LIVE_RESURFACE:-45}s, blips=$blip):"
  awk -F '\t' -v w="$window" '$3 == "stale" && $4 == w { n++ } END { print n + 0 }' "$state/.wake-queue" 2>/dev/null
  echo "--- wake-queue kinds:"; cut -f3,5 "$state/.wake-queue" 2>/dev/null | sort | uniq -c
  echo "--- triage log tail:"; tail -n 6 "$state/.watch-triage.log" 2>/dev/null
  echo "--- absorbed-paused lines: $(grep -c 'absorbed stale (paused' "$state/.watch-triage.log" 2>/dev/null)"
}
export -f live_driver
live_debug() {
  LIVE_DUR=45 LIVE_PERIOD=10 live_driver 2>&1 | head -40
  local st; st=$(ls -d "$TMP_ROOT"/live-*/state | head -1)
  echo "state=$st"; head -20 "$st/.watch-triage.log"; cat "$st"/.count-* "$st"/.hash-*; echo; tail -20 "$(dirname "$st")/watch.out"
}
export -f live_debug
live_trace() {
  local st
  LIVE_WATCH="/tmp/fmtrace-watch.sh" LIVE_DUR=30 LIVE_PERIOD=8 live_driver > /tmp/fmtrace-driver.out 2>&1
}
export -f live_trace
