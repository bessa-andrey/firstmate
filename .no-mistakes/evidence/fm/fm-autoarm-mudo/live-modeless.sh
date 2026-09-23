#!/usr/bin/env bash
# Live driver: real fm-check-register.sh + fm-watch.sh against a state dir on
# the WSL2 DrvFs mount /mnt/c, where chmod 600/700 reverts to 777.
set -u
ROOT=/home/bessabr/.no-mistakes/worktrees/bfe4fd9cd19f/01M37MV7VQPSVJZ47Q557FK7GF
BASE=${1:-/mnt/c/Users/bessa/AppData/Local/Temp}
H=$(mktemp -d "$BASE/fm-live-home.XXXXXX"); trap 'rm -rf "$H"' EXIT
mkdir -p "$H/state" "$H/data" "$H/config"; S=$H/state
ack() {  # acknowledge the delivered wake the way firstmate does, via fm-wake-drain.sh
  local err=$H/drain.err seq gen
  FM_STATE_OVERRIDE=$S "$ROOT/bin/fm-wake-drain.sh" >/dev/null 2>"$err"
  seq=$(sed -n 's/^WAKE_ACK_REQUIRED:.*--ack-through \([0-9][0-9]*\) --recovery-generation .*$/\1/p' "$err")
  gen=$(sed -n 's/^WAKE_ACK_REQUIRED:.*--recovery-generation \([A-Za-z0-9._-]*\)$/\1/p' "$err")
  FM_STATE_OVERRIDE=$S "$ROOT/bin/fm-wake-drain.sh" --ack-through "$seq" --recovery-generation "$gen" >/dev/null 2>&1 && echo "(acked wake $seq)"
}
echo "== home: $H  (mount: $(stat -f -c %T "$H"))"
chmod 700 "$S"; echo "state dir mode after chmod 700: $(stat -c %a "$S")"
cat > "$S/probe.check.sh" <<'SH'
#!/usr/bin/env bash
printf 'check: probe fired from a mode-incapable state dir\n'
SH
chmod 700 "$S/probe.check.sh"; echo "check.sh mode after chmod 700: $(stat -c %a "$S/probe.check.sh")"
echo "== \$ fm-check-register.sh probe"
FM_HOME=$H FM_ROOT_OVERRIDE=$ROOT "$ROOT/bin/fm-check-register.sh" probe; echo "exit=$?"
ls -1a "$S" | grep -v '^\.\.\?$'
echo "== \$ fm-watch.sh (one bounded cycle)"
timeout 60 env FM_HOME=$H FM_ROOT_OVERRIDE=$ROOT FM_CHECK_INTERVAL=0 FM_POLL=0.05 FM_HEARTBEAT=999999 FM_SIGNAL_GRACE=0 \
  "$ROOT/bin/fm-watch.sh" > "$H/w1.out" 2> "$H/w1.err"; echo "exit=$?"
echo "-- stdout:"; cat "$H/w1.out"; echo "-- stderr (tail):"; tail -5 "$H/w1.err"
ack
echo "== tamper: append a line to probe.check.sh after the seal"
printf 'printf "tampered\\n"\n' >> "$S/probe.check.sh"
rm -f "$S/.last-check"
timeout 20 env FM_HOME=$H FM_ROOT_OVERRIDE=$ROOT FM_CHECK_INTERVAL=0 FM_POLL=0.05 FM_HEARTBEAT=999999 FM_SIGNAL_GRACE=0 \
  "$ROOT/bin/fm-watch.sh" > "$H/w2.out" 2> "$H/w2.err"; echo "exit=$?"
echo "-- stdout:"; cat "$H/w2.out"; echo "-- stderr (tail):"; tail -5 "$H/w2.err"
if grep -q rearm-resurface "$H/w2.out"; then
  ack
  echo "== (restart resurface wake consumed; run the next watcher cycle)"
  timeout 20 env FM_HOME=$H FM_ROOT_OVERRIDE=$ROOT FM_CHECK_INTERVAL=0 FM_POLL=0.05 FM_HEARTBEAT=999999 FM_SIGNAL_GRACE=0 \
    "$ROOT/bin/fm-watch.sh" > "$H/w2.out" 2> "$H/w2.err"; echo "exit=$?"
  echo "-- stdout:"; cat "$H/w2.out"; echo "-- stderr (tail):"; tail -5 "$H/w2.err"
fi
grep -q tampered "$H/w2.out" && echo "RESULT: TAMPERED CHECK EXECUTED (bad)" || echo "RESULT: tampered check not executed"
