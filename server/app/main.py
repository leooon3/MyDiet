import os
import json
import uuid
import shutil
from typing import Optional

import firebase_admin
from firebase_admin import credentials, auth
from fastapi import FastAPI, UploadFile, File, HTTPException, Form, Header, Depends
from fastapi.responses import JSONResponse

from app.services.diet_service import DietParser
from app.services.receipt_service import ReceiptScanner
from app.services.notification_service import NotificationService
from app.services.normalization import normalize_meal_name

# --- FIREBASE SETUP ---
if not firebase_admin._apps:
    try:
        # Tries to load the Service Account from GOOGLE_APPLICATION_CREDENTIALS
        cred = credentials.ApplicationDefault()
        firebase_admin.initialize_app(cred)
        print("Firebase initialized with Service Account.")
    except Exception as e:
        print(f"Warning: Could not load Service Account ({e}). Fallback to manual ID.")
        # FALLBACK: If Env Var is missing, you MUST paste your Project ID below
        firebase_admin.initialize_app(options={
            'projectId': 'INSERISCI_QUI_IL_TUO_PROJECT_ID' 
        })

app = FastAPI()

# Initialize Services
notification_service = NotificationService()
diet_parser = DietParser()

# --- SECURITY DEPENDENCY ---
async def verify_token(authorization: str = Header(...)):
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Invalid auth header format")
    
    token = authorization.split("Bearer ")[1]
    try:
        decoded_token = auth.verify_id_token(token)
        
        # ACTIVE MODE: Security Check
        if not decoded_token.get('email_verified', False):
            raise HTTPException(status_code=403, detail="Email verification required")
            
        return decoded_token['uid'] 
    except ValueError as e:
        raise HTTPException(status_code=403, detail=str(e))
    except Exception as e:
        print(f"Auth Error: {e}")
        raise HTTPException(status_code=401, detail="Invalid or expired token")

# --- ENDPOINTS ---

@app.post("/upload-diet")
async def upload_diet(
    file: UploadFile = File(...),
    fcm_token: Optional[str] = Form(None),
    user_id: str = Depends(verify_token) 
):
    temp_filename = f"{uuid.uuid4()}.pdf"
    
    try:
        with open(temp_filename, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
            
        raw_data = diet_parser.parse_complex_diet(temp_filename)
        final_data = _convert_to_app_format(raw_data)
        
        if fcm_token:
            notification_service.send_diet_ready(fcm_token)
            
        return JSONResponse(content=final_data)

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if os.path.exists(temp_filename):
            os.remove(temp_filename)

@app.post("/scan-receipt")
async def scan_receipt(
    file: UploadFile = File(...),
    allowed_foods: str = Form(...),
    user_id: str = Depends(verify_token) 
):
    temp_filename = f"{uuid.uuid4()}{os.path.splitext(file.filename)[1]}"
    
    try:
        food_list = json.loads(allowed_foods)
        if not isinstance(food_list, list):
            raise ValueError("allowed_foods must be a JSON list of strings")

        with open(temp_filename, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
            
        current_scanner = ReceiptScanner(allowed_foods_list=food_list)
        found_items = current_scanner.scan_receipt(temp_filename)
        
        return JSONResponse(content=found_items)

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if os.path.exists(temp_filename):
            os.remove(temp_filename)

def _convert_to_app_format(gemini_output):
    app_plan = {}
    app_substitutions = {}

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

    raw_plan = gemini_output.get('piano_settimanale', [])
    
    for giorno in raw_plan:
        day_name = giorno.get('giorno', 'Sconosciuto').strip().capitalize()
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