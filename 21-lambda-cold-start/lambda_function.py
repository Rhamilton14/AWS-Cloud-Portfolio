import json
import os
import time

# Everything at module level runs once per execution environment, during the
# INIT phase. That is the part of a cold start you control.
_init_start = time.perf_counter()

# HEAVY_INIT=true imports boto3 and creates a client at init, the way many real
# functions do. HEAVY_INIT=false keeps init to the standard library only.
HEAVY_INIT = os.environ.get("HEAVY_INIT", "false").lower() == "true"
if HEAVY_INIT:
    import boto3

    s3 = boto3.client("s3")

INIT_MS = round((time.perf_counter() - _init_start) * 1000, 1)
_is_cold = True


def lambda_handler(event, context):
    global _is_cold
    cold = _is_cold
    _is_cold = False

    result = {
        "cold_start": cold,
        "heavy_init": HEAVY_INIT,
        "module_init_ms": INIT_MS,
        "memory_mb": int(context.memory_limit_in_mb),
        "init_type": os.environ.get("AWS_LAMBDA_INITIALIZATION_TYPE"),
    }
    # One JSON line per invoke, so CloudWatch Logs Insights can query it
    print(json.dumps(result))
    return {"statusCode": 200, "body": json.dumps(result)}
