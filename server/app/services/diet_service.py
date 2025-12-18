import google.generativeai as genai
import typing_extensions as typing
import json
import pdfplumber
import os
from app.core.config import settings

# --- SCHEMI DATI (Unchanged) ---
class Ingrediente(typing.TypedDict):
    nome: str
    quantita: str

class Piatto(typing.TypedDict):
    nome_piatto: str
    tipo: str
    cad_code: int
    quantita_totale: str
    ingredienti: list[Ingrediente]

class Pasto(typing.TypedDict):
    tipo_pasto: str
    elenco_piatti: list[Piatto]

class GiornoDieta(typing.TypedDict):
    giorno: str 
    pasti: list[Pasto]

class OpzioneSostituzione(typing.TypedDict):
    nome: str
    quantita: str

class GruppoSostituzione(typing.TypedDict):
    cad_code: int
    titolo: str
    opzioni: list[OpzioneSostituzione]

class OutputDietaCompleto(typing.TypedDict):
    piano_settimanale: list[GiornoDieta]
    tabella_sostituzioni: list[GruppoSostituzione]

class DietParser:
    def __init__(self):
        api_key = settings.GOOGLE_API_KEY
        if not api_key:
            print("❌ ERRORE CRITICO: GOOGLE_API_KEY non trovata!")
        else:
            clean_key = api_key.strip().replace('"', '').replace("'", "")
            genai.configure(api_key=clean_key)

        self.system_instruction = """
        Sei un nutrizionista esperto. Analizza il PDF (tabella) ed estrai i dati in JSON.
        ... (Keep your prompt here) ...
        """

    def _extract_text_from_pdf(self, pdf_path: str) -> str:
        text = ""
        try:
            # [FIX] Safety check before opening
            file_size = os.path.getsize(pdf_path)
            if file_size > 10 * 1024 * 1024: # 10MB limit
                raise ValueError("PDF troppo grande per l'elaborazione.")

            with pdfplumber.open(pdf_path) as pdf:
                # [FIX] Page limit check to prevent DoS
                if len(pdf.pages) > 50:
                    raise ValueError("Il PDF ha troppe pagine (Max 50).")
                
                for page in pdf.pages:
                    extracted = page.extract_text(layout=True) 
                    if extracted:
                        text += extracted + "\n"
        except Exception as e:
            print(f"❌ Errore lettura PDF: {e}")
            raise e
        return text

    def parse_complex_diet(self, file_path: str):
        diet_text = self._extract_text_from_pdf(file_path)
        if not diet_text:
            raise ValueError("PDF vuoto o illeggibile.")

        model_name = settings.GEMINI_MODEL
        
        try:
            print(f"🤖 Analisi Gemini ({model_name})...")
            model = genai.GenerativeModel(
                model_name=model_name,
                system_instruction=self.system_instruction,
                generation_config={
                    "response_mime_type": "application/json",
                    "response_schema": OutputDietaCompleto
                }
            )
            
            prompt = f"Analizza il documento e recupera codici CAD e tabelle.\n\nTESTO:\n{diet_text}"

            response = model.generate_content(prompt)
            return json.loads(response.text)

        except Exception as e:
            print(f"⚠️ Errore con Gemini: {e}")
            raise e