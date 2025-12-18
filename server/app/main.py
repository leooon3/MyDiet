import os
import json
import uuid
import aiofiles
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
        cred = credentials.ApplicationDefault()
        firebase_admin.initialize_app(cred)
        print("🔥 Firebase initialized via ApplicationDefault credentials.")
    except Exception as e:
        print(f"❌ Critical Firebase Init Error: {e}")

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
        async with aiofiles.open(temp_filename, 'wb') as out_file:
            while content := await file.read(1024 * 1024):
                await out_file.write(content)
            
        raw_data = diet_parser.parse_complex_diet(temp_filename)
        final_data = _convert_to_app_format(raw_data)
        
        if fcm_token:
            notification_service.send_diet_ready(fcm_token)
            
        return JSONResponse(content=final_data)

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Processing Error: {str(e)}")
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
        try:
            food_list = json.loads(allowed_foods)
        except json.JSONDecodeError:
            raise ValueError("allowed_foods must be a valid JSON string")

        if not isinstance(food_list, list):
            raise ValueError("allowed_foods must be a JSON list of strings")

        async with aiofiles.open(temp_filename, 'wb') as out_file:
            while content := await file.read(1024 * 1024):
                await out_file.write(content)
            
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
                # [FIX] Safer string conversion for main dish
                dish_name = str(piatto.get('nome_piatto') or 'Piatto')
                final_cad = piatto.get('cad_code', 0)
                if final_cad == 0:
                    final_cad = cad_lookup_map.get(dish_name.lower(), 0)

                # [FIX] Safer string conversion for ingredients (Prevents None)
                formatted_ingredients = []
                for ing in piatto.get('ingredienti', []):
                    formatted_ingredients.append({
                        "name": str(ing.get('nome') or ''),
                        "qty": str(ing.get('quantita') or '')
                    })

                items.append({
                    "name": dish_name,
                    "qty": str(piatto.get('quantita_totale') or ''),
                    "cad_code": final_cad,
                    "is_composed": piatto.get('tipo') == 'composto',
                    "ingredients": formatted_ingredients
                })
            
            if meal_name in app_plan[day_name]:
                app_plan[day_name][meal_name].extend(items)
            else:
                app_plan[day_name][meal_name] = items

    return {
        "plan": app_plan,
        "substitutions": app_substitutions
    }