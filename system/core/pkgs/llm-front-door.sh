# llm-front-door: get the machine online and signed in to Claude, then hand over to Claude.

REPO=${LLM_MACHINE_REPO:-/etc/llm-machine}
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/llm-machine

# Any HTTP answer from the API means DNS, routing, TLS and the clock all work.
online() { [ "$(curl -s -o /dev/null -m 5 -w '%{http_code}' https://api.anthropic.com/ || true)" != 000 ]; }
signed_in() { [ -s "$HOME/.claude/.credentials.json" ] || [ -n "${ANTHROPIC_API_KEY:-}" ]; }
# Claude saves a folder's conversations in ~/.claude/projects/<its path, with every
# character other than a letter or digit turned into ->.
has_conversation() {
  local saved=("$HOME/.claude/projects/${PWD//[^a-zA-Z0-9]/-}"/*.jsonl)
  [ -e "${saved[0]}" ]
}

banner() {
  clear
  cat <<'EOF'

   llm-machine

   This computer is set up and looked after by Claude. Ask for what you want,
   and Claude changes the system for you. Every change can be undone.

EOF
}

while true; do
  banner

  until online; do
    echo "   This computer is not connected to the internet, and Claude needs a connection."
    echo "   Opening the network settings: choose your Wi-Fi network, then Quit."
    sleep 3
    nmtui connect || true
    banner
  done

  watcher=""
  if ! signed_in && [ -n "${TMUX:-}" ]; then
    echo "   Next, sign in to Claude. When the sign-in link appears, it is also shown as a"
    echo "   QR code: scan it with your phone, approve, and type the code you get back here."
    echo "   (F4 shows the QR code again.)"
    sleep 4
    llm-login-qr --watch &
    watcher=$!
  fi

  cd "$REPO" 2>/dev/null || cd "$HOME"
  mkdir -p "$STATE"
  # Carry on with the last conversation, unless there is none yet: the computer can
  # restart before Claude has saved anything, for example during sign-in.
  resume=()
  ! has_conversation || resume=(--continue)
  if [ -e /var/lib/osctl/pending-boot ]; then
    claude "${resume[@]}" "The computer has restarted into the change on trial. Check with me that it works, then keep or undo it, and carry on." || true
  elif [ -f "$STATE/setup-done" ]; then
    claude || true
  else
    claude "${resume[@]}" "/setup" || true
  fi
  [ -z "$watcher" ] || kill "$watcher" 2>/dev/null || true

  echo
  echo "   Claude has exited. Press Enter to start it again, or F2 for a shell."
  read -r _ || true
done
