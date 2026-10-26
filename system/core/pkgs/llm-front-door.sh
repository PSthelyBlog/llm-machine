# llm-front-door: get the machine online and signed in to Claude, then hand over to Claude.

REPO=${LLM_MACHINE_REPO:-/etc/llm-machine}
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/llm-machine

# Any HTTP answer from the API means DNS, routing, TLS and the clock all work.
online() { [ "$(curl -s -o /dev/null -m 5 -w '%{http_code}' https://api.anthropic.com/ || true)" != 000 ]; }
signed_in() { [ -s "$HOME/.claude/.credentials.json" ] || [ -n "${ANTHROPIC_API_KEY:-}" ]; }

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
  if [ -e /var/lib/osctl/pending-boot ]; then
    # Back from a trial reboot: continue the conversation that started it.
    claude --continue "The computer has restarted into the change on trial. Check with me that it works, then keep or undo it, and carry on." || true
  elif [ -f "$STATE/setup-done" ]; then
    claude || true
  elif [ -f "$STATE/setup-started" ]; then
    claude --continue "/setup" || true
  else
    touch "$STATE/setup-started"
    claude "/setup" || true
  fi
  [ -z "$watcher" ] || kill "$watcher" 2>/dev/null || true

  echo
  echo "   Claude has exited. Press Enter to start it again, or F2 for a shell."
  read -r _ || true
done
