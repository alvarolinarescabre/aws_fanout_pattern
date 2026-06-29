import json
import logging
import os
import uuid
import time

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

DDB_TABLE_NAME = os.getenv('DDB_TABLE_NAME')
CONSUMER_ID = os.getenv('CONSUMER_ID', 'unknown')


def _save_to_dynamodb(message_id, body, queue_arn):
    if not DDB_TABLE_NAME:
        logger.warning('DDB_TABLE_NAME not set — skipping persist')
        return
    region = os.getenv('AWS_REGION', 'us-east-1')
    client = boto3.client('dynamodb', region_name=region)
    client.put_item(
        TableName=DDB_TABLE_NAME,
        Item={
            'id':          {'S': str(uuid.uuid4())},
            'message_id':  {'S': message_id},
            'consumer_id': {'S': CONSUMER_ID},
            'body':        {'S': body},
            'queue_arn':   {'S': queue_arn},
            'processed_at': {'N': str(int(time.time()))},
        },
    )


def _maybe_slow_down():
    """If SLOW_CONSUMER env var set, sleep to simulate long processing.

    This extends the SQS InFlight window so you can observe processing.
    """
    slow = os.getenv('SLOW_CONSUMER')
    if slow and slow != '0':
        try:
            secs = int(os.getenv('SLOW_CONSUMER_SECONDS', '15'))
        except Exception:
            secs = 15
        logging.getLogger().info('SLOW_CONSUMER active: sleeping %s seconds', secs)
        time.sleep(secs)


def handler(event, context):
    records = event.get('Records', [])
    logger.info('Received %d records (consumer=%s)', len(records), CONSUMER_ID)

    for r in records:
        message_id = r.get('messageId', 'unknown')
        body = r.get('body', '')
        queue_arn = r.get('eventSourceARN', '')
        logger.info('Processing messageId=%s consumer=%s', message_id, CONSUMER_ID)
        _maybe_slow_down()
        # Allow simulated failures for testing/debugging.
        # Trigger by either setting FORCE_FAIL=1 in the Lambda env or by
        # publishing a JSON body containing {"force_fail": true}.
        should_fail = False
        if os.getenv('FORCE_FAIL') == '1':
            should_fail = True
        else:
            try:
                parsed = json.loads(body)
                if isinstance(parsed, dict) and parsed.get('force_fail'):
                    should_fail = True
            except Exception:
                # body not JSON — ignore
                pass

        try:
            if should_fail:
                logger.error('Simulated consumer failure for messageId=%s consumer=%s', message_id, CONSUMER_ID)
                raise RuntimeError('Simulated consumer failure')

            _save_to_dynamodb(message_id, body, queue_arn)
        except Exception:
            logger.exception('Failed to save messageId=%s to DynamoDB', message_id)
            raise  # re-raise so SQS retries and eventually sends to DLQ

    return {'statusCode': 200, 'body': json.dumps({'processed': len(records)})}
