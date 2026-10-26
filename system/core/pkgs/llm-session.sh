# llm-session: the front door on tty1. Claude runs in the first tmux window and a plain
# shell in the second, so the machine stays usable when Claude can't be.

if tmux -L llm-machine has-session -t main 2>/dev/null; then
  exec tmux -L llm-machine attach-session -t main
fi

exec tmux -L llm-machine -f @tmuxConf@ \
  new-session -s main -n claude llm-front-door \; \
  new-window -d -n shell 'while true; do bash -l; done'
