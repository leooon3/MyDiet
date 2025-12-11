# Usage: python broadcast.py "Server Maintenance" "Down for 1 hour"
import sys
from firebase_admin import messaging
# ... init code ...

def send_broadcast(title, body, topic='all_users'):
    message = messaging.Message(
        notification=messaging.Notification(title=title, body=body),
        topic=topic,
    )
    messaging.send(message)

if __name__ == "__main__":
    send_broadcast(sys.argv[1], sys.argv[2])