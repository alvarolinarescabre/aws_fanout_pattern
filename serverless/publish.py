import json
import sys
from pathlib import Path

import boto3


def load_outputs():
    p = Path(__file__).resolve().parent.parent / 'terraform' / 'outputs.json'
    if not p.exists():
        print(f"outputs.json not found at {p}")
        sys.exit(1)
    return json.loads(p.read_text())


def publish(message: str, simulate_failure: bool = False):
    if simulate_failure:
        print('Simulating failure before SNS publish...')
        print('Simulated publish failure')
        sys.exit(0)

    outputs = load_outputs()
    sns_arn = outputs.get('sns_topic_arn')
    if not sns_arn:
        print('sns_topic_arn missing in outputs.json')
        sys.exit(1)

    region = sns_arn.split(':')[3]
    client = boto3.client('sns', region_name=region)
    resp = client.publish(TopicArn=sns_arn, Message=message)
    print('Published message, MessageId:', resp.get('MessageId'))


if __name__ == '__main__':
    # Flags
    fail_flags = {'--fail', '--simulate-failure'}
    structured_flags = {'--structured', '--json'}

    args = [arg for arg in sys.argv[1:] if arg not in fail_flags and arg not in structured_flags]
    simulate_failure = any(f in sys.argv[1:] for f in fail_flags)
    use_structured = any(f in sys.argv[1:] for f in structured_flags)

    if use_structured:
        payload = {
            'event': 'fanout-demo',
            'message': 'This payload is intentionally verbose so the queue body and downstream logs are easier to inspect.',
            'sections': [
                {'name': 'Section A', 'body': 'A-' * 80},
                {'name': 'Section B', 'body': 'B-' * 80},
                {'name': 'Section C', 'body': 'C-' * 80},
            ],
            'metadata': {
                'source': 'publish.py',
                'environment': 'demo',
                'tags': ['fanout', 'sqs', 'sns', 'visible-payload'],
            },
        }
        msg = json.dumps(payload, indent=2)
    elif args:
        msg = ' '.join(args)
    else:
        payload = {
            'event': 'fanout-demo',
            'message': 'This payload is intentionally verbose so the queue body and downstream logs are easier to inspect.',
            'sections': [
                {'name': 'Section A', 'body': 'A-' * 80},
                {'name': 'Section B', 'body': 'B-' * 80},
                {'name': 'Section C', 'body': 'C-' * 80},
            ],
            'metadata': {
                'source': 'publish.py',
                'environment': 'demo',
                'tags': ['fanout', 'sqs', 'sns', 'visible-payload'],
            },
        }
        msg = json.dumps(payload, indent=2)

    publish(msg, simulate_failure=simulate_failure)
