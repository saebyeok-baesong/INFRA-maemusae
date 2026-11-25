import json
import os
import urllib.request

import boto3

# eks.sh 가 매일 ops DB 를 끄고 켤 때 나는 이벤트. 최대 정지 기간(7일)을 넘겨 RDS 가 스스로 켠 RDS-EVENT-0154 는 알린다
SKIP_EVENT_IDS = frozenset({"RDS-EVENT-0087", "RDS-EVENT-0088"})

_webhook_url = None


def webhook_url():
    global _webhook_url
    if _webhook_url is None:
        secret = boto3.client("secretsmanager").get_secret_value(SecretId=os.environ["WEBHOOK_SECRET_ID"])
        _webhook_url = secret["SecretString"].strip()
    return _webhook_url


def rds_event(m):
    # SNS 로 오는 Event ID 는 ...USER_Events.html#RDS-EVENT-0088 같은 문서 링크다
    event_id = m["Event ID"].rsplit("#", 1)[-1]
    if event_id in SKIP_EVENT_IDS:
        return None
    return f"**RDS {m['Source ID']}** {event_id}\n{m['Event Message']}\n{m['Identifier Link']}"


def alarm(m):
    return f"**{m['NewStateValue']}** {m['AlarmName']}\n{m['NewStateReason']}"


SHAPES = (("Event ID", rds_event), ("AlarmName", alarm))


def format_message(raw):
    try:
        m = json.loads(raw)
    except ValueError:
        return raw
    if isinstance(m, dict):
        for key, fmt in SHAPES:
            if key in m:
                return fmt(m)
    return raw


def post(content):
    req = urllib.request.Request(
        webhook_url(),
        data=json.dumps({"content": content[:2000]}).encode(),
        # Discord 는 urllib 기본 User-Agent 를 403 으로 막는다
        headers={"Content-Type": "application/json", "User-Agent": "maemusae-discord-alerts"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        resp.read()


def handler(event, context):
    for record in event["Records"]:
        content = format_message(record["Sns"]["Message"])
        if content:
            post(content)
