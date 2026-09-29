import json, os, random, string, logging
from urllib.parse import urlparse
import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['TABLE_NAME'])

CORS_HEADERS = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS'
}

def respond(status, body_dict):
    return {'statusCode': status, 'headers': CORS_HEADERS, 'body': json.dumps(body_dict)}

def lambda_handler(event, context):
    try:
        body = json.loads(event.get('body') or '{}')
        original_url = body.get('url')

        if not original_url:
            return respond(400, {'error': 'A "url" field is required'})

        parsed = urlparse(original_url)
        if not all([parsed.scheme, parsed.netloc]):
            return respond(400, {'error': 'Invalid URL format'})

        # Try a few times in case of a random collision
        for _ in range(5):
            short_code = ''.join(random.choices(string.ascii_letters + string.digits, k=6))
            try:
                table.put_item(
                    Item={'shortCode': short_code, 'originalUrl': original_url},
                    ConditionExpression='attribute_not_exists(shortCode)'
                )
                break
            except dynamodb.meta.client.exceptions.ConditionalCheckFailedException:
                continue
        else:
            return respond(500, {'error': 'Could not generate a unique short code'})

        return respond(201, {'shortCode': short_code, 'originalUrl': original_url})

    except Exception as e:
        logger.error(f"Unhandled error: {e}")
        return respond(500, {'error': 'Internal server error'})
