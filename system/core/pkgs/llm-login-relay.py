"""Hand Claude's sign-in code over from a phone, so nobody has to type it.

usage: llm-login-relay PORT URL_FILE ADDRESS_FILE

While Claude waits for its sign-in code in the tty1 session, this serves one page on the
local network with the sign-in link (read from URL_FILE) and a box for the code. The page
lives at a secret address, written to ADDRESS_FILE for the QR code. A code is accepted only
for the sign-in on screen, where its state (the part after #) matches the link's, and is
then typed into Claude's window.
"""

import html
import os
import re
import secrets
import signal
import socket
import subprocess
import sys
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer
from string import Template

PORT, URL_FILE, ADDRESS_FILE = int(sys.argv[1]), sys.argv[2], sys.argv[3]
TOKEN = secrets.token_hex(16)
HOST = html.escape(socket.gethostname())
CODE = re.compile(r"[A-Za-z0-9_-]+(#[A-Za-z0-9_-]+)?")

PAGE = Template("""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Sign in to Claude on $host</title>
<style>
  body { font: 17px/1.5 system-ui, sans-serif; max-width: 28em; margin: 0 auto; padding: 1em 16px; }
  .button { display: block; box-sizing: border-box; width: 100%; padding: .8em; border: 0; border-radius: .5em;
            background: #c96442; color: #fff; font: inherit; text-align: center; text-decoration: none; }
  input { display: block; box-sizing: border-box; width: 100%; margin: .5em 0; padding: .7em; font: inherit; }
  .error { color: #b3261e; font-weight: bold; }
</style>
</head>
<body>
<h1>Sign in to Claude on $host</h1>
$body
</body>
</html>
""")

FORM = Template("""$error
<p>1. Open the sign-in page and approve.</p>
<a class="button" href="$url" target="_blank" rel="noreferrer">Open the Claude sign-in page</a>
<p>2. It then shows a code. Copy it, come back to this tab, and paste it here.</p>
<form method="post">
  <input name="code" autocomplete="off" autocapitalize="off" autocorrect="off" spellcheck="false"
         placeholder="Paste the code here">
  <button class="button">Send the code to $host</button>
</form>
""")

SENT = Template("""<p>Sent. $host is signing in now: look at its screen.</p>
<p>If Claude says the code didn't work, press Enter there to try again, then
<a href="">start over here</a>.</p>
""")


def sign_in_url():
    try:
        with open(URL_FILE) as f:
            return f.read().strip()
    except OSError:
        return ""


def hand_over(code):
    def tmux(*args):
        subprocess.run(["tmux", *args], check=False, capture_output=True)

    tmux("display-popup", "-C", "-t", "main")
    tmux("send-keys", "-t", "main:claude", "-l", code)
    time.sleep(0.5)  # let Claude take the text in before Enter submits it
    tmux("send-keys", "-t", "main:claude", "Enter")


class Handler(BaseHTTPRequestHandler):
    server_version = "llm-machine"
    sys_version = ""

    def log_message(self, *args):
        pass

    def page(self, status, body):
        data = PAGE.substitute(host=HOST, body=body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Referrer-Policy", "no-referrer")
        self.end_headers()
        self.wfile.write(data)

    def form(self, status, error=""):
        error = f'<p class="error">{error}</p>' if error else ""
        self.page(status, FORM.substitute(host=HOST, url=html.escape(sign_in_url()), error=error))

    def do_GET(self):
        if self.path != "/" + TOKEN:
            return self.send_error(404)
        self.form(200)

    def do_POST(self):
        if self.path != "/" + TOKEN:
            return self.send_error(404)
        length = min(int(self.headers.get("Content-Length") or 0), 4096)
        fields = urllib.parse.parse_qs(self.rfile.read(length).decode(errors="replace"))
        # Phones sometimes add spaces or a line break around pasted text.
        code = "".join(fields.get("code", [""])[0].split())
        query = urllib.parse.urlparse(sign_in_url()).query
        state = urllib.parse.parse_qs(query).get("state", [""])[0]

        if not state:
            return self.form(409, "Claude isn't waiting for a sign-in code right now.")
        if not CODE.fullmatch(code):
            return self.form(400, "That doesn't look like a sign-in code. Copy it again "
                                  "(the page has a Copy button) and paste it here.")
        if "#" in code and code.split("#")[1] != state:
            return self.form(400, "That code is from an earlier sign-in. Open the sign-in "
                                  "page again from here and use the new code.")
        hand_over(code.split("#")[0] + "#" + state)
        self.page(200, SENT.substitute(host=HOST))


def lan_address():
    # Connecting a UDP socket sends nothing; it only picks the outgoing address.
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.connect(("192.0.2.1", 9))
        return s.getsockname()[0]


def main():
    server = HTTPServer(("", PORT), Handler)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    try:
        with open(ADDRESS_FILE, "w") as f:
            f.write(f"http://{lan_address()}:{PORT}/{TOKEN}\n")
        server.serve_forever()
    finally:
        try:
            os.remove(ADDRESS_FILE)
        except OSError:
            pass


if __name__ == "__main__":
    main()
