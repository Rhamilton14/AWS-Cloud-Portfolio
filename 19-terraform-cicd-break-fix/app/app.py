"""Tiny web app for project 19. Standard library only, so the servers need no internet access."""
import json
import os
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

APP_VERSION = os.environ.get("APP_VERSION", "dev")
PORT = int(os.environ.get("APP_PORT", "8080"))


def instance_metadata(path):
    """Read EC2 instance metadata with IMDSv2 (a session token is required)."""
    try:
        token_req = urllib.request.Request(
            "http://169.254.169.254/latest/api/token",
            method="PUT",
            headers={"X-aws-ec2-metadata-token-ttl-seconds": "60"},
        )
        token = urllib.request.urlopen(token_req, timeout=1).read().decode()
        req = urllib.request.Request(
            f"http://169.254.169.254/latest/meta-data/{path}",
            headers={"X-aws-ec2-metadata-token": token},
        )
        return urllib.request.urlopen(req, timeout=1).read().decode()
    except OSError:
        return "unknown"


INSTANCE_ID = instance_metadata("instance-id")
AZ = instance_metadata("placement/availability-zone")


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            self.send_json(200, {"status": "ok", "version": APP_VERSION})
        elif self.path == "/":
            body = (
                "<h1>Hello from project 19</h1>"
                f"<p>Version <b>{APP_VERSION}</b> served by <b>{INSTANCE_ID}</b> in <b>{AZ}</b></p>"
                "<p>Refresh to watch the load balancer switch servers.</p>"
            )
            self.send_body(200, "text/html", body.encode())
        else:
            self.send_json(404, {"error": "not found"})

    def send_json(self, code, payload):
        self.send_body(code, "application/json", json.dumps(payload).encode())

    def send_body(self, code, content_type, body):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        # One line per request in the journal: `journalctl -u webapp`
        print(f"{self.address_string()} {fmt % args}", flush=True)


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
