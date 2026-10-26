# llm-resume: in a graphical session, bring Claude back in a terminal while setup is
# unfinished or a change is waiting to be confirmed after a trial reboot.

STATE=${XDG_STATE_HOME:-$HOME/.local/state}/llm-machine

if [ -e /var/lib/osctl/pending-boot ] || [ ! -f "$STATE/setup-done" ]; then
  exec @terminal@ llm-front-door
fi
