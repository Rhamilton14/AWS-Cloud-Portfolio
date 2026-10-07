import hashlib
import json


def lambda_handler(event, context):
    # CPU-heavy work: hash a value 200,000 times
    value = b"Rhart90"
    for _ in range(200_000):
        value = hashlib.sha256(value).digest()
    return {"statusCode": 200, "body": json.dumps({"result": value.hex()[:16]})}
