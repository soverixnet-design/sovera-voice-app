"""Install a locally supplied Firebase credential; never log its contents.

This installs a file only. It does not activate the game or migrate wallets.
"""
import argparse
import json
import os
from pathlib import Path
import select
import stat
import sys
import termios
import time

LIMIT = 16384
PROJECT = "sovera-app-7d1d6"
EMAIL = f"sovera-game-reader@{PROJECT}.iam.gserviceaccount.com"
EXPOSED_KEY = "b3983449138c7b8a938816d489acf7d6fb0119e2"


def parse_credential(raw):
    if len(raw) > LIMIT:
        raise ValueError("STOP: input too large")
    # Terminal paste wrappers are transport controls, not part of the JSON.
    text = raw.decode("utf-8-sig").replace("\x1b[200~", "").replace("\x1b[201~", "").strip()
    try:
        data = json.loads(text)
    except (ValueError, TypeError):
        raise ValueError("STOP: invalid JSON; copy the complete downloaded file") from None
    if (not isinstance(data, dict) or data.get("type") != "service_account"
            or data.get("project_id") != PROJECT or data.get("client_email") != EMAIL):
        raise ValueError("STOP: wrong project or service account")
    if not data.get("private_key_id") or data["private_key_id"] == EXPOSED_KEY:
        raise ValueError("STOP: missing or previously exposed key")
    key = data.get("private_key")
    if (not isinstance(key, str) or not key.startswith("-----BEGIN PRIVATE KEY-----\n")
            or not key.rstrip().endswith("-----END PRIVATE KEY-----")):
        raise ValueError("STOP: incomplete private key")
    return data


def read_terminal(timeout=120):
    with open("/dev/tty", "rb", buffering=0) as tty:
        saved = termios.tcgetattr(tty)
        hidden = termios.tcgetattr(tty)
        hidden[3] &= ~(termios.ECHO | termios.ECHONL | termios.ICANON)
        hidden[6][termios.VMIN] = 1
        hidden[6][termios.VTIME] = 0
        raw = b""
        try:
            termios.tcsetattr(tty, termios.TCSANOW, hidden)
            print("PASTE_NEW_JSON (hidden; Ctrl+C cancels; 120 second limit)", flush=True)
            deadline = time.monotonic() + timeout
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0 or not select.select([tty], [], [], remaining)[0]:
                    raise ValueError("STOP: paste timed out; no file saved")
                chunk = os.read(tty.fileno(), 4096)
                if not chunk:
                    raise ValueError("STOP: input ended; no file saved")
                raw += chunk
                if len(raw) > LIMIT:
                    raise ValueError("STOP: input too large; no file saved")
                if len(raw) == len(chunk):
                    print("INPUT_RECEIVED (contents hidden)", flush=True)
                clean = raw.replace(b"\x1b[200~", b"").replace(b"\x1b[201~", b"").strip()
                # A copied pretty-printed file ends at the closing object brace.
                # Parse immediately; no extra Enter or endless readline loop.
                if clean.endswith(b"}"):
                    return parse_credential(raw)
        finally:
            termios.tcsetattr(tty, termios.TCSANOW, saved)
            print(flush=True)


def install(data, folder):
    folder = Path(folder)
    folder.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = folder.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid():
        raise ValueError("STOP: unsafe destination directory")
    os.chmod(folder, 0o700)
    target = folder / "firebase-reader.json"
    fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(data, stream)
            stream.flush()
            os.fsync(stream.fileno())
    except BaseException:
        target.unlink(missing_ok=True)
        raise
    return target


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, help="JSON already uploaded privately to this host")
    args = parser.parse_args()
    try:
        if args.source:
            with args.source.open("rb") as stream:
                data = parse_credential(stream.read(LIMIT + 1))
        else:
            data = read_terminal()
        install(data, "/etc/sovera-food")
    except KeyboardInterrupt:
        print("CANCELLED: no credential installed")
        return 1
    except FileExistsError:
        print("STOP: credential file already exists; not overwritten")
        return 1
    except (ValueError, UnicodeError) as error:
        # UnicodeError can include input fragments; never print that exception.
        print(str(error) if type(error) is ValueError else "STOP: input is not UTF-8 JSON")
        return 1
    except OSError:
        print("STOP: terminal or file access failed; no activation performed")
        return 1
    print("CREDENTIAL_SAVED (connection not yet verified; game not activated)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
