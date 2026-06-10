import json
import boto3

# boto3 is the AWS SDK for Python. `resource` gives a higher-level,
# object-oriented interface to DynamoDB (vs the lower-level `client`).
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table("cloud-resume-visitors")


def lambda_handler(event, context):
    # Atomically add 1 to the `views` attribute of the item id="views".
    # ADD on a number does read-increment-write in a single atomic op on
    # DynamoDB's side, so concurrent visitors can't clobber each other.
    # If the attribute didn't exist, ADD treats it as 0 first.
    response = table.update_item(
        Key={"id": "views"},
        UpdateExpression="ADD #v :inc",
        ExpressionAttributeNames={"#v": "views"},   # #v -> "views" (avoids reserved words)
        ExpressionAttributeValues={":inc": 1},        # :inc -> 1
        ReturnValues="UPDATED_NEW",                   # return the new value
    )

    new_count = int(response["Attributes"]["views"])

    return {
        "statusCode": 200,
        "headers": {
            # Let the browser (served from another origin) read this response.
            "Access-Control-Allow-Origin": "*",
            "Content-Type": "application/json",
        },
        "body": json.dumps({"views": new_count}),
    }
