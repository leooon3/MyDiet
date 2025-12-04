from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import JSONResponse
import shutil
import os
import json

# Importiamo i tuoi "cervelli" (assicurati che siano nella stessa cartella)
from diet_parser import DietParser
from receipt_scanner import ReceiptScanner

app = FastAPI()

# Percorsi dei file
DIET_PDF_PATH = "temp_dieta.pdf"
RECEIPT_PATH = "temp_scontrino" # L'estensione la decidiamo dopo
DIET_JSON_PATH = "dieta.json"

@app.get("/")
def read_root():
    return {"status": "Server Attivo! 🚀", "message": "Usa /upload-diet o /scan-receipt"}

@app.post("/upload-diet")
async def upload_diet(file: UploadFile = File(...)):
    """
    Riceve il PDF della dieta, lo analizza e salva il risultato.
    Restituisce il JSON della dieta al telefono.
    """
    try:
        print(f"📥 Ricevuto file dieta: {file.filename}")
        
        # 1. Salva il PDF ricevuto
        with open(DIET_PDF_PATH, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
            
        # 2. Lancia il Parser (V21)
        parser = DietParser()
        plan, subs = parser.parse_complex_diet(DIET_PDF_PATH)
        
        # 3. Prepara i dati finali
        final_data = {
            "type": "complex",
            "plan": plan,
            "substitutions": subs
        }
        
        # 4. Salva il JSON (serve allo scanner scontrini!)
        with open(DIET_JSON_PATH, "w", encoding="utf-8") as f:
            json.dump(final_data, f, indent=2, ensure_ascii=False)
            
        print("✅ Dieta elaborata e salvata.")
        return JSONResponse(content=final_data)

    except Exception as e:
        print(f"❌ Errore: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/scan-receipt")
async def scan_receipt(file: UploadFile = File(...)):
    """
    Riceve una foto o PDF dello scontrino.
    Usa dieta.json (già salvato) per filtrare i cibi.
    Restituisce la lista della spesa.
    """
    try:
        print(f"📥 Ricevuto scontrino: {file.filename}")
        
        # Verifica che esista la dieta per fare i confronti
        if not os.path.exists(DIET_JSON_PATH):
            raise HTTPException(status_code=400, detail="Carica prima la dieta!")

        # 1. Salva il file scontrino (mantenendo l'estensione)
        ext = os.path.splitext(file.filename)[1]
        temp_filename = f"{RECEIPT_PATH}{ext}"
        
        with open(temp_filename, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

        # 2. Lancia lo Scanner (V6)
        scanner = ReceiptScanner(DIET_JSON_PATH)
        found_items = scanner.scan_receipt(temp_filename)
        
        print(f"✅ Scontrino analizzato: trovati {len(found_items)} prodotti.")
        return JSONResponse(content=found_items)

    except Exception as e:
        print(f"❌ Errore: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    # Avvia il server su tutti gli indirizzi IP locali (0.0.0.0) porta 8000
    print("🌐 Avvio server su http://0.0.0.0:8000")
    uvicorn.run(app, host="0.0.0.0", port=8000)