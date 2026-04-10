#!/usr/bin/env python3
"""Ask your GIT — Native Messaging Host for terminal command execution."""

import json
import struct
import subprocess
import sys


def read_message():
    raw_length = sys.stdin.buffer.read(4)
    if len(raw_length) < 4:
        return None
    length = struct.unpack("=I", raw_length)[0]
    data = sys.stdin.buffer.read(length)
    return json.loads(data.decode("utf-8"))


def send_message(obj):
    encoded = json.dumps(obj).encode("utf-8")
    sys.stdout.buffer.write(struct.pack("=I", len(encoded)))
    sys.stdout.buffer.write(encoded)
    sys.stdout.buffer.flush()


def detect_terminal():
    """Detect the frontmost terminal app."""
    script = '''
    tell application "System Events"
        set frontApp to name of first application process whose frontmost is true
    end tell
    return frontApp
    '''
    try:
        result = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True, text=True, timeout=5
        )
        app = result.stdout.strip()
        if app in ("Terminal", "iTerm2", "Warp"):
            return app
    except Exception:
        pass
    return None


def send_to_terminal(command, terminal):
    """Send command to the specified terminal app and bring it to front."""
    if terminal == "iTerm2":
        script = f'''
        tell application "iTerm2"
            activate
            tell current session of current window
                write text {json.dumps(command)}
            end tell
        end tell
        '''
    elif terminal == "Warp":
        script = f'''
        tell application "Warp"
            activate
            tell application "System Events"
                keystroke {json.dumps(command)}
                key code 36
            end tell
        end tell
        '''
    else:
        # Terminal.app (default)
        terminal = "Terminal"
        script = f'''
        tell application "Terminal"
            activate
            if (count of windows) > 0 then
                do script {json.dumps(command)} in front window
            else
                do script {json.dumps(command)}
            end if
        end tell
        '''

    subprocess.run(["osascript", "-e", script], capture_output=True, timeout=10)
    return terminal


def main():
    msg = read_message()
    if not msg:
        send_message({"success": False, "error": "No input"})
        return

    command = msg.get("command", "")
    preferred = msg.get("terminal", "auto")

    if not command:
        send_message({"success": False, "error": "Empty command"})
        return

    # Security: only allow known command patterns
    import re
    ALLOWED_PATTERNS = [
        r'^git clone https?://[^\s;|&]+',          # git clone
        r'^claude\s',                                # claude code
        r'^codex\s',                                 # codex cli
        r'^open -a\s',                               # open app (Cursor etc)
    ]
    if not any(re.match(p, command) for p in ALLOWED_PATTERNS):
        send_message({"success": False, "error": "Command not allowed"})
        return

    try:
        if preferred == "auto":
            terminal = detect_terminal() or "Terminal"
        else:
            terminal = preferred

        used = send_to_terminal(command, terminal)
        send_message({"success": True, "app": used})
    except Exception as e:
        send_message({"success": False, "error": str(e)})


if __name__ == "__main__":
    main()
