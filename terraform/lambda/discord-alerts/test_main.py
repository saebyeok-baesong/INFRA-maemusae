import json
import pathlib
import sys
import types

sys.dont_write_bytecode = True
sys.modules["boto3"] = types.SimpleNamespace(client=lambda name: None)
sys.path.insert(0, str(pathlib.Path(__file__).parent))
import main  # noqa: E402

sent = []
main.post = sent.append


def sns(message):
    return {"Records": [{"Sns": {"Message": message}}]}


def rds(event_id, text):
    return json.dumps({
        "Event Source": "db-instance",
        "Source ID": "maemusae-ops",
        "Event ID": f"http://docs.amazonwebservices.com/AmazonRDS/latest/UserGuide/USER_Events.html#{event_id}",
        "Event Message": text,
        "Identifier Link": "https://console.aws.amazon.com/rds/home?region=ap-northeast-2#dbinstance:id=maemusae-ops",
    })


main.handler(sns(rds("RDS-EVENT-0087", "DB instance stopped")), None)
main.handler(sns(rds("RDS-EVENT-0088", "DB instance started")), None)
assert sent == [], "daily ops stop/start is skipped"

main.handler(sns(rds("RDS-EVENT-0154", "DB instance is being started due to it exceeding the maximum allowed time being stopped.")), None)
assert sent[-1].startswith("**RDS maemusae-ops** RDS-EVENT-0154\nDB instance is being started"), sent[-1]
assert "dbinstance:id=maemusae-ops" in sent[-1], "rds message keeps the console link"

main.handler(sns(json.dumps({"AlarmName": "maemusae-ops-cpu", "NewStateValue": "ALARM", "NewStateReason": "Threshold Crossed"})), None)
assert sent[-1] == "**ALARM** maemusae-ops-cpu\nThreshold Crossed", sent[-1]

main.handler(sns("plain text"), None)
main.handler(sns('["json", "but not a known shape"]'), None)
assert sent[-2:] == ["plain text", '["json", "but not a known shape"]'], sent[-2:]

print("ok")
