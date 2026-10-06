import json

import boto3
from botocore.exceptions import ClientError

bedrock = boto3.client("bedrock-runtime")

MODEL_ID = "amazon.nova-micro-v1:0"
MAX_QUESTION_CHARS = 500   # cost control: cap input size
MAX_ANSWER_TOKENS = 300    # cost control: cap output size
SYSTEM_PROMPT = (
    "You are an AWS study helper. Answer questions about AWS in 3 sentences "
    "or fewer, in plain language for a beginner."
)


def lambda_handler(event, context):
    # API Gateway sends the body as a string; a console test may send a dict
    body = event.get("body") or "{}"
    if isinstance(body, str):
        try:
            body = json.loads(body)
        except json.JSONDecodeError:
            return respond(400, {"error": "Body must be valid JSON"})

    question = (body.get("question") or "").strip()
    if not question:
        return respond(400, {"error": 'Send JSON like {"question": "What is S3?"}'})
    if len(question) > MAX_QUESTION_CHARS:
        return respond(400, {"error": f"Question must be {MAX_QUESTION_CHARS} characters or fewer"})

    try:
        result = bedrock.converse(
            modelId=MODEL_ID,
            system=[{"text": SYSTEM_PROMPT}],
            messages=[{"role": "user", "content": [{"text": question}]}],
            inferenceConfig={"maxTokens": MAX_ANSWER_TOKENS, "temperature": 0.3},
        )
    except ClientError as e:
        print(json.dumps({"event": "bedrock_error", "error": str(e)}))
        return respond(502, {"error": "The AI model could not answer right now"})

    answer = result["output"]["message"]["content"][0]["text"]
    usage = result["usage"]

    # One structured log line per call, searchable in CloudWatch Logs Insights
    print(json.dumps({
        "event": "bedrock_call",
        "model": MODEL_ID,
        "inputTokens": usage["inputTokens"],
        "outputTokens": usage["outputTokens"],
        "latencyMs": result["metrics"]["latencyMs"],
    }))

    return respond(200, {
        "question": question,
        "answer": answer,
        "model": MODEL_ID,
        "usage": {"inputTokens": usage["inputTokens"], "outputTokens": usage["outputTokens"]},
    })


def respond(status, payload):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(payload),
    }
