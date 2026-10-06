import json
import boto3
import os

ddb = boto3.client("dynamodb")
TABLE_NAME = os.environ["TABLE_NAME"]

def lambda_handler(event, context):
    action = event.get("action")

    if action == "check_connectivity":
        table = ddb.describe_table(TableName=TABLE_NAME)
        return {
            "statusCode": 200,
            "body": json.dumps({
                "message": "Connected!",
                "table": TABLE_NAME,
                "status": table["Table"]["TableStatus"]
            })
        }

    elif action == "put_item":
        item_id = event.get("id", "item-1")
        item_name = event.get("name", "My Item")
        ddb.put_item(
            TableName=TABLE_NAME,
            Item={
                "id":   {"S": item_id},
                "name": {"S": item_name}
            }
        )
        return {
            "statusCode": 200,
            "body": json.dumps({"message": "Item created", "id": item_id})
        }

    elif action == "get_item":
        item_id = event.get("id", "item-1")
        response = ddb.get_item(
            TableName=TABLE_NAME,
            Key={"id": {"S": item_id}}
        )
        item = response.get("Item")
        if not item:
            return {
                "statusCode": 404,
                "body": json.dumps({"error": "Item not found", "id": item_id})
            }
        return {
            "statusCode": 200,
            "body": json.dumps({"item": item})
        }

    elif action == "delete_item":
        item_id = event.get("id")
        if not item_id:
            return {
                "statusCode": 400,
                "body": json.dumps({"error": "Missing 'id' in event"})
            }
        ddb.delete_item(
            TableName=TABLE_NAME,
            Key={"id": {"S": item_id}}
        )
        return {
            "statusCode": 200,
            "body": json.dumps({"message": "Item deleted", "id": item_id})
        }

    return {
        "statusCode": 400,
        "body": json.dumps({"error": f"Action '{action}' not implemented yet"})
    }
