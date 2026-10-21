"""Verify the Docker proxy transformation without changing a live server."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

class ProxyConfigTests(unittest.TestCase):
    def fixture(self):
        return {'storage': {'module': 'file_system', 'root': '/data'}, 'apps': {
            'tls': {'certificates': {'automate': ['voice.soverixnet.com', 'turn.soverixnet.com']}},
            'layer4': {'servers': {'main': {'listen': [':443'], 'routes': [
                {'match': [{'tls': {'sni': ['turn.soverixnet.com']}}], 'handle': [{'handler': 'proxy', 'upstreams': [{'dial': ['206.189.238.27:5349']}]}]},
                {'match': [{'tls': {'sni': ['voice.soverixnet.com']}}], 'handle': [{'handler': 'proxy', 'upstreams': [{'dial': ['127.0.0.1:7882']}]}]}]}}},
            'http': {'servers': {'sovera': {'listen': ['127.0.0.1:7882'], 'routes': [{'handle': [{'handler': 'reverse_proxy', 'upstreams': [{'dial': '127.0.0.1:7880'}]}]}]}}}}}

    def transform(self, config):
        script = Path(__file__).with_name('install_control.sh').read_text()
        program = script.split("<<'CADDY_JSON'\n", 1)[1].split('\nCADDY_JSON', 1)[0]
        with tempfile.TemporaryDirectory() as directory:
            src, dst = Path(directory)/'source.json', Path(directory)/'output.json'
            src.write_text(json.dumps(config))
            result = subprocess.run([sys.executable, '-c', program, str(src), str(dst)], capture_output=True)
            return result.returncode, json.loads(dst.read_text()) if dst.exists() else None

    def test_preserves_voice_turn_and_isolates_admin(self):
        before = self.fixture()
        code, after = self.transform(before)
        self.assertEqual(code, 0)
        self.assertEqual(after['apps']['http']['servers']['sovera'], before['apps']['http']['servers']['sovera'])
        routes = after['apps']['layer4']['servers']['main']['routes']
        self.assertEqual(routes[1:], before['apps']['layer4']['servers']['main']['routes'])
        self.assertEqual(routes[0]['match'], [{'tls': {'sni': ['admin.soverixnet.com']}}])
        admin = after['apps']['http']['servers']['sovera_control']
        self.assertEqual(admin['listen'], ['127.0.0.1:7883'])
        self.assertEqual(admin['routes'][0]['match'], [{'host': ['admin.soverixnet.com']}])
        api = admin['routes'][0]['handle'][1]['routes'][0]
        self.assertEqual(api['match'], [{'path': ['/sovera/control/*']}])
        self.assertTrue(api['terminal'])
        self.assertEqual(admin['routes'][-1]['handle'][0]['status_code'], 404)

    def test_rejects_existing_admin_and_port_conflict(self):
        config = self.fixture()
        config['apps']['tls']['certificates']['automate'].append('admin.soverixnet.com')
        self.assertNotEqual(self.transform(config)[0], 0)
        config = self.fixture()
        config['apps']['http']['servers']['other'] = {'listen': ['127.0.0.1:7883']}
        self.assertNotEqual(self.transform(config)[0], 0)

if __name__ == '__main__':
    unittest.main()
