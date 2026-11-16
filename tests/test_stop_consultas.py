"""Offline regression checks for emergency interruption; no real services or clients."""
import importlib.util
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import Mock

spec = importlib.util.spec_from_file_location("stop_consultas",
    Path(__file__).resolve().parents[1] / "scripts" / "stop-consultas.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class EmergencyStopTests(unittest.TestCase):
    def test_stop_precedes_kill_and_no_restart(self):
        run = Mock(return_value=SimpleNamespace(stdout="ActiveState=inactive\nMainPID=0\n"))
        module.stop_services(run=run, sleep=Mock())
        commands = [c.args[0] for c in run.call_args_list]
        self.assertEqual(commands[0][:3], ["systemctl", "stop", "--no-block"])
        self.assertIn("--signal=SIGKILL", commands[1])
        self.assertTrue(all("start" not in c and "restart" not in c for c in commands))
        self.assertEqual(len(commands), 4)

    def test_active_executor_blocks_requeue(self):
        run = Mock(return_value=SimpleNamespace(stdout="ActiveState=active\nMainPID=42\n"))
        with self.assertRaises(RuntimeError):
            module.stop_services(run=run, sleep=Mock())

    def test_only_processing_rows_requeued_without_quota(self):
        request = Mock(return_value=[])
        module.requeue(request)
        self.assertEqual(request.call_count, 6)
        for call in request.call_args_list:
            path = call.args[0]
            self.assertIn("status=eq.processando", path)
            self.assertNotIn("rpc/", path)
            if len(call.args) == 2:
                payload = call.args[1]
                self.assertEqual(payload["status"], "aguardando")
                self.assertIsNone(payload["locked_at"])
                self.assertNotIn("attempts", payload)
                self.assertNotIn("execution_mode", payload)
        self.assertIsNone(module.PAYLOADS["amigoz_jobs"]["lease"])

    def test_failure_attempts_other_queues_and_reports_incomplete(self):
        def request(path, payload=None):
            if path.startswith("consulta_jobs"):
                raise OSError("SECRET must never appear")
            return []
        with self.assertRaises(RuntimeError) as caught:
            module.requeue(request)
        self.assertIn("consulta_jobs", str(caught.exception))
        self.assertNotIn("SECRET", str(caught.exception))

    def test_remaining_processing_rows_are_not_reported_as_success(self):
        request = Mock(return_value=[{"id": "still-running"}])
        with self.assertRaises(RuntimeError):
            module.requeue(request)

if __name__ == "__main__":
    unittest.main()
