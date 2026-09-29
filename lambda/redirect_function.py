import os, logging
import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['TABLE_NAME'])

def html_response(status, message):
    return {'statusCode': status, 'headers': {'Content-Type': 'text/html'}, 'body': f'<h1>{message}</h1>'}

def lambda_handler(event, context):
    short_code = (event.get('pathParameters') or {}).get('shortCode')

    if not short_code or len(short_code) != 6 or not short_code.isalnum():
        return html_response(400, '400 - Invalid short code')

    try:
        response = table.get_item(Key={'shortCode': short_code})
    except ClientError as e:
        logger.error(f"DynamoDB error: {e}")
        return html_response(500, '500 - Internal server error')

    item = response.get('Item')
    if not item:
        return html_response(404, '404 - Short URL not found')

    return {
        'statusCode': 302,
        'headers': {'Location': item['originalUrl'], 'Cache-Control': 'no-cache'}
    }
