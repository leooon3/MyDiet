from fastapi import FastAPI, UploadFile, File, HTTPException, Form
from fastapi.responses import JSONResponse
import shutil
import os
import json
import firebase_admin
from firebase_admin import credentials, messaging

from app.core.config import settings
from app.services.diet_service import DietParser
from app.services.receipt_service import ReceiptScanner
from app.services.normalization import normalize_meal_name

# --- FIREBASE INIT ---
# Only initialize if not already initialized (prevents errors on hot-reload)
if not firebase_admin._apps:
    try:
        # Assumes serviceAccountKey.json is in the root 'server/' folder
        cred = credentials.Certificate("serviceAccountKey.json")
        firebase_admin.initialize_app(cred)
        print("🔥 Firebase Admin Initialized")
    except Exception as e:
        print(f"⚠️ Warning: Firebase init failed (Notifications won't work): {e}")

app = FastAPI()

def convert_to_app_format(gemini_output):
    app_plan = {}
    app_substitutions = {}

    # 1. Substitutions
    raw_subs = gemini_output.get('tabella_sostituzioni', [])
    cad_lookup_map = {} 

    for group in raw_subs:
        cad_code = group.get('cad_code', 0)
        titolo = group.get('titolo', "").strip()
        
        if cad_code > 0:
            cad_key = str(cad_code)
            cad_lookup_map[titolo.lower()] = cad_code
            
            options = []
            for opt in group.get('opzioni', []):
                options.append({
                    "name": opt['nome'],
                    "qty": opt['quantita']
                })
            
            if not options: 
                options.append({"name": titolo, "qty": ""})

            app_substitutions[cad_key] = {
                "name": titolo,
                "options": options
            }

    # 2. Weekly Plan
    raw_plan = gemini_output.get('piano_settimanale', [])
    
    for giorno in raw_plan:
        day_name = giorno.get('giorno', 'Sconosciuto').strip().capitalize()
        # Simple day normalization
        for eng, it in [("lun", "Lunedì"), ("mar", "Martedì"), ("mer", "Mercoledì"), 
                        ("gio", "Giovedì"), ("ven", "Venerdì"), ("sab", "Sabato"), ("dom", "Domenica")]:
            if eng in day_name.lower(): day_name = it

        app_plan[day_name] = {}

        for pasto in giorno.get('pasti', []):
            meal_name = normalize_meal_name(pasto.get('tipo_pasto', ''))
            
            items = []
            for piatto in pasto.get('elenco_piatti', []):
                dish_name = piatto['nome_piatto']
                final_cad = piatto.get('cad_code', 0)
                if final_cad == 0:
                    final_cad = cad_lookup_map.get(dish_name.lower(), 0)

                items.append({
                    "name": dish_name,
                    "qty": piatto.get('quantita_totale', ''),
                    "cad_code": final_cad,
                    "is_composed": piatto.get('tipo') == 'composto',
                    "ingredients": piatto.get('ingredienti', [])
                })
            
            if meal_name in app_plan[day_name]:
                app_plan[day_name][meal_name].extend(items)
            else:
                app_plan[day_name][meal_name] = items

    return {
        "plan": app_plan,
        "substitutions": app_substitutions
    }

@app.post("/upload-diet")
async def upload_diet(
    file: UploadFile = File(...),
    fcm_token: str = Form(None) # [NEW] Accept token from Flutter
):
    try:
        print(f"📥 Received PDF: {file.filename}")
        with open(settings.DIET_PDF_PATH, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
            
        parser = DietParser()
        raw_data = parser.parse_complex_diet(settings.DIET_PDF_PATH)
        final_data = convert_to_app_format(raw_data)
        
        with open(settings.DIET_JSON_PATH, "w", encoding="utf-8") as f:
            json.dump(final_data, f, indent=2, ensure_ascii=False)
        
        # [NEW] Send Push Notification
        if fcm_token:
            print(f"🔔 Sending notification to: {fcm_token[:10]}...")
            try:
                message = messaging.Message(
                    notification=messaging.Notification(
                        title="Dieta Pronta! 🥗",
                        body="Il tuo nuovo piano nutrizionale è stato caricato con successo.",
                    ),
                    token=fcm_token,
                )
                response = messaging.send(message)
                print(f"✅ Notification Sent: {response}")
            except Exception as e:
                print(f"⚠️ Notification Failed: {e}")
            
        return JSONResponse(content=final_data)

    except Exception as e:
        print(f"❌ Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/scan-receipt")
async def scan_receipt(file: UploadFile = File(...)):
    try:
        if not os.path.exists(settings.DIET_JSON_PATH):
            raise HTTPException(status_code=400, detail="Load a diet first!")
            
        ext = os.path.splitext(file.filename)[1]
        temp_filename = f"{settings.RECEIPT_PATH_PREFIX}{ext}"
        
        with open(temp_filename, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
            
        scanner = ReceiptScanner(settings.DIET_JSON_PATH)
        found_items = scanner.scan_receipt(temp_filename)
        
        return JSONResponse(content=found_items)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)