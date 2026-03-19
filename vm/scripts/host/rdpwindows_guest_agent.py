#!/usr/bin/env python3

import argparse
import base64
import json
import subprocess
import sys
import time
from typing import Any


class GuestAgentError(RuntimeError):
    pass


class RdpWindowsGuestAgent:
    def __init__(self, vm_name: str, connect_uri: str = "qemu:///system") -> None:
        self.vm_name = vm_name
        self.connect_uri = connect_uri

    def _virsh(self, payload: dict[str, Any]) -> dict[str, Any]:
        result = subprocess.run(
            [
                "virsh",
                "--connect",
                self.connect_uri,
                "qemu-agent-command",
                self.vm_name,
                json.dumps(payload),
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        return json.loads(result.stdout)

    def ping(self) -> None:
        self._virsh({"execute": "guest-ping"})

    def exec(
        self,
        path: str,
        args: list[str] | None = None,
        timeout: int = 300,
        capture_output: bool = True,
    ) -> dict[str, Any]:
        payload = {
            "execute": "guest-exec",
            "arguments": {
                "path": path,
                "arg": args or [],
                "capture-output": capture_output,
            },
        }
        response = self._virsh(payload)
        pid = response["return"]["pid"]
        deadline = time.time() + timeout

        while time.time() < deadline:
            status = self._virsh(
                {"execute": "guest-exec-status", "arguments": {"pid": pid}}
            )["return"]
            if status.get("exited"):
                stdout = base64.b64decode(status.get("out-data", "") or b"").decode(
                    "utf-8", "replace"
                )
                stderr = base64.b64decode(status.get("err-data", "") or b"").decode(
                    "utf-8", "replace"
                )
                return {
                    "exitcode": status.get("exitcode", 0),
                    "stdout": stdout,
                    "stderr": stderr,
                    "raw": status,
                }
            time.sleep(1)

        raise GuestAgentError(f"Timed out waiting for guest command pid={pid}")

    def powershell(self, command: str, timeout: int = 300) -> dict[str, Any]:
        return self.exec(
            r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe",
            [
                "-NoLogo",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-Command",
                command,
            ],
            timeout=timeout,
        )

    def cmd(self, command: str, timeout: int = 300) -> dict[str, Any]:
        return self.exec(
            r"C:\Windows\System32\cmd.exe",
            ["/c", command],
            timeout=timeout,
        )

    def reboot(self) -> None:
        try:
            self._virsh({"execute": "guest-shutdown", "arguments": {"mode": "reboot"}})
        except Exception:
            self.exec(
                r"C:\Windows\System32\shutdown.exe",
                ["/r", "/t", "0", "/f"],
                timeout=30,
                capture_output=False,
            )

    def wait_for_ping(self, timeout: int = 600, interval: int = 5) -> None:
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                self.ping()
                return
            except Exception:
                time.sleep(interval)
        raise GuestAgentError("Timed out waiting for guest agent to respond.")

    def guest_info(self) -> dict[str, Any]:
        return self._virsh({"execute": "guest-info"})["return"]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--vm-name", default="RDPWindows")
    parser.add_argument("--connect-uri", default="qemu:///system")
    parser.add_argument("--ping", action="store_true")
    parser.add_argument("--guest-info", action="store_true")
    parser.add_argument("--cmd")
    parser.add_argument("--powershell")
    parser.add_argument("--timeout", type=int, default=300)
    args = parser.parse_args()

    guest = RdpWindowsGuestAgent(vm_name=args.vm_name, connect_uri=args.connect_uri)

    try:
        if args.ping:
            guest.ping()
            print("guest-ping ok")
            return 0

        if args.guest_info:
            print(json.dumps(guest.guest_info(), indent=2))
            return 0

        if args.cmd:
            result = guest.cmd(args.cmd, timeout=args.timeout)
            print(result["stdout"], end="")
            if result["stderr"]:
                print(result["stderr"], file=sys.stderr, end="")
            return int(result["exitcode"])

        if args.powershell:
            result = guest.powershell(args.powershell, timeout=args.timeout)
            print(result["stdout"], end="")
            if result["stderr"]:
                print(result["stderr"], file=sys.stderr, end="")
            return int(result["exitcode"])

        parser.error("Specify one of --ping, --guest-info, --cmd, or --powershell.")
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
