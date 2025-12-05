from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import JSONResponse, FileResponse
import shutil
import os
import json

# Import moduli locali
from diet_parser import DietParser
from receipt_scanner import ReceiptScanner

app = FastAPI()

# Percorsi file
DIET_PDF_PATH = "temp_dieta.pdf"
RECEIPT_PATH = "temp_scontrino"
DIET_JSON_PATH = "dieta.json"

def convert_to_app_format(gemini_output):
    """
    Converte l'output di Gemini (Piano + Sostituzioni) nel formato per l'App.
    Output strutturato per MealCard.dart:
    - Piatto Composto: qty="N/A", cad_code=123
    - Ingredienti: qty="70g"
    """
    app_plan = {}
    app_substitutions = {}

    # 1. ELABORAZIONE PIANO SETTIMANALE
    raw_plan = gemini_output.get('piano_settimanale', [])
    
    for giorno in raw_plan:
        day_name = giorno.get('giorno', 'Sconosciuto').strip().capitalize()
        
        # Mappatura di sicurezza giorni
        day_lower = day_name.lower()
        if "lun" in day_lower: day_name = "Lunedì"
        elif "mar" in day_lower: day_name = "Martedì"
        elif "mer" in day_lower: day_name = "Mercoledì"
        elif "gio" in day_lower: day_name = "Giovedì"
        elif "ven" in day_lower: day_name = "Venerdì"
        elif "sab" in day_lower: day_name = "Sabato"
        elif "dom" in day_lower: day_name = "Domenica"

        app_plan[day_name] = {}

        for pasto in giorno.get('pasti', []):
            meal_name = pasto.get('tipo_pasto', 'Altro').strip()
            items = []
            
            for piatto in pasto.get('elenco_piatti', []):
                # Importante: Gemini restituisce 'cad_code' (int), noi lo passiamo
                cad_code = piatto.get('cad_code', 0)
                
                if piatto.get('tipo') == 'composto':
                    # Titolo del Piatto (Header)
                    items.append({
                        "name": piatto['nome_piatto'],
                        "qty": "N/A", # <--- FONDAMENTALE per MealCard
                        "cad_code": cad_code
                    })
                    # Ingredienti
                    for ing in piatto.get('ingredienti', []):
                        items.append({
                            "name": ing['nome'], # Rimuovo il pallino qui, lo mette la UI se vuole
                            "qty": ing['quantita'],
                            "is_ingredient": True
                        })
                else:
                    # Piatto Singolo
                    items.append({
                        "name": piatto['nome_piatto'],
                        "qty": piatto.get('quantita_totale', ''),
                        "cad_code": cad_code
                    })
            
            app_plan[day_name][meal_name] = items

    # 2. ELABORAZIONE TABELLA SOSTITUZIONI
    raw_subs = gemini_output.get('tabella_sostituzioni', [])
    for group in raw_subs:
        cad_key = str(group.get('cad_code', '0'))
        
        options = []
        for opt in group.get('opzioni', []):
            options.append({
                "name": opt['nome'],
                "qty": opt['quantita']
            })

        app_substitutions[cad_key] = {
            "name": group.get('titolo', "Alternativa"),
            "options": options
        }

    return {
        "plan": app_plan,
        "substitutions": app_substitutions
    }

@app.get("/")
def read_root():
    return {"status": "Server Attivo", "actions": ["/upload-diet", "/debug/json"]}

@app.get("/debug/json")
def get_debug_json():
    if os.path.exists(DIET_JSON_PATH):
        return FileResponse(DIET_JSON_PATH, media_type='application/json', filename="dieta_debug.json")
    return {"error": "Nessun file presente"}

@app.post("/upload-diet")
async def upload_diet(file: UploadFile = File(...)):
    try:
        print(f"📥 Ricevuto PDF: {file.filename}")
        with open(DIET_PDF_PATH, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
            
        parser = DietParser()
        print("🤖 Avvio analisi Gemini...")
        raw_data = parser.parse_complex_diet(DIET_PDF_PATH)
        
        final_data = convert_to_app_format(raw_data)
        
        with open(DIET_JSON_PATH, "w", encoding="utf-8") as f:
            json.dump(final_data, f, indent=2, ensure_ascii=False)
            
        print("✅ Analisi completata. JSON salvato.")
        return JSONResponse(content=final_data)

    except Exception as e:
        print(f"❌ Errore: {e}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/scan-receipt")
async def scan_receipt(file: UploadFile = File(...)):
    try:
        print(f"📥 Ricevuto scontrino: {file.filename}")
        if not os.path.exists(DIET_JSON_PATH):
            raise HTTPException(status_code=400, detail="Carica prima la dieta!")

        ext = os.path.splitext(file.filename)[1]
        temp_filename = f"{RECEIPT_PATH}{ext}"
        
        with open(temp_filename, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

        scanner = ReceiptScanner(DIET_JSON_PATH)
        found_items = scanner.scan_receipt(temp_filename)
        
        return JSONResponse(content=found_items)

    except Exception as e:
        print(f"❌ Errore: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)