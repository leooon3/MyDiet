import os
import uuid
import structlog
import aiofiles
import json
import asyncio
from datetime import datetime, timezone
from typing import Optional, List, Dict

import firebase_admin
from firebase_admin import credentials, auth, firestore, messaging

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
from app.broadcast import broadcast_message 

# --- CONFIGURATION ---
MAX_FILE_SIZE = 10 * 1024 * 1024
ALLOWED_EXTENSIONS = {".jpg", ".jpeg", ".png", ".pdf", ".webp"}

MEAL_ORDER = [
    "Colazione", "Seconda Colazione", "Spuntino", "Pranzo",
    "Merenda", "Cena", "Spuntino Serale", "Nell'Arco Della Giornata"
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
        elif os.path.exists("serviceAccountKey.json"):
            cred = credentials.Certificate("serviceAccountKey.json")
            firebase_admin.initialize_app(cred)
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
    allow_methods=["GET", "POST", "OPTIONS", "DELETE", "PUT"],
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

class UpdateUserRequest(BaseModel):
    email: Optional[str] = None
    first_name: Optional[str] = None
    last_name: Optional[str] = None

class AssignUserRequest(BaseModel):
    target_uid: str
    nutritionist_id: str

class UnassignUserRequest(BaseModel):
    target_uid: str

class MaintenanceRequest(BaseModel):
    enabled: bool
    message: Optional[str] = None

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
    token = authorization.split("Bearer ")[1].strip()
    if not token:
         raise HTTPException(status_code=401, detail="Empty token")
    try:
        decoded_token = await run_in_threadpool(auth.verify_id_token, token)
        return decoded_token['uid'] 
    except Exception:
        raise HTTPException(status_code=401, detail="Authentication failed")

async def verify_admin(uid: str = Depends(verify_token)):
    try:
        db = firebase_admin.firestore.client()
        user_doc = db.collection('users').document(uid).get()
        if not user_doc.exists or user_doc.to_dict().get('role') != 'admin':
            if user_doc.exists and user_doc.to_dict().get('role') == 'nutritionist':
                 return uid
            raise HTTPException(status_code=403, detail="Admin privileges required")
        return uid
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail="Authorization check failed")

# --- BACKGROUND WORKER (SECURE SCHEDULER) ---

async def maintenance_worker():
    logger.info("maintenance_worker_started")
    while True:
        try:
            db = firebase_admin.firestore.client()
            doc_ref = db.collection('config').document('global')
            doc = doc_ref.get()
            
            if doc.exists:
                data = doc.to_dict()
                is_scheduled = data.get('is_scheduled', False)
                start_str = data.get('scheduled_maintenance_start')
                
                if is_scheduled and start_str:
                    try:
                        clean_str = start_str.replace('Z', '+00:00')
                        scheduled_time = datetime.fromisoformat(clean_str)
                        if scheduled_time.tzinfo is None:
                            scheduled_time = scheduled_time.replace(tzinfo=timezone.utc)
                        
                        now = datetime.now(timezone.utc)
                        if now >= scheduled_time:
                            logger.info("maintenance_triggered", scheduled_for=start_str)
                            doc_ref.update({
                                "maintenance_mode": True,
                                "is_scheduled": False,
                                "scheduled_maintenance_start": firestore.DELETE_FIELD,
                                "updated_by": "system_scheduler"
                            })
                    except Exception as e:
                        logger.error("scheduler_error", error=str(e))
        except Exception as e:
            logger.error("worker_crash", error=str(e))
        
        await asyncio.sleep(60)

@app.on_event("startup")
async def start_background_tasks():
    asyncio.create_task(maintenance_worker())

# --- ENDPOINTS ---

@app.post("/upload-diet", response_model=DietResponse)
@limiter.limit("5/minute")
async def upload_diet(request: Request, file: UploadFile = File(...), fcm_token: Optional[str] = Form(None), user_id: str = Depends(verify_token)):
    if not file.filename.lower().endswith('.pdf'): raise HTTPException(status_code=400, detail="Only PDF allowed")
    temp_filename = f"{uuid.uuid4()}.pdf"
    try:
        await save_upload_file(file, temp_filename)
        raw_data = await run_in_threadpool(diet_parser.parse_complex_diet, temp_filename)
        if fcm_token: await run_in_threadpool(notification_service.send_diet_ready, fcm_token)
        return _convert_to_app_format(raw_data)
    finally:
        if os.path.exists(temp_filename): os.remove(temp_filename)

@app.post("/upload-diet/{target_uid}", response_model=DietResponse)
@limiter.limit("10/minute")
async def upload_diet_admin(request: Request, target_uid: str, file: UploadFile = File(...), fcm_token: Optional[str] = Form(None), requester_id: str = Depends(verify_token)):
    if not file.filename.lower().endswith('.pdf'): raise HTTPException(status_code=400, detail="Only PDF allowed")
    temp_filename = f"{uuid.uuid4()}.pdf"
    try:
        await save_upload_file(file, temp_filename)
        db = firebase_admin.firestore.client()
        custom_prompt = None
        user_doc = db.collection('users').document(target_uid).get()
        if user_doc.exists:
            parent_id = user_doc.to_dict().get('parent_id')
            if parent_id:
                parent_doc = db.collection('users').document(parent_id).get()
                if parent_doc.exists: custom_prompt = parent_doc.to_dict().get('custom_parser_prompt')
        
        raw_data = await run_in_threadpool(diet_parser.parse_complex_diet, temp_filename, custom_prompt)
        formatted_data = _convert_to_app_format(raw_data)
        dict_data = formatted_data.dict()

        # 1. Save to Admin History (Global)
        db.collection('diet_history').add({
            'userId': target_uid,
            'uploadedAt': firebase_admin.firestore.SERVER_TIMESTAMP,
            'fileName': file.filename,
            'parsedData': dict_data,
            'uploadedBy': requester_id
        })

        # 2. Save to Client History (User Subcollection)
        db.collection('users').document(target_uid).collection('diets').add({
            'uploadedAt': firebase_admin.firestore.SERVER_TIMESTAMP,
            'plan': dict_data.get('plan'),
            'substitutions': dict_data.get('substitutions'),
            'uploadedBy': 'nutritionist'
        })
        
        if fcm_token: await run_in_threadpool(notification_service.send_diet_ready, fcm_token)
        return formatted_data
    finally:
        if os.path.exists(temp_filename): os.remove(temp_filename)

@app.post("/scan-receipt")
async def scan_receipt(request: Request, file: UploadFile = File(...), allowed_foods: Json[List[str]] = Form(...), user_id: str = Depends(verify_token)):
    temp_filename = f"{uuid.uuid4()}{validate_extension(file.filename)}"
    try:
        await save_upload_file(file, temp_filename)
        current_scanner = ReceiptScanner(allowed_foods_list=allowed_foods)
        found_items = await run_in_threadpool(current_scanner.scan_receipt, temp_filename)
        return JSONResponse(content=found_items)
    finally:
        if os.path.exists(temp_filename): os.remove(temp_filename)

# --- ADMIN USER MANAGEMENT ---

@app.post("/admin/create-user")
async def admin_create_user(body: CreateUserRequest, requester_id: str = Depends(verify_admin)):
    try:
        db = firebase_admin.firestore.client()
        
        # 1. CLEANUP: Delete any existing orphaned docs with this email to prevent duplicates
        existing_docs = db.collection('users').where('email', '==', body.email).stream()
        for doc in existing_docs:
            doc.reference.delete()

        # 2. Check requester permissions (for inheritance logic)
        requester_doc = db.collection('users').document(requester_id).get()
        final_parent_id = body.parent_id
        if requester_doc.exists and requester_doc.to_dict().get('role') == 'nutritionist':
            final_parent_id = requester_id
        
        # 3. Create Auth User
        user = auth.create_user(
            email=body.email, 
            password=body.password, 
            display_name=f"{body.first_name} {body.last_name}", 
            email_verified=True
        )
        auth.set_custom_user_claims(user.uid, {'role': body.role})
        
        # 4. Create Firestore Document (Clean State)
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
        return {"uid": user.uid, "message": "User created"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    
@app.put("/admin/update-user/{target_uid}")
async def admin_update_user(target_uid: str, body: UpdateUserRequest, requester_id: str = Depends(verify_admin)):
    try:
        db = firebase_admin.firestore.client()
        
        # Update Auth
        update_args = {}
        if body.email: update_args['email'] = body.email
        if body.first_name or body.last_name:
             user = auth.get_user(target_uid)
             names = user.display_name.split(' ') if user.display_name else ["", ""]
             new_first = body.first_name if body.first_name else names[0]
             new_last = body.last_name if body.last_name else (names[1] if len(names)>1 else "")
             update_args['display_name'] = f"{new_first} {new_last}".strip()

        if update_args:
            auth.update_user(target_uid, **update_args)

        # Update Firestore
        fs_update = {}
        if body.email: fs_update['email'] = body.email
        if body.first_name: fs_update['first_name'] = body.first_name
        if body.last_name: fs_update['last_name'] = body.last_name
        
        if fs_update:
            db.collection('users').document(target_uid).update(fs_update)
            
        return {"message": "User updated"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/admin/assign-user")
async def admin_assign_user(body: AssignUserRequest, requester_id: str = Depends(verify_admin)):
    try:
        db = firebase_admin.firestore.client()
        # Change role to user, assign parent
        db.collection('users').document(body.target_uid).update({
            'role': 'user',
            'parent_id': body.nutritionist_id,
            'updated_at': firebase_admin.firestore.SERVER_TIMESTAMP
        })
        auth.set_custom_user_claims(body.target_uid, {'role': 'user'})
        return {"message": "User assigned successfully"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/admin/unassign-user")
async def admin_unassign_user(body: UnassignUserRequest, requester_id: str = Depends(verify_admin)):
    try:
        db = firebase_admin.firestore.client()
        # Revert role to independent, remove parent
        db.collection('users').document(body.target_uid).update({
            'role': 'independent',
            'parent_id': firestore.DELETE_FIELD,
            'updated_at': firebase_admin.firestore.SERVER_TIMESTAMP
        })
        auth.set_custom_user_claims(body.target_uid, {'role': 'independent'})
        return {"message": "User unassigned successfully"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/admin/delete-user/{target_uid}")
async def admin_delete_user(target_uid: str, requester_id: str = Depends(verify_admin)):
    try:
        try: auth.delete_user(target_uid)
        except: pass
        firebase_admin.firestore.client().collection('users').document(target_uid).delete()
        return {"message": "Deleted"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/admin/sync-users")
async def admin_sync_users(requester_id: str = Depends(verify_admin)):
    try:
        db = firebase_admin.firestore.client()
        
        # Iterate through all Auth users
        for user in auth.list_users().users:
            
            # 1. GHOST BUSTER: Find and delete any docs with this email that have the WRONG ID
            email_docs = db.collection('users').where('email', '==', user.email).stream()
            for doc in email_docs:
                if doc.id != user.uid:
                    doc.reference.delete()

            # 2. Create missing document if it doesn't exist
            if not db.collection('users').document(user.uid).get().exists:
                db.collection('users').document(user.uid).set({
                    'uid': user.uid, 
                    'email': user.email, 
                    'role': 'independent',
                    'first_name': 'App', 
                    'last_name': '', 
                    'created_at': firebase_admin.firestore.SERVER_TIMESTAMP
                })
                
        return {"message": "Synced & Cleaned"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    
@app.post("/admin/upload-parser/{target_uid}")
async def upload_parser_config(target_uid: str, file: UploadFile = File(...), requester_id: str = Depends(verify_admin)):
    try:
        content = (await file.read()).decode("utf-8")
        db = firebase_admin.firestore.client()
        
        db.collection('users').document(target_uid).update({
            'custom_parser_prompt': content, 
            'has_custom_parser': True,
            'parser_updated_at': firebase_admin.firestore.SERVER_TIMESTAMP
        })
        
        # History
        db.collection('users').document(target_uid).collection('parser_history').add({
            'content': content,
            'uploaded_at': firebase_admin.firestore.SERVER_TIMESTAMP,
            'uploaded_by': requester_id
        })
        
        return {"message": "Updated"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# --- MAINTENANCE & HELPERS ---

@app.get("/admin/config/maintenance")
async def get_maintenance_status(requester_id: str = Depends(verify_admin)):
    doc = firebase_admin.firestore.client().collection('config').document('global').get()
    return {"enabled": doc.to_dict().get('maintenance_mode', False)} if doc.exists else {"enabled": False}

@app.post("/admin/config/maintenance")
async def set_maintenance_status(body: MaintenanceRequest, requester_id: str = Depends(verify_admin)):
    data = {'maintenance_mode': body.enabled, 'updated_by': requester_id}
    if body.message:
        data['maintenance_message'] = body.message
    firebase_admin.firestore.client().collection('config').document('global').set(data, merge=True)
    return {"message": "Updated"}

@app.post("/admin/schedule-maintenance")
async def schedule_maintenance(req: ScheduleMaintenanceRequest, admin_uid: str = Depends(verify_admin)):
    firebase_admin.firestore.client().collection('config').document('global').set({
        "scheduled_maintenance_start": req.scheduled_time,
        "maintenance_message": req.message,
        "is_scheduled": True
    }, merge=True)
    
    if req.notify:
        try:
            broadcast_message(title="System Update", body=req.message, data={"type": "maintenance_alert"})
        except: pass
    return {"status": "scheduled"}

@app.post("/admin/cancel-maintenance")
async def cancel_maintenance_schedule(requester_id: str = Depends(verify_admin)):
    firebase_admin.firestore.client().collection('config').document('global').update({
        "is_scheduled": False,
        "scheduled_maintenance_start": firestore.DELETE_FIELD,
        "maintenance_message": firestore.DELETE_FIELD
    })
    return {"status": "cancelled"}

def _convert_to_app_format(gemini_output) -> DietResponse:
    if not gemini_output: return DietResponse(plan={}, substitutions={})
    app_plan, app_substitutions = {}, {}
    cad_map = {}
    
    for g in gemini_output.get('tabella_sostituzioni', []):
        if g.get('cad_code', 0) > 0:
            cad_map[g.get('titolo', '').strip().lower()] = g['cad_code']
            app_substitutions[str(g['cad_code'])] = SubstitutionGroup(
                name=g.get('titolo', ''),
                options=[SubstitutionOption(name=o.get('nome',''), qty=o.get('quantita','')) for o in g.get('opzioni',[])]
            )

    day_map = {"lun": "Lunedì", "mar": "Martedì", "mer": "Mercoledì", "gio": "Giovedì", "ven": "Venerdì", "sab": "Sabato", "dom": "Domenica"}
    
    for day in gemini_output.get('piano_settimanale', []):
        raw_name = day.get('giorno', '').lower().strip()
        day_name = day_map.get(raw_name[:3], raw_name.capitalize())
        app_plan[day_name] = {}
        
        for meal in day.get('pasti', []):
            m_name = normalize_meal_name(meal.get('tipo_pasto', ''))
            dishes = []
            for d in meal.get('elenco_piatti', []):
                d_name = d.get('nome_piatto') or 'Piatto'
                dishes.append(Dish(
                    name=d_name,
                    qty=str(d.get('quantita_totale') or ''),
                    cad_code=d.get('cad_code', 0) or cad_map.get(d_name.lower(), 0),
                    is_composed=(d.get('tipo') == 'composto'),
                    ingredients=[Ingredient(name=str(i.get('nome','')), qty=str(i.get('quantita',''))) for i in d.get('ingredienti', [])]
                ))
            if m_name in app_plan[day_name]: app_plan[day_name][m_name].extend(dishes)
            else: app_plan[day_name][m_name] = dishes

    # Order meals
    for d, meals in app_plan.items():
        app_plan[d] = {k: meals[k] for k in MEAL_ORDER if k in meals}
        for k in meals: 
            if k not in app_plan[d]: app_plan[d][k] = meals[k]

    return DietResponse(plan=app_plan, substitutions=app_substitutions)