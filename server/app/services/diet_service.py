import json
import re
import io
import pdfplumber
import os
from google import genai
from google.genai import types
from app.core.config import settings
from app.models.schemas import (
    DietResponse, 
    Dish, 
    Ingredient, 
    SubstitutionGroup, 
    SubstitutionOption
)
import typing_extensions as typing

# --- DATA SCHEMAS (Your Original TypedDicts) ---
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
            print("❌ CRITICAL ERROR: GOOGLE_API_KEY not found in settings!")
            self.client = None
        else:
            clean_key = api_key.strip().replace('"', '').replace("'", "")
            self.client = genai.Client(api_key=clean_key)
        
        # [System instruction originale mantenuta...]
        self.system_instruction = """
You are an expert AI Nutritionist and Data Analyst capable of understanding any language.
YOUR TASK: Extract the weekly diet plan from the provided document.
CRITICAL RULES FOR MULTI-LANGUAGE SUPPORT:
1. Detect Language: Read the document in its original language.
2. Translate Structure (Required): 
   - Translate Day of the Week into Italian.
   - Translate Meal Category into Italian.
3. Preserve Content: Keep Dish Names, Ingredients, and Quantities in ORIGINAL LANGUAGE.
SIMPLIFIED SCHEMA RULES:
1. Weekly Plan Only: Extract every meal.
2. No Substitutions: Return empty list [].
3. No CAD Codes: Set to 0.
"""

    # --- 1.4 SANITIZZAZIONE GDPR (Re-integrata) ---
    def _sanitize_text(self, text: str) -> str:
        if not text: return ""
        # Rimuove Email
        text = re.sub(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b', '[EMAIL_OSCURATA]', text)
        # Rimuove CF
        text = re.sub(r'\b[A-Z]{6}\d{2}[A-Z]\d{2}[A-Z]\d{3}[A-Z]\b', '[CF_OSCURATO]', text, flags=re.IGNORECASE)
        # Rimuove Telefoni
        text = re.sub(r'\b(\+39|0039)?\s?(3\d{2}|0\d{1,3})[\s\.-]?\d{6,10}\b', '[TEL_OSCURATO]', text)
        # Rimuove Intestazioni Nomi
        text = re.sub(r'(?i)(Paziente|Sig\.|Sig\.ra|Dott\.|Dr\.|Nome|Cognome|Spett\.le)\s*[:\.]?\s*[^\n]+', '[ANAGRAFICA_OSCURATA]', text)
        return text

    # --- 3.1 STREAMING I/O FIX ---
    # Ora accetta 'file_obj' (stream) invece di 'pdf_path' (stringa)
    def _extract_text_from_pdf(self, file_obj) -> str:
        text_buffer = io.StringIO()
        try:
            # Apriamo direttamente l'oggetto in memoria senza toccare il disco
            with pdfplumber.open(file_obj) as pdf:
                if len(pdf.pages) > 50:
                    raise ValueError("Il PDF ha troppe pagine (Max 50).")
                
                for page in pdf.pages:
                    extracted = page.extract_text(layout=True) 
                    if extracted:
                        text_buffer.write(extracted)
                        text_buffer.write("\n")
            
            return text_buffer.getvalue()
        except Exception as e:
            print(f"❌ Errore lettura PDF: {e}")
            raise e
        finally:
            text_buffer.close()

    def _extract_json_from_text(self, text: str):
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            pass
        match = re.search(r'\{.*\}', text, re.DOTALL)
        if match:
            clean_text = match.group(0)
            try:
                return json.loads(clean_text)
            except json.JSONDecodeError:
                pass
        raise ValueError("Impossibile estrarre JSON valido.")

    # Ora accetta 'file_obj' come primo parametro
    def parse_complex_diet(self, file_obj, custom_instructions: str = None):
        if not self.client:
            raise ValueError("Client Gemini non inizializzato.")

        # Estrai testo dallo stream (RAM)
        raw_text = self._extract_text_from_pdf(file_obj)
        if not raw_text:
            raise ValueError("PDF vuoto o illeggibile.")
        
        # Applica sanitizzazione GDPR
        diet_text = self._sanitize_text(raw_text)

        model_name = settings.GEMINI_MODEL
        final_instruction = custom_instructions if custom_instructions else self.system_instruction
        
        try:
            print(f"🤖 Analisi Gemini ({model_name})... Custom Prompt: {bool(custom_instructions)}")
            
            prompt = f"""
            Analizza il seguente testo ed estrai i dati della dieta e le sostituzioni CAD.
            <source_document>
            {diet_text}
            </source_document>
            """

            response = self.client.models.generate_content(
                model=model_name,
                contents=prompt,
                config=types.GenerateContentConfig(
                    system_instruction=final_instruction,
                    response_mime_type="application/json",
                    response_schema=OutputDietaCompleto
                )
            )
            
            if hasattr(response, 'parsed') and response.parsed:
                return response.parsed
            if hasattr(response, 'text') and response.text:
                return self._extract_json_from_text(response.text)
            
            raise ValueError("Risposta vuota da Gemini")

        except Exception as e:
            print(f"⚠️ Errore con Gemini: {e}")
            raise e