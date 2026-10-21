import json
import os
from pathlib import Path
import pty
import select
import signal
import stat
import tempfile
import time
import unittest

from server.food.install_credential import EMAIL, EXPOSED_KEY, PROJECT, install, parse_credential


def sample():
    return dict(type="service_account", project_id=PROJECT, client_email=EMAIL,
                private_key_id="synthetic-test-key",
                private_key="-----BEGIN PRIVATE KEY-----\nSYNTHETIC_NOT_A_KEY\n-----END PRIVATE KEY-----\n")


class CredentialTests(unittest.TestCase):
    def test_paste_controls_and_wrong_or_exposed_credentials(self):
        raw = json.dumps(sample()).encode()
        self.assertEqual(parse_credential(b"\x1b[200~" + raw + b"\x1b[201~"), sample())
        for change in ({"project_id": "wrong"}, {"client_email": "wrong"},
                       {"private_key_id": EXPOSED_KEY}, {"private_key": "truncated"}):
            with self.assertRaises(ValueError):
                parse_credential(json.dumps(sample() | change).encode())

    def test_private_permissions_no_overwrite_and_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            folder = Path(root) / "credentials"
            target = install(sample(), folder)
            self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(folder.stat().st_mode), 0o700)
            with self.assertRaises(FileExistsError):
                install(sample() | {"private_key_id": "different"}, folder)
            self.assertEqual(json.loads(target.read_text()), sample())
            link = Path(root) / "link"
            link.symlink_to(folder, target_is_directory=True)
            with self.assertRaises(ValueError):
                install(sample(), link)

    def test_real_terminal_long_paste_no_enter_and_no_secret_echo(self):
        pid, master = pty.fork()
        if pid == 0:
            try:
                from server.food.install_credential import read_terminal
                data = read_terminal(timeout=3)
                print("PARSED_OK" if data["project_id"] == PROJECT else "FAILED", flush=True)
                os._exit(0)
            except BaseException:
                os._exit(1)
        output = b""
        try:
            end = time.monotonic() + 5
            sent = False
            while time.monotonic() < end:
                if select.select([master], [], [], 0.1)[0]:
                    try:
                        chunk = os.read(master, 16384)
                    except OSError:
                        break
                    if not chunk:
                        break
                    output += chunk
                if b"PASTE_NEW_JSON" in output and not sent:
                    # Larger than a canonical terminal line buffer; no final Enter.
                    raw = json.dumps(sample() | {"padding": "x" * 5000}).encode()
                    os.write(master, b"\x1b[200~" + raw + b"\x1b[201~")
                    sent = True
                if b"PARSED_OK" in output:
                    break
            self.assertIn(b"INPUT_RECEIVED", output)
            self.assertIn(b"PARSED_OK", output)
            self.assertNotIn(b"SYNTHETIC_NOT_A_KEY", output)
        finally:
            os.close(master)
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            os.waitpid(pid, 0)


if __name__ == "__main__":
    unittest.main()
