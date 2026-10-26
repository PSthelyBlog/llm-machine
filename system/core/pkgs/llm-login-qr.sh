# llm-login-qr: show Claude's sign-in link as a QR code, so it can be opened on a phone.
#   --watch  wait for the link to appear in the Claude window and pop the code up once
#   --show   pop up the latest link again (F4)
#   --popup  draw the code (runs inside the tmux popup)

URL_FILE=${XDG_RUNTIME_DIR:-/tmp}/llm-login-url

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

case "${1:-}" in
  --watch)
    seen=""
    while ! signed_in; do
      url=$(find_url || true)
      if [ -n "$url" ] && [ "$url" != "$seen" ]; then
        seen=$url
        echo "$url" > "$URL_FILE"
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
    clear
    url=$(cat "$URL_FILE")
    code=$(qrencode -t ANSIUTF8 -m 2 "$url")
    if [ "$(echo "$code" | wc -l)" -gt $(($(tput lines) - 4)) ]; then
      echo "The screen is too small for the QR code. Open the link shown in Claude's window instead."
    else
      echo "Scan with your phone to sign in to Claude:"
      echo "$code"
    fi
    echo "After you approve, the page shows a code. Press any key, then type that code into Claude."
    read -rsn1 _ || true
    ;;
  *)
    echo "usage: llm-login-qr --watch | --show | --popup" >&2
    exit 1
    ;;
esac
