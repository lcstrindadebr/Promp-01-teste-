"""Regression coverage for installer preflight failure classification."""
import sys, unittest
from pathlib import Path
from unittest.mock import patch, MagicMock
from urllib.error import HTTPError, URLError
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import configure_supabase as config

class ProbeTests(unittest.TestCase):
    def test_http_errors(self):
        for status in (400,401,403,404,429,500,502,503,504):
            with self.subTest(status=status), patch.object(config, 'time') as clock:
                def fail(*args, **kwargs):
                    raise HTTPError('https://example.test',status,'unavailable',{},None)
                with patch.object(config,'urlopen',side_effect=fail) as call:
                    with self.assertRaises(config.ProbeError) as caught:
                        config.check_endpoint('https://example.test','/rest/v1/consulta_jobs',{})
                    self.assertEqual(caught.exception.exit_code,75 if status in (429,500,502,503,504) else 1)
                    self.assertEqual(call.call_count,2 if status>=500 else 1)
    def test_timeout(self):
        with patch.object(config,'urlopen',side_effect=URLError(TimeoutError())), patch.object(config,'time'):
            with self.assertRaises(config.ProbeError) as caught:
                config.check_endpoint('https://example.test','/auth/v1/settings',{})
            self.assertEqual(caught.exception.exit_code,75)
    def test_recovery(self):
        response=MagicMock()
        response.__enter__.return_value=response
        with patch.object(config,'urlopen',side_effect=[TimeoutError(),response]), patch.object(config,'time'):
            config.check_endpoint('https://example.test','/auth/v1/settings',{})
    def test_invalid_credentials_still_fail_closed(self):
        with self.assertRaises(ValueError):
            config.validate('https://abcdefghijklmnopqrst.supabase.co','sb_secret_wrong','sb_secret_test')

if __name__=='__main__': unittest.main()
