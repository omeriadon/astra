#!/usr/bin/env python3
"""Exercise localhost page-open events and record Astra host process snapshots.

WebKit XPC helpers remain unattributed. The output is informational, not a
claim about per-tab memory or completed rendering.
"""
import argparse
import json
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.request import urlopen


class Fixture(BaseHTTPRequestHandler):
    def do_GET(self):
        page = (
            "<!doctype html><html><head><title>Astra CI fixture</title></head><body>"
            "<h1>Local benchmark fixture</h1><main id='content'></main>"
            "<script>document.querySelector('main').textContent = "
            "Array.from({length:100}, (_,i)=>i).join(',');</script>"
            "</body></html>"
        ).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(page)))
        self.end_headers()
        self.wfile.write(page)

    def log_message(self, *_):
        pass


def app_pid():
    p = subprocess.run(["pgrep", "-x", "astra"], capture_output=True, text=True)
    matches = [int(i) for i in p.stdout.split() if i.isdecimal()]
    return matches[0] if len(matches) == 1 else None


def open_app(app, url=None):
    subprocess.run(["open", "-a", str(app)] + ([url] if url else []),
                   check=True, capture_output=True, text=True)


def sample(pid, name, directory, benchmark):
    destination = directory / f"{name}.json"
    subprocess.run(
        [sys.executable, str(benchmark), "snapshot", "--pid", str(pid),
         "--interval", "7", "--output", str(destination)],
        check=True, timeout=35,
    )
    data = json.loads(destination.read_text())
    if pid in data["after"]["unavailable_selected_pids"]:
        raise RuntimeError("Astra exited during sampling")
    return data


def run(app, directory):
    directory.mkdir(parents=True, exist_ok=True)
    if app_pid() is not None:
        raise RuntimeError("Astra is already running on the CI runner")
    benchmark = Path(__file__).resolve().parents[1] / "webkit_benchmark.py"
    server = ThreadingHTTPServer(("127.0.0.1", 0), Fixture)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    host = f"http://127.0.0.1:{server.server_address[1]}"
    results = {}
    try:
        open_app(app)
        pid = None
        for _ in range(120):
            pid = app_pid()
            if pid:
                break
            time.sleep(0.5)
        if pid is None:
            raise RuntimeError("No Astra process; the runner may not support foreground GUI apps")
        time.sleep(5)
        results["empty_tab"] = sample(pid, "empty_tab", directory, benchmark)
        open_app(app, host + "/one")
        time.sleep(5)
        results["one_local_page"] = sample(pid, "one_local_page", directory, benchmark)
        for i in range(10):
            open_app(app, host + f"/tab-{i}")
        time.sleep(8)
        results["ten_opened_urls"] = sample(pid, "ten_opened_urls", directory, benchmark)
        rows = []
        for name, result in results.items():
            after = result["after"]
            host_data = after["totals"]["astra"]
            footprint = host_data["footprint_bytes"]
            rows.append({
                "scenario": name,
                "host_rss_mib": round(host_data["rss_bytes"] / 1048576, 1),
                "host_footprint_mib": round(footprint / 1048576, 1) if footprint is not None else None,
                "host_cpu_pct_one_core": round(result["cpu_percent_of_one_core"]["astra"], 1),
                "unattributed_webkit_pids": len(after["unattributed_webkit_processes"]),
            })
        (directory / "scenario-results.json").write_text(json.dumps(rows, indent=2) + "\n")
        md = [
            "## Astra localhost WebKit workload — informational", "",
            "Process measurements after initial launch, one local webpage and ten additional URL-open events.",
            "CPU is percentage of one core over seven seconds.", "",
            "| Scenario | Astra host RSS | Astra footprint | Astra CPU | Unattributed WebKit PIDs |",
            "|---|---:|---:|---:|---:|",
        ]
        for row in rows:
            fp = ("unavailable" if row["host_footprint_mib"] is None
                  else f"{row['host_footprint_mib']:.1f} MiB")
            md.append(
                f"| {row['scenario']} | {row['host_rss_mib']:.1f} MiB | "
                f"{fp} | {row['host_cpu_pct_one_core']:.1f}% | {row['unattributed_webkit_pids']} |"
            )
        md += [
            "", "**Limits:** WebKit XPC helper memory is not attributed to Astra. "
            "These are host-process measurements, not total browser memory, "
            "per-tab usage, frame times or proof that every webpage rendered. "
            "Hosted runner variation prevents stable performance thresholds."
        ]
        summary = "\n".join(md) + "\n"
        (directory / "webkit-summary.md").write_text(summary)
        print(summary)
    finally:
        server.shutdown()
        try:
            subprocess.run(
                ["osascript", "-e", 'tell application id "com.omeriadon.astra" to quit'],
                timeout=15, capture_output=True,
            )
        except (OSError, subprocess.TimeoutExpired):
            pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("app", nargs="?")
    parser.add_argument("--output-dir")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        server = ThreadingHTTPServer(("127.0.0.1", 0), Fixture)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with urlopen(f"http://127.0.0.1:{server.server_address[1]}/test") as result:
                assert result.status == 200
                assert b"Astra CI fixture" in result.read()
        finally:
            server.shutdown()
        print("WebKit local fixture self-test passed")
        return
    if not args.app or not args.output_dir:
        parser.error("app and --output-dir are required")
    app = Path(args.app)
    if not app.is_dir():
        parser.error("App not found: " + str(app))
    run(app, Path(args.output_dir))


if __name__ == "__main__":
    main()
