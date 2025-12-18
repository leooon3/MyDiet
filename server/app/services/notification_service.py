import firebase_admin
from firebase_admin import credentials, messaging
import os

class NotificationService:
    _initialized = False

    def __init__(self):
        if not NotificationService._initialized:
            self._init_firebase()
            NotificationService._initialized = True

    def _init_firebase(self):
        # Prevent double init
        if firebase_admin._apps:
            return

        key_path = "serviceAccountKey.json"
        if os.path.exists(key_path):
            try:
                cred = credentials.Certificate(key_path)
                firebase_admin.initialize_app(cred)
                print("🔥 Firebase Admin Initialized")
            except Exception as e:
                print(f"⚠️ Firebase Init Error: {e}")
        else:
            print("⚠️ serviceAccountKey.json not found. Notifications disabled.")
            
    def send_diet_ready(self, fcm_token: str) -> None:
        if not fcm_token or not isinstance(fcm_token, str):
            print("⚠️ Skipping notification: Invalid FCM token")
            return
        
        try:
            message = messaging.Message(
                notification=messaging.Notification(
                    title="Dieta Pronta! 🥗",
                    body="Il tuo piano nutrizionale è stato elaborato."
                ),
                token=fcm_token,
            )
            response = messaging.send(message)
            print(f"✅ Notification sent: {response}")
        except Exception as e:
            print(f"⚠️ Notification Error: {e}")