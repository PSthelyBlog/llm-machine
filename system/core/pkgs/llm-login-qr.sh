# llm-login-qr: sign in to Claude with a phone.
#   --watch  wait for the sign-in link in the Claude window, start the hand-over page
#            (llm-login-relay) and pop the QR code up once
#   --show   pop it up again (F4)
#   --popup  draw it (runs inside the tmux popup); --popup --link shows the sign-in link
#            itself, for when no phone is on the same network

URL_FILE=${XDG_RUNTIME_DIR:-/tmp}/llm-login-url
RELAY_FILE=${XDG_RUNTIME_DIR:-/tmp}/llm-login-relay
RELAY_PORT=@relayPort@

signed_in() { [ -s "$HOME/.claude/.credentials.json" ] || [ -n "${ANTHROPIC_API_KEY:-}" ]; }

# The link can be wrapped over several lines: take the last one on screen and append
# the lines that follow it as long as they look like more of the same URL.
find_url() {
  tmux capture-pane -p -J -S -200 -t main:claude | awk '
    function trim(s) { sub(/^[ \t│|]+/, "", s); sub(/[ \t│|]+$/, "", s); return s }
    {
      line = trim($0)
      if (match(line, /https:\/\/[^ \t]*oauth\/authorize[^ \t]*/)) {
        url = substr(line, RSTART, RLENGTH); open = 1; next
      }
      if (open && line ~ /^[A-Za-z0-9%._~:\/?#@!$&()*+,;=-]+$/) url = url line
      else open = 0
    }
    END { if (url != "") print url }'
}

popup() { tmux display-popup -E -w 100% -h 100% -t main "llm-login-qr --popup"; }

show_qr() {
  local code
  clear
  code=$(qrencode -t ANSIUTF8 -m 2 "$1")
  if [ "$(echo "$code" | wc -l)" -gt $(($(tput lines) - 7)) ]; then
    echo "The screen is too small for the QR code. On your phone, open:"
    echo "$1"
  else
    echo "$2"
    echo "$code"
  fi
}

case "${1:-}" in
  --watch)
    seen="" relay=""
    trap 'exit' TERM INT
    trap '[ -z "$relay" ] || kill "$relay" 2>/dev/null || true' EXIT
    while ! signed_in; do
      url=$(find_url || true)
      if [ -n "$url" ] && [ "$url" != "$seen" ]; then
        seen=$url
        echo "$url" > "$URL_FILE"
        if [ -z "$relay" ] && [ -n "$RELAY_PORT" ]; then
          rm -f "$RELAY_FILE"
          llm-login-relay "$RELAY_PORT" "$URL_FILE" "$RELAY_FILE" > /dev/null 2>&1 &
          relay=$!
          sleep 1
        fi
        popup || true
      fi
      sleep 1
    done
    ;;
  --show)
    url=$(find_url || true)
    [ -z "$url" ] || echo "$url" > "$URL_FILE"
    if [ -s "$URL_FILE" ]; then
      popup
    else
      tmux display-message "No sign-in link on screen yet. In Claude, type /login."
    fi
    ;;
  --popup)
    if [ -s "$RELAY_FILE" ] && [ "${2:-}" != --link ]; then
      address=$(cat "$RELAY_FILE")
      show_qr "$address" "Scan this with your phone to sign in to Claude."
      echo "Your phone needs to be on the same network as this computer. It then shows the"
      echo "sign-in link and a box for the code, and this computer signs in by itself."
      echo "(Or open $address on your phone.)"
      echo
      echo "No phone on this network? Press L for the sign-in link instead. Any other key closes this."
      key=""
      read -rsn1 key || true
      if [ "$key" = l ] || [ "$key" = L ]; then
        exec llm-login-qr --popup --link
      fi
    else
      url=$(cat "$URL_FILE")
      show_qr "$url" "Scan this with your phone to sign in to Claude."
      echo "After you approve, the page shows a code. Type it here up to the # sign (the rest"
      echo "is filled in for you), then press Enter. Enter on its own closes this."
      code=""
      read -r code || true
      # Only the part before # is needed: the rest is the link's state, which we know.
      code=${code%%#*}
      code=${code//[[:space:]]/}
      if [ -n "$code" ]; then
        state=${url##*state=}
        tmux send-keys -t main:claude -l "$code#${state%%&*}"
        sleep 0.5
        tmux send-keys -t main:claude Enter
      fi
    fi
    ;;
  *)
    echo "usage: llm-login-qr --watch | --show | --popup [--link]" >&2
    exit 1
    ;;
esac
