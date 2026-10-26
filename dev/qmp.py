#!/usr/bin/env python3
"""Drive a test VM over QMP: take screenshots and type, as a person at the keyboard would.

usage: qmp.py SOCKET screenshot OUT.png
       qmp.py SOCKET type TEXT          (\\n presses Enter; assumes a US layout in the VM)
       qmp.py SOCKET paste              (types the host clipboard, without pressing Enter)
       qmp.py SOCKET key COMBO...       (e.g. ret, f2, ctrl-alt-f2, shift-tab)

With QMP_KEYMAP=fr, type and paste assume a French AZERTY layout in the VM instead.
"""

import json
import os
import socket
import subprocess
import sys
import time

SHIFTED = {
    "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8",
    "(": "9", ")": "0", "_": "minus", "+": "equal", "{": "bracket_left",
    "}": "bracket_right", ":": "semicolon", '"': "apostrophe", "<": "comma",
    ">": "dot", "?": "slash", "|": "backslash", "~": "grave_accent",
}
PLAIN = {
    " ": "spc", "\n": "ret", "\t": "tab", "-": "minus", "=": "equal",
    "[": "bracket_left", "]": "bracket_right", ";": "semicolon", "'": "apostrophe",
    ",": "comma", ".": "dot", "/": "slash", "\\": "backslash", "`": "grave_accent",
}
# French AZERTY: each character as the keys at their US positions. Digits need Shift.
FRENCH = {
    "a": ("q",), "q": ("a",), "z": ("w",), "w": ("z",), "m": ("semicolon",),
    " ": ("spc",), "\n": ("ret",), "\t": ("tab",),
    "&": ("1",), "é": ("2",), '"': ("3",), "'": ("4",), "(": ("5",), "-": ("6",),
    "è": ("7",), "_": ("8",), "ç": ("9",), "à": ("0",), ")": ("minus",),
    "=": ("equal",), "+": ("shift", "equal"), "ù": ("apostrophe",),
    ",": ("m",), ";": ("comma",), ":": ("dot",), "!": ("slash",),
    "?": ("shift", "m"), ".": ("shift", "comma"), "/": ("shift", "dot"),
    "$": ("bracket_right",), "*": ("backslash",), "%": ("shift", "apostrophe"),
    "<": ("less",), ">": ("shift", "less"),
    "#": ("alt_r", "3"), "{": ("alt_r", "4"), "[": ("alt_r", "5"), "|": ("alt_r", "6"),
    "\\": ("alt_r", "8"), "@": ("alt_r", "0"), "]": ("alt_r", "minus"),
    "}": ("alt_r", "equal"),
}


class QMP:
    def __init__(self, path):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(path)
        self.file = self.sock.makefile("rw")
        self._read()  # greeting
        self.call("qmp_capabilities")

    def _read(self):
        while True:
            msg = json.loads(self.file.readline())
            if "event" not in msg:
                return msg

    def call(self, command, **arguments):
        self.file.write(json.dumps({"execute": command, "arguments": arguments}) + "\n")
        self.file.flush()
        reply = self._read()
        if "error" in reply:
            raise SystemExit(f"qmp {command}: {reply['error']['desc']}")
        return reply.get("return")

    def keys(self, *qcodes):
        self.call("send-key", keys=[{"type": "qcode", "data": k} for k in qcodes])
        time.sleep(0.03)


def keys_for(ch):
    if os.environ.get("QMP_KEYMAP") == "fr":
        return french_keys_for(ch)
    if ch.isascii() and ch.isalpha():
        return ("shift", ch.lower()) if ch.isupper() else (ch,)
    if ch.isdigit():
        return (ch,)
    if ch in PLAIN:
        return (PLAIN[ch],)
    if ch in SHIFTED:
        return ("shift", SHIFTED[ch])
    raise SystemExit(f"can't type {ch!r}")


def french_keys_for(ch):
    if ch.isdigit():
        return ("shift", ch)
    if ch.isascii() and ch.isalpha():
        keys = FRENCH.get(ch.lower(), (ch.lower(),))
        return ("shift",) + keys if ch.isupper() else keys
    if ch in FRENCH:
        return FRENCH[ch]
    raise SystemExit(f"can't type {ch!r} on a French keyboard")


def clipboard():
    for cmd in (["wl-paste", "--no-newline"], ["xclip", "-o", "-selection", "clipboard"]):
        try:
            return subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
        except (OSError, subprocess.CalledProcessError):
            pass
    raise SystemExit("can't read the clipboard: install wl-clipboard or xclip")


def main(argv):
    if len(argv) < 3:
        raise SystemExit(__doc__)
    qmp = QMP(argv[1])
    action, args = argv[2], argv[3:]
    if action == "screenshot":
        qmp.call("screendump", filename=args[0], format="png")
    elif action == "type":
        for ch in " ".join(args).replace("\\n", "\n"):
            qmp.keys(*keys_for(ch))
    elif action == "paste":
        for ch in clipboard().strip():
            qmp.keys(*keys_for(ch))
    elif action == "key":
        for combo in args:
            qmp.keys(*combo.split("-"))
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
