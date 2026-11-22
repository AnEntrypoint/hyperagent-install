#!/bin/sh
set -eu
release_dir="$1"
log="$2"
python3 -u -m http.server 0 --bind 127.0.0.1 --directory "$release_dir" > "$log" 2>&1 &
server_pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  port=$(sed -n 's/.*port \([0-9][0-9]*\).*/\1/p' "$log" | head -n 1)
  [ -n "$port" ] && break
  sleep 0.2
done
echo "$server_pid $port"
