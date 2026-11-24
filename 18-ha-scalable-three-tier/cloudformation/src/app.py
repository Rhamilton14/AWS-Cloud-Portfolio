"""Application tier: a small web app that runs on each EC2 instance.

It counts visits in DynamoDB and reports which instance and Availability Zone
served the request, so you can watch the load balancer spread traffic.
Uses only the Python standard library plus boto3 (no internet access needed).
"""
import json
import os
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import boto3

TABLE = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])
IMDS = "http://169.254.169.254/latest"


def metadata(path):
    """Read instance metadata using IMDSv2 (token required)."""
    token_req = urllib.request.Request(
        f"{IMDS}/api/token", method="PUT",
        headers={"X-aws-ec2-metadata-token-ttl-seconds": "300"},
    )
    token = urllib.request.urlopen(token_req, timeout=2).read().decode()
    req = urllib.request.Request(f"{IMDS}/meta-data/{path}", headers={"X-aws-ec2-metadata-token": token})
    return urllib.request.urlopen(req, timeout=2).read().decode()


INSTANCE_ID = metadata("instance-id")
AZ = metadata("placement/availability-zone")


class Handler(BaseHTTPRequestHandler):
    def _send(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/health":
            return self._send(200, {"status": "ok"})

        if self.path == "/":
            result = TABLE.update_item(
                Key={"pk": "visits"},
                UpdateExpression="ADD hits :one",
                ExpressionAttributeValues={":one": 1},
                ReturnValues="UPDATED_NEW",
            )
            return self._send(200, {
                "message": "Hello from the three-tier app",
                "total_visits": int(result["Attributes"]["hits"]),
                "served_by": INSTANCE_ID,
                "availability_zone": AZ,
            })

        return self._send(404, {"error": "Not found"})


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
