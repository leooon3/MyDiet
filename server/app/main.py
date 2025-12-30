import os
import uuid
import structlog
import aiofiles
import json
from typing import Optional, List, Dict

import firebase_admin
from firebase_admin import credentials, auth, firestore

from fastapi import FastAPI, UploadFile, File, HTTPException, Form, Header, Depends, Request
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.concurrency import run_in_threadpool
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from pydantic import Json, BaseModel

# --- IMPORTS ---
from app.services.diet_service import DietParser
from app.services.receipt_service import ReceiptScanner
from app.services.notification_service import NotificationService
from app.services.normalization import normalize_meal_name
from app.core.config import settings
from app.models.schemas import DietResponse, Dish, Ingredient, SubstitutionGroup, SubstitutionOption
# [ADDED] Import for broadcasting notifications
from app.broadcast import broadcast_message 

# --- CONFIGURATION ---
MAX_FILE_SIZE = 10 * 1024 * 1024
ALLOWED_EXTENSIONS = {".jpg", ".jpeg", ".png", ".pdf", ".webp"}

MEAL_ORDER = [
    "Colazione",
    "Seconda Colazione",
    "Spuntino",
    "Pranzo",
    "Merenda",
    "Cena",
    "Spuntino Serale",
    "Nell'Arco Della Giornata"
]

structlog.configure(
    processors=[
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.JSONRenderer()
    ],
    logger_factory=structlog.stdlib.LoggerFactory(),
)
logger = structlog.get_logger()

# --- FIREBASE INIT ---
if not firebase_admin._apps:
    try:
        if os.getenv("GOOGLE_APPLICATION_CREDENTIALS"):
            cred = credentials.ApplicationDefault()
            firebase_admin.initialize_app(cred)
            logger.info("firebase_init", method="env_vars")
        elif os.path.exists("serviceAccountKey.json"):
            cred = credentials.Certificate("serviceAccountKey.json")
            firebase_admin.initialize_app(cred)
            logger.info("firebase_init", method="file")
        else:
            logger.warning("firebase_init_fail", reason="no_credentials")
    except Exception as e:
        logger.error("firebase_init_critical_error", error=str(e))

limiter = Limiter(key_func=get_remote_address)
app = FastAPI()
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "POST", "OPTIONS", "DELETE"],
    allow_headers=["Authorization", "Content-Type"],
)

notification_service = NotificationService()
diet_parser = DietParser()

# --- SCHEMAS ---
class CreateUserRequest(BaseModel):
    email: str
    password: str
    role: str
    first_name: str
    last_name: str
    parent_id: Optional[str] = None

class MaintenanceRequest(BaseModel):
    enabled: bool

class ScheduleMaintenanceRequest(BaseModel):
    scheduled_time: str
    message: str
    notify: bool

# --- UTILS & SECURITY ---

async def save_upload_file(file: UploadFile, filename: str) -> None:
    size = 0
    try:
        async with aiofiles.open(filename, 'wb') as out_file:
            while content := await file.read(1024 * 1024):
                size += len(content)
                if size > MAX_FILE_SIZE:
                    raise HTTPException(status_code=413, detail="File too large")
                await out_file.write(content)
    except Exception as e:
        if os.path.exists(filename):
            os.remove(filename)
        raise e

def validate_extension(filename: str) -> str:
    ext = os.path.splitext(filename)[1].lower()
    if ext not in ALLOWED_EXTENSIONS:
        raise HTTPException(status_code=400, detail="Invalid file type")
    return ext

async def verify_token(authorization: str = Header(...)):
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Invalid auth header")
    
    parts = authorization.split("Bearer ")
    if len(parts) < 2:
        raise HTTPException(status_code=401, detail="Invalid token format")
        
    token = parts[1].strip()
    if not token:
         raise HTTPException(status_code=401, detail="Empty token")

    try:
        decoded_token = await run_in_threadpool(auth.verify_id_token, token)
        return decoded_token['uid'] 
    except Exception as e:
        logger.warning("auth_failed", error=str(e), error_type=type(e).__name__)
        raise HTTPException(status_code=401, detail="Authentication failed")

# [ADDED] Helper to verify Admin Role
async def verify_admin(uid: str = Depends(verify_token)):
    try:
        db = firebase_admin.firestore.client()
        user_doc = db.collection('users').document(uid).get()
        if not user_doc.exists:
             raise HTTPException(status_code=403, detail="User not found")
             
        user_data = user_doc.to_dict()
        if user_data.get('role') != 'admin':
            raise HTTPException(status_code=403, detail="Admin privileges required")
            
        return uid
    except HTTPException:
        raise
    except Exception as e:
        logger.error("admin_verification_error", error=str(e))
        raise HTTPException(status_code=500, detail="Authorization check failed")

# --- ENDPOINTS ---

@app.post("/upload-diet", response_model=DietResponse)
@limiter.limit("5/minute")
async def upload_diet(
    request: Request,
    file: UploadFile = File(...),
    fcm_token: Optional[str] = Form(None),
    user_id: str = Depends(verify_token) 
):
    if not file.filename.lower().endswith('.pdf'):
        raise HTTPException(status_code=400, detail="Only PDF allowed")

    temp_filename = f"{uuid.uuid4()}.pdf"
    log = logger.bind(user_id=user_id, filename=file.filename)
    
    try:
        await save_upload_file(file, temp_filename)
        log.info("file_upload_success")
        
        raw_data = await run_in_threadpool(diet_parser.parse_complex_diet, temp_filename)
        final_data = _convert_to_app_format(raw_data)

        if fcm_token:
            await run_in_threadpool(notification_service.send_diet_ready, fcm_token)
            
        return final_data

    except HTTPException:
        raise
    except Exception as e:
        log.error("diet_process_failed", error=str(e))
        raise HTTPException(status_code=500, detail="Processing failed")
    finally:
        if os.path.exists(temp_filename):
            os.remove(temp_filename)

@app.post("/upload-diet/{target_uid}", response_model=DietResponse)
@limiter.limit("10/minute")
async def upload_diet_admin(
    request: Request,
    target_uid: str,
    file: UploadFile = File(...),
    fcm_token: Optional[str] = Form(None),
    requester_id: str = Depends(verify_token) 
):
    if not file.filename.lower().endswith('.pdf'):
        raise HTTPException(status_code=400, detail="Only PDF allowed")

    temp_filename = f"{uuid.uuid4()}.pdf"
    log = logger.bind(admin_id=requester_id, target_uid=target_uid, filename=file.filename)
    
    try:
        await save_upload_file(file, temp_filename)
        log.info("admin_upload_start")
        
        db = firebase_admin.firestore.client()
        custom_prompt = None
        
        user_doc = db.collection('users').document(target_uid).get()
        if user_doc.exists:
            user_data = user_doc.to_dict()
            parent_id = user_data.get('parent_id')
            if parent_id:
                parent_doc = db.collection('users').document(parent_id).get()
                if parent_doc.exists:
                    custom_prompt = parent_doc.to_dict().get('custom_parser_prompt')

        raw_data = await run_in_threadpool(
            diet_parser.parse_complex_diet, 
            temp_filename, 
            custom_prompt
        )
        final_data = _convert_to_app_format(raw_data)

        if fcm_token:
            await run_in_threadpool(notification_service.send_diet_ready, fcm_token)
            
        log.info("admin_upload_success", used_custom_parser=bool(custom_prompt))
        return final_data

    except HTTPException:
        raise
    except Exception as e:
        log.error("admin_upload_failed", error=str(e))
        raise HTTPException(status_code=500, detail="Processing failed")
    finally:
        if os.path.exists(temp_filename):
            os.remove(temp_filename)

@app.post("/scan-receipt")
@limiter.limit("10/minute")
async def scan_receipt(
    request: Request,
    file: UploadFile = File(...),
    allowed_foods: Json[List[str]] = Form(...),
    user_id: str = Depends(verify_token) 
):
    ext = validate_extension(file.filename)
    temp_filename = f"{uuid.uuid4()}{ext}"
    log = logger.bind(user_id=user_id, task="receipt_scan")
    
    try:
        await save_upload_file(file, temp_filename)
        
        current_scanner = ReceiptScanner(allowed_foods_list=allowed_foods)
        found_items = await run_in_threadpool(current_scanner.scan_receipt, temp_filename)
        
        log.info("scan_success", items_found=len(found_items))
        return JSONResponse(content=found_items)

    except HTTPException:
        raise
    except Exception as e:
        log.error("scan_failed", error=str(e))
        raise HTTPException(status_code=500, detail="Scanning failed")
    finally:
        if os.path.exists(temp_filename):
            os.remove(temp_filename)

# --- ADMIN MANAGEMENT ENDPOINTS ---

@app.post("/admin/create-user")
async def admin_create_user(
    body: CreateUserRequest,
    requester_id: str = Depends(verify_admin)  # Updated to use verify_admin
):
    try:
        db = firebase_admin.firestore.client()
        requester_doc = db.collection('users').document(requester_id).get()
        
        final_parent_id = body.parent_id
        if requester_doc.exists:
            requester_data = requester_doc.to_dict()
            if requester_data.get('role', 'user') == 'nutritionist':
                final_parent_id = requester_id
        
        user = auth.create_user(
            email=body.email,
            password=body.password,
            display_name=f"{body.first_name} {body.last_name}",
            email_verified=True
        )

        auth.set_custom_user_claims(user.uid, {'role': body.role})

        db.collection('users').document(user.uid).set({
            'uid': user.uid,
            'email': body.email,
            'role': body.role,
            'first_name': body.first_name, 
            'last_name': body.last_name,   
            'parent_id': final_parent_id,
            'is_active': True,
            'created_at': firebase_admin.firestore.SERVER_TIMESTAMP,
            'created_by': requester_id,
            'requires_password_change': True 
        })
        
        logger.info("user_created", uid=user.uid, role=body.role)
        return {"uid": user.uid, "message": "User created and verified"}

    except Exception as e:
        logger.error("create_user_failed", error=str(e))
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/admin/delete-user/{target_uid}")
async def admin_delete_user(
    target_uid: str,
    requester_id: str = Depends(verify_admin)
):
    try:
        try:
            auth.delete_user(target_uid)
        except auth.UserNotFoundError:
            logger.warning("ghost_user_deletion", uid=target_uid)

        db = firebase_admin.firestore.client()
        db.collection('users').document(target_uid).delete()

        logger.info("user_deleted", uid=target_uid, admin=requester_id)
        return {"message": "User deleted successfully"}

    except Exception as e:
        logger.error("delete_user_failed", error=str(e))
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/admin/sync-users")
async def admin_sync_users(requester_id: str = Depends(verify_admin)):
    try:
        db = firebase_admin.firestore.client()
        page = auth.list_users()
        count = 0
        
        while page:
            for user in page.users:
                doc_ref = db.collection('users').document(user.uid)
                doc = doc_ref.get()
                if not doc.exists:
                    doc_ref.set({
                        'uid': user.uid,
                        'email': user.email,
                        'role': 'independent',
                        'is_active': True,
                        'first_name': user.display_name.split(' ')[0] if user.display_name else 'App',
                        'last_name': '',
                        'created_at': firebase_admin.firestore.SERVER_TIMESTAMP,
                        'synced_by_admin': True,
                        'requires_password_change': False
                    })
                    count += 1
            page = page.get_next_page()
            
        return {"message": f"Sync complete. Restored {count} users."}

    except Exception as e:
        logger.error("sync_failed", error=str(e))
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/admin/upload-parser/{target_uid}")
async def upload_parser_config(
    target_uid: str,
    file: UploadFile = File(...),
    requester_id: str = Depends(verify_admin)
):
    if not file.filename.lower().endswith(".txt"):
        raise HTTPException(status_code=400, detail="Parser must be a .txt file")

    try:
        content_bytes = await file.read()
        custom_instructions = content_bytes.decode("utf-8")

        db = firebase_admin.firestore.client()
        db.collection('users').document(target_uid).update({
            'custom_parser_prompt': custom_instructions,
            'has_custom_parser': True
        })

        logger.info("parser_updated", uid=target_uid, admin=requester_id)
        return {"message": "Custom Parser instructions saved successfully."}

    except Exception as e:
        logger.error("parser_upload_failed", error=str(e))
        raise HTTPException(status_code=500, detail=str(e))

# --- SYSTEM CONFIG & MAINTENANCE ---

@app.get("/admin/config/maintenance")
async def get_maintenance_status(requester_id: str = Depends(verify_admin)):
    try:
        db = firebase_admin.firestore.client()
        config_ref = db.collection('config').document('global')
        doc = config_ref.get()
        if doc.exists:
            data = doc.to_dict()
            return {"enabled": data.get('maintenance_mode', False)}
        return {"enabled": False}

    except Exception as e:
        logger.error("maintenance_read_error", error=str(e))
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/admin/config/maintenance")
async def set_maintenance_status(
    body: MaintenanceRequest,
    requester_id: str = Depends(verify_admin)
):
    try:
        db = firebase_admin.firestore.client()
        config_ref = db.collection('config').document('global')
        config_ref.set({
            'maintenance_mode': body.enabled,
            'updated_at': firebase_admin.firestore.SERVER_TIMESTAMP,
            'updated_by': requester_id
        }, merge=True)
        return {"message": f"Maintenance Mode is now {body.enabled}"}

    except Exception as e:
        logger.error("maintenance_write_error", error=str(e))
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/admin/schedule-maintenance")
async def schedule_maintenance(
    req: ScheduleMaintenanceRequest, 
    admin_uid: str = Depends(verify_admin)
):
    try:
        db = firebase_admin.firestore.client()
        # 1. Save schedule to Firestore
        db.collection('config').document('global').set({
            "scheduled_maintenance_start": req.scheduled_time,
            "maintenance_message": req.message,
            "is_scheduled": True
        }, merge=True)

        # 2. Broadcast Notification
        sent_count = 0
        if req.notify:
            try:
                # Assuming app subscribes to 'all_users' topic
                response = broadcast_message(
                    title="System Update",
                    body=req.message,
                    data={"type": "maintenance_alert", "time": req.scheduled_time}
                )
                sent_count = 1 # broadcast returns an id, not count, but success means sent
                logger.info("maintenance_broadcast_sent", admin=admin_uid)
            except Exception as e:
                logger.error("broadcast_error", error=str(e))
                # Don't fail the request if just notification fails, but warn
                
        return {"status": "scheduled", "notifications_sent": sent_count}
        
    except Exception as e:
        logger.error("schedule_maintenance_error", error=str(e))
        raise HTTPException(status_code=500, detail=str(e))

# --- HELPER FUNCTIONS ---

def _convert_to_app_format(gemini_output) -> DietResponse:
    if not gemini_output:
        return DietResponse(plan={}, substitutions={})

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
                options.append(SubstitutionOption(
                    name=opt.get('nome', 'Unknown'),
                    qty=opt.get('quantita', '')
                ))
            
            if not options: 
                options.append(SubstitutionOption(name=titolo, qty=""))

            app_substitutions[cad_key] = SubstitutionGroup(
                name=titolo,
                options=options
            )

    raw_plan = gemini_output.get('piano_settimanale', [])
    
    DAY_MAPPING = {
        "lun": "Lunedì", "mon": "Lunedì",
        "mar": "Martedì", "tue": "Martedì",
        "mer": "Mercoledì", "wed": "Mercoledì",
        "gio": "Giovedì", "thu": "Giovedì",
        "ven": "Venerdì", "fri": "Venerdì",
        "sab": "Sabato", "sat": "Sabato",
        "dom": "Domenica", "sun": "Domenica"
    }

    for giorno in raw_plan:
        raw_day_name = giorno.get('giorno', 'Sconosciuto').strip().lower()
        day_name = "Sconosciuto"
        
        if len(raw_day_name) >= 3:
            prefix = raw_day_name[:3]
            day_name = DAY_MAPPING.get(prefix, raw_day_name.capitalize())
        else:
            day_name = raw_day_name.capitalize()

        if day_name not in app_plan:
            app_plan[day_name] = {}

        for pasto in giorno.get('pasti', []):
            meal_name = normalize_meal_name(pasto.get('tipo_pasto', ''))
            
            items = []
            for piatto in pasto.get('elenco_piatti', []):
                dish_name = str(piatto.get('nome_piatto') or 'Piatto')
                final_cad = piatto.get('cad_code', 0)
                if final_cad == 0:
                    final_cad = cad_lookup_map.get(dish_name.lower(), 0)

                formatted_ingredients = []
                for ing in piatto.get('ingredienti', []):
                    formatted_ingredients.append(Ingredient(
                        name=str(ing.get('nome') or ''),
                        qty=str(ing.get('quantita') or '')
                    ))

                items.append(Dish(
                    name=dish_name,
                    qty=str(piatto.get('quantita_totale') or ''),
                    cad_code=final_cad,
                    is_composed=(piatto.get('tipo') == 'composto'),
                    ingredients=formatted_ingredients
                ))
            
            if meal_name in app_plan[day_name]:
                app_plan[day_name][meal_name].extend(items)
            else:
                app_plan[day_name][meal_name] = items

    for day, meals in app_plan.items():
        ordered_meals = {}
        for standard_meal in MEAL_ORDER:
            if standard_meal in meals:
                ordered_meals[standard_meal] = meals[standard_meal]
        for k, v in meals.items():
            if k not in ordered_meals:
                ordered_meals[k] = v
        app_plan[day] = ordered_meals

    return DietResponse(
        plan=app_plan,
        substitutions=app_substitutions
    )
# [ADD THIS NEW ENDPOINT]
@app.post("/admin/cancel-maintenance")
async def cancel_maintenance_schedule(
    requester_id: str = Depends(verify_admin)
):
    try:
        db = firebase_admin.firestore.client()
        # Remove schedule fields and set is_scheduled to False
        db.collection('config').document('global').update({
            "is_scheduled": False,
            "scheduled_maintenance_start": firebase_admin.firestore.DELETE_FIELD,
            "maintenance_message": firebase_admin.firestore.DELETE_FIELD 
        })
        
        logger.info("maintenance_schedule_cancelled", admin=requester_id)
        return {"status": "cancelled", "message": "Schedule removed."}
        
    except Exception as e:
        logger.error("cancel_maintenance_error", error=str(e))
        raise HTTPException(status_code=500, detail=str(e))