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
from app.services.normalization import normalize_meal_name, normalize_quantity
from app.core.config import settings
from app.models.schemas import DietResponse, Dish, Ingredient, SubstitutionGroup, SubstitutionOption
from app.broadcast import broadcast_message 

# --- CONFIGURATION ---
MAX_FILE_SIZE = 10 * 1024 * 1024
ALLOWED_EXTENSIONS = {".jpg", ".jpeg", ".png", ".pdf", ".webp"}


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

class LogAccessRequest(BaseModel):
    target_uid: str
    reason: str
    
# --- UTILS & SECURITY ---

#async def save_upload_file(file: UploadFile, filename: str) -> None:
#    size = 0
#    try:
#        async with aiofiles.open(filename, 'wb') as out_file:
#            while content := await file.read(1024 * 1024):
#               size += len(content)
#                if size > MAX_FILE_SIZE:
#                    raise HTTPException(status_code=413, detail="File too large")
#                await out_file.write(content)
#    except Exception as e:
#        if os.path.exists(filename):
#            os.remove(filename)
#        raise e

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
        return decoded_token 
    except Exception:
        raise HTTPException(status_code=401, detail="Authentication failed")

async def verify_admin(token: dict = Depends(verify_token)):
    role = token.get('role')
    uid = token.get('uid')
    if role == 'admin': return {'uid': uid, 'role': 'admin'}
    try:
        db = firebase_admin.firestore.client()
        user_doc = db.collection('users').document(uid).get()
        if user_doc.exists and user_doc.to_dict().get('role') == 'admin':
             auth.set_custom_user_claims(uid, {'role': 'admin'})
             return {'uid': uid, 'role': 'admin'}
    except: pass
    raise HTTPException(status_code=403, detail="Admin privileges required")

async def verify_professional(token: dict = Depends(verify_token)):
    role = token.get('role')
    uid = token.get('uid')
    if role in ['admin', 'nutritionist']: return {'uid': uid, 'role': role}
    raise HTTPException(status_code=403, detail="Professional privileges required")

async def get_current_uid(token: dict = Depends(verify_token)):
    return token['uid']

# --- BACKGROUND WORKER ---

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
async def upload_diet(request: Request, file: UploadFile = File(...), fcm_token: Optional[str] = Form(None), user_id: str = Depends(get_current_uid)):
    if not file.filename.lower().endswith('.pdf'): raise HTTPException(status_code=400, detail="Only PDF allowed")
    
    # LEGGIAMO IN MEMORIA
    content = await file.read()
    
    # Passiamo i bytes direttamente
    raw_data = await run_in_threadpool(diet_parser.parse_complex_diet, content)
    
    if fcm_token: await run_in_threadpool(notification_service.send_diet_ready, fcm_token)
    return _convert_to_app_format(raw_data)

@app.post("/upload-diet/{target_uid}", response_model=DietResponse)
@limiter.limit("10/minute")
async def upload_diet_admin(request: Request, target_uid: str, file: UploadFile = File(...), fcm_token: Optional[str] = Form(None), requester: dict = Depends(verify_professional)):
        requester_id = requester['uid']
        
        if not file.filename.lower().endswith('.pdf'): raise HTTPException(status_code=400, detail="Only PDF allowed")
        
        # LEGGIAMO IN MEMORIA
        content = await file.read()

        db = firebase_admin.firestore.client()
        custom_prompt = None
        user_doc = db.collection('users').document(target_uid).get()
        if user_doc.exists:
            parent_id = user_doc.to_dict().get('parent_id')
            if parent_id:
                parent_doc = db.collection('users').document(parent_id).get()
                if parent_doc.exists: custom_prompt = parent_doc.to_dict().get('custom_parser_prompt')

        # Passiamo bytes
        raw_data = await run_in_threadpool(diet_parser.parse_complex_diet, content, custom_prompt)
        formatted_data = _convert_to_app_format(raw_data)
        dict_data = formatted_data.dict()

        # Salvataggio DB (rimane uguale)
        db.collection('diet_history').add({
            'userId': target_uid,
            'uploadedAt': firebase_admin.firestore.SERVER_TIMESTAMP,
            'fileName': file.filename,
            'parsedData': dict_data,
            'uploadedBy': requester_id
        })

        db.collection('users').document(target_uid).collection('diets').add({
                'uploadedAt': firebase_admin.firestore.SERVER_TIMESTAMP,
                'plan': dict_data.get('plan'),
                'substitutions': dict_data.get('substitutions'),
                'uploadedBy': 'nutritionist'
        })
            
        if fcm_token: await run_in_threadpool(notification_service.send_diet_ready, fcm_token)
        return formatted_data

@app.post("/scan-receipt")
async def scan_receipt(request: Request, file: UploadFile = File(...), allowed_foods: Json[List[str]] = Form(...), user_id: str = Depends(get_current_uid)):
    # Legge il contenuto del file direttamente in memoria
    file_content = await file.read()
    
    current_scanner = ReceiptScanner(allowed_foods_list=allowed_foods)
    
    # Passa i bytes (file_content) invece del percorso file
    # Modifica questa riga:
    found_items = await run_in_threadpool(current_scanner.scan_receipt, file_content, file.content_type)
    
    return JSONResponse(content=found_items)

# --- USER MANAGEMENT ---

@app.post("/admin/create-user")
async def admin_create_user(body: CreateUserRequest, requester: dict = Depends(verify_admin)):
    try:
        db = firebase_admin.firestore.client()
        existing_docs = db.collection('users').where('email', '==', body.email).stream()
        for doc in existing_docs: doc.reference.delete()

        user = auth.create_user(
            email=body.email, password=body.password, display_name=f"{body.first_name} {body.last_name}", email_verified=True
        )
        auth.set_custom_user_claims(user.uid, {'role': body.role})
        
        db.collection('users').document(user.uid).set({
            'uid': user.uid, 'email': body.email, 'role': body.role,
            'first_name': body.first_name, 'last_name': body.last_name,
            'parent_id': body.parent_id, 'is_active': True,
            'created_at': firebase_admin.firestore.SERVER_TIMESTAMP,
            'created_by': requester['uid'], 'requires_password_change': True
        })
        return {"uid": user.uid, "message": "User created"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    
@app.put("/admin/update-user/{target_uid}")
async def admin_update_user(target_uid: str, body: UpdateUserRequest, requester: dict = Depends(verify_admin)):
    try:
        db = firebase_admin.firestore.client()
        update_args = {}
        if body.email: update_args['email'] = body.email
        if body.first_name or body.last_name:
             user = auth.get_user(target_uid)
             names = user.display_name.split(' ') if user.display_name else ["", ""]
             new_first = body.first_name if body.first_name else names[0]
             new_last = body.last_name if body.last_name else (names[1] if len(names)>1 else "")
             update_args['display_name'] = f"{new_first} {new_last}".strip()

        if update_args: auth.update_user(target_uid, **update_args)

        fs_update = {}
        if body.email: fs_update['email'] = body.email
        if body.first_name: fs_update['first_name'] = body.first_name
        if body.last_name: fs_update['last_name'] = body.last_name
        
        if fs_update: db.collection('users').document(target_uid).update(fs_update)
        return {"message": "User updated"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/admin/assign-user")
async def admin_assign_user(body: AssignUserRequest, requester: dict = Depends(verify_admin)):
    try:
        db = firebase_admin.firestore.client()
        db.collection('access_logs').add({
            'requester_id': requester['uid'], 'target_uid': body.target_uid,
            'action': 'ASSIGN_USER', 'reason': f"Assigned to {body.nutritionist_id}",
            'timestamp': firebase_admin.firestore.SERVER_TIMESTAMP
        })
        db.collection('users').document(body.target_uid).update({
            'role': 'user', 'parent_id': body.nutritionist_id,
            'updated_at': firebase_admin.firestore.SERVER_TIMESTAMP
        })
        auth.set_custom_user_claims(body.target_uid, {'role': 'user'})
        return {"message": "User assigned"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/admin/unassign-user")
async def admin_unassign_user(body: UnassignUserRequest, requester: dict = Depends(verify_admin)):
    try:
        db = firebase_admin.firestore.client()
        db.collection('access_logs').add({
            'requester_id': requester['uid'], 'target_uid': body.target_uid,
            'action': 'UNASSIGN_USER', 'reason': "Restored to Independent",
            'timestamp': firebase_admin.firestore.SERVER_TIMESTAMP
        })
        db.collection('users').document(body.target_uid).update({
            'role': 'independent', 'parent_id': firestore.DELETE_FIELD,
            'updated_at': firebase_admin.firestore.SERVER_TIMESTAMP
        })
        auth.set_custom_user_claims(body.target_uid, {'role': 'independent'})
        return {"message": "User unassigned"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/admin/delete-user/{target_uid}")
async def admin_delete_user(target_uid: str, requester: dict = Depends(verify_professional)):
    requester_id = requester['uid']
    requester_role = requester['role']
    try:
        db = firebase_admin.firestore.client()
        if requester_role == 'nutritionist':
             user_doc = db.collection('users').document(target_uid).get()
             if not user_doc.exists: return {"message": "User already deleted"}
             data = user_doc.to_dict()
             if data.get('parent_id') != requester_id and data.get('created_by') != requester_id:
                  raise HTTPException(status_code=403, detail="Cannot delete this user")
        db.collection('access_logs').add({
            'requester_id': requester_id, 'target_uid': target_uid,
            'action': 'DELETE_USER', 'reason': 'Permanent Deletion',
            'timestamp': firebase_admin.firestore.SERVER_TIMESTAMP
        })
        try: auth.delete_user(target_uid)
        except: pass
        db.collection('users').document(target_uid).delete()
        return {"message": "Deleted"}
    except HTTPException as he: raise he
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/admin/delete-diet/{diet_id}")
async def admin_delete_diet(diet_id: str, requester: dict = Depends(verify_professional)):
    requester_id = requester['uid']
    requester_role = requester['role']
    try:
        db = firebase_admin.firestore.client()
        diet_doc = db.collection('diet_history').document(diet_id).get()
        if not diet_doc.exists: return {"message": "Already deleted"}
        
        diet_data = diet_doc.to_dict()
        user_id = diet_data.get('userId')
        
        # Check ownership per Nutrizionista
        if requester_role == 'nutritionist':
            if diet_data.get('uploadedBy') != requester_id:
                 # Se non l'ho caricata io, controllo se l'utente è mio
                 if user_id:
                     user_doc = db.collection('users').document(user_id).get()
                     if user_doc.exists and user_doc.to_dict().get('parent_id') != requester_id:
                         raise HTTPException(status_code=403, detail="Not authorized")

        db.collection('access_logs').add({
            'requester_id': requester_id, 'target_uid': user_id,
            'action': 'DELETE_DIET_HISTORY', 
            'reason': f"Deleted file: {diet_data.get('fileName')}",
            'timestamp': firebase_admin.firestore.SERVER_TIMESTAMP
        })
        
        db.collection('diet_history').document(diet_id).delete()
        return {"message": "Diet deleted"}
    except HTTPException as he: raise he
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/admin/sync-users")
async def admin_sync_users(requester: dict = Depends(verify_admin)):
    try:
        db = firebase_admin.firestore.client()
        count = 0
        for user in auth.list_users().users:
            email_docs = db.collection('users').where('email', '==', user.email).stream()
            for doc in email_docs:
                if doc.id != user.uid: doc.reference.delete()

            current_role = 'independent'
            user_doc = db.collection('users').document(user.uid).get()
            if user_doc.exists: current_role = user_doc.to_dict().get('role', 'independent')
            else:
                db.collection('users').document(user.uid).set({
                    'uid': user.uid, 'email': user.email, 'role': 'independent',
                    'first_name': 'App', 'last_name': '', 'created_at': firebase_admin.firestore.SERVER_TIMESTAMP
                })
            auth.set_custom_user_claims(user.uid, {'role': current_role})
            count += 1
        return {"message": f"Synced {count} users"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    
@app.post("/admin/upload-parser/{target_uid}")
async def upload_parser_config(target_uid: str, file: UploadFile = File(...), requester: dict = Depends(verify_admin)):
    requester_id = requester['uid']
    try:
        content = (await file.read()).decode("utf-8")
        db = firebase_admin.firestore.client()
        db.collection('users').document(target_uid).update({
            'custom_parser_prompt': content, 'has_custom_parser': True,
            'parser_updated_at': firebase_admin.firestore.SERVER_TIMESTAMP
        })
        db.collection('users').document(target_uid).collection('parser_history').add({
            'content': content, 'uploaded_at': firebase_admin.firestore.SERVER_TIMESTAMP, 'uploaded_by': requester_id
        })
        return {"message": "Updated"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# --- SECURE GATEWAY ---

@app.post("/admin/log-access")
async def log_access(body: LogAccessRequest, requester: dict = Depends(verify_professional)):
    try:
        firebase_admin.firestore.client().collection('access_logs').add({
            'requester_id': requester['uid'], 'target_uid': body.target_uid,
            'action': 'UNLOCK_PII', 'reason': body.reason or 'User Unlock',
            'timestamp': firebase_admin.firestore.SERVER_TIMESTAMP,
            'user_agent': 'kybo_admin_panel'
        })
        return {"status": "logged"}
    except Exception as e:
        raise HTTPException(status_code=500, detail="Failed to log access")

@app.get("/admin/user-history/{target_uid}")
async def get_secure_user_history(target_uid: str, requester: dict = Depends(verify_professional)):
    requester_id = requester['uid']
    requester_role = requester['role']
    
    try:
        db = firebase_admin.firestore.client()
        if requester_role == 'nutritionist':
            user_doc = db.collection('users').document(target_uid).get()
            if not user_doc.exists: raise HTTPException(status_code=404, detail="User not found")
            data = user_doc.to_dict()
            if data.get('parent_id') != requester_id and data.get('created_by') != requester_id:
                raise HTTPException(status_code=403, detail="Access denied")

        db.collection('access_logs').add({
            'requester_id': requester_id, 'target_uid': target_uid,
            'action': 'READ_HISTORY_FULL', 'reason': 'Diet Review',
            'timestamp': firebase_admin.firestore.SERVER_TIMESTAMP
        })
        
        history_ref = db.collection('diet_history')\
                        .where('userId', '==', target_uid)\
                        .order_by('uploadedAt', direction=firestore.Query.DESCENDING)\
                        .limit(50)
        
        results = []
        for doc in history_ref.stream():
            data = doc.to_dict()
            if 'uploadedAt' in data and data['uploadedAt']:
                data['uploadedAt'] = data['uploadedAt'].isoformat()
            data['id'] = doc.id
            results.append(data)
        return results
    except HTTPException as he: raise he
    except Exception as e:
        logger.error("secure_gateway_error", error=str(e))
        raise HTTPException(status_code=500, detail="Error fetching history")

@app.get("/admin/users-secure")
async def list_users_secure(requester: dict = Depends(verify_professional)):
    requester_id = requester['uid']
    requester_role = requester['role']
    try:
        db = firebase_admin.firestore.client()
        db.collection('access_logs').add({
            'requester_id': requester_id, 'action': 'READ_USER_DIRECTORY',
            'reason': 'User List View', 'timestamp': firebase_admin.firestore.SERVER_TIMESTAMP
        })
        users_ref = db.collection('users')
        if requester_role == 'nutritionist':
            docs = users_ref.where('parent_id', '==', requester_id).stream()
        else:
            docs = users_ref.stream()
        return [d.to_dict() for d in docs]
    except Exception as e:
        raise HTTPException(status_code=500, detail="Error fetching users")

@app.get("/admin/user-details-secure/{target_uid}")
async def get_user_details_secure(target_uid: str, requester: dict = Depends(verify_professional)):
    requester_id = requester['uid']
    requester_role = requester['role']
    try:
        db = firebase_admin.firestore.client()
        if requester_role == 'nutritionist':
             user_doc = db.collection('users').document(target_uid).get()
             if not user_doc.exists: raise HTTPException(status_code=404, detail="User not found")
             if user_doc.to_dict().get('parent_id') != requester_id: raise HTTPException(status_code=403, detail="Access denied")

        db.collection('access_logs').add({
            'requester_id': requester_id, 'target_uid': target_uid,
            'action': 'READ_USER_PROFILE', 'reason': 'Detail View',
            'timestamp': firebase_admin.firestore.SERVER_TIMESTAMP
        })
        
        doc = db.collection('users').document(target_uid).get()
        if not doc.exists: raise HTTPException(status_code=404, detail="User not found")
        return doc.to_dict()
    except HTTPException as he: raise he
    except Exception as e:
        raise HTTPException(status_code=500, detail="Error fetching profile")

# --- MAINTENANCE ---
@app.get("/admin/config/maintenance")
async def get_maintenance_status(requester: dict = Depends(verify_admin)):
    doc = firebase_admin.firestore.client().collection('config').document('global').get()
    return {"enabled": doc.to_dict().get('maintenance_mode', False)} if doc.exists else {"enabled": False}

@app.post("/admin/config/maintenance")
async def set_maintenance_status(body: MaintenanceRequest, requester: dict = Depends(verify_admin)):
    data = {'maintenance_mode': body.enabled, 'updated_by': requester['uid']}
    if body.message: data['maintenance_message'] = body.message
    firebase_admin.firestore.client().collection('config').document('global').set(data, merge=True)
    return {"message": "Updated"}

@app.post("/admin/schedule-maintenance")
async def schedule_maintenance(req: ScheduleMaintenanceRequest, requester: dict = Depends(verify_admin)):
    firebase_admin.firestore.client().collection('config').document('global').set({
        "scheduled_maintenance_start": req.scheduled_time, "maintenance_message": req.message, "is_scheduled": True
    }, merge=True)
    if req.notify:
        try: broadcast_message(title="System Update", body=req.message, data={"type": "maintenance_alert"})
        except: pass
    return {"status": "scheduled"}

@app.post("/admin/cancel-maintenance")
async def cancel_maintenance_schedule(requester: dict = Depends(verify_admin)):
    firebase_admin.firestore.client().collection('config').document('global').update({
        "is_scheduled": False, "scheduled_maintenance_start": firestore.DELETE_FIELD, "maintenance_message": firestore.DELETE_FIELD
    })
    return {"status": "cancelled"}

 
def _convert_to_app_format(gemini_output) -> DietResponse:
    if not gemini_output: return DietResponse(plan={}, substitutions={})
    app_plan, app_substitutions = {}, {}
    cad_map = {}
    
    # 1. Mappatura Sostituzioni (Invariato)
    for g in gemini_output.get('tabella_sostituzioni', []):
        if g.get('cad_code', 0) > 0:
            cad_map[g.get('titolo', '').strip().lower()] = g['cad_code']
            clean_options = []
            for o in g.get('opzioni',[]):
                raw_qty = o.get('quantita','')
                clean_qty = normalize_quantity(raw_qty) 
                clean_options.append(SubstitutionOption(name=o.get('nome',''), qty=clean_qty))

            app_substitutions[str(g['cad_code'])] = SubstitutionGroup(
                name=g.get('titolo', ''),
                options=clean_options
            )

    day_map = {"lun": "Lunedì", "mar": "Martedì", "mer": "Mercoledì", "gio": "Giovedì", "ven": "Venerdì", "sab": "Sabato", "dom": "Domenica"}
    
    # 2. Costruzione Piano (Dinamico)
    # L'ordine è garantito dalla lista 'pasti' restituita da Gemini (che legge dall'alto in basso)
    for day in gemini_output.get('piano_settimanale', []):
        raw_name = day.get('giorno', '').lower().strip()
        day_name = day_map.get(raw_name[:3], raw_name.capitalize())
        
        # Usiamo un dict standard (in Python 3.7+ preserva l'ordine di inserimento)
        app_plan[day_name] = {}
        
        for meal in day.get('pasti', []):
            # Normalizzazione minima solo per rimuovere spazi extra, ma manteniamo il nome originale
            # Opzionale: normalize_meal_name(meal.get('tipo_pasto', '')) se vuoi ancora uniformare
            # Per flessibilità totale, usa il nome grezzo:
            m_name = meal.get('tipo_pasto', '').strip().capitalize() 
            
            dishes = []
            for d in meal.get('elenco_piatti', []):
                d_name = d.get('nome_piatto') or 'Piatto'
                raw_dish_qty = str(d.get('quantita_totale') or '')
                clean_dish_qty = normalize_quantity(raw_dish_qty)

                clean_ingredients = []
                for i in d.get('ingredienti', []):
                    raw_ing_qty = str(i.get('quantita',''))
                    clean_ing_qty = normalize_quantity(raw_ing_qty)
                    clean_ingredients.append(Ingredient(name=str(i.get('nome','')), qty=clean_ing_qty))

                new_dish = Dish(
                    instance_id=str(uuid.uuid4()),
                    name=d_name,
                    qty=clean_dish_qty,
                    cad_code=d.get('cad_code', 0) or cad_map.get(d_name.lower(), 0),
                    is_composed=(d.get('tipo') == 'composto'),
                    ingredients=clean_ingredients
                )
                dishes.append(new_dish)

            # Preserva l'ordine di arrivo
            if m_name in app_plan[day_name]: 
                app_plan[day_name][m_name].extend(dishes)
            else: 
                app_plan[day_name][m_name] = dishes

    # [RIMOSSO] Blocco di riordino forzato basato su MEAL_ORDER
    # Non serve fare altro, app_plan[day] ha le chiavi nell'ordine di inserimento.

    return DietResponse(plan=app_plan, substitutions=app_substitutions)