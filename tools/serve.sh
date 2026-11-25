#!/bin/sh
set -eu
release_dir=$1
log=$2
port=$(python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
python3 -u -m http.server "$port" --bind 127.0.0.1 --directory "$release_dir" > "$log" 2>&1 &
server_pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  if python3 -I -c 'import socket,sys; s=socket.create_connection(("127.0.0.1",int(sys.argv[1])),0.2); s.close()' "$port" >/dev/null 2>&1; then break; fi
  sleep 0.1
done
echo "$server_pid $port"
