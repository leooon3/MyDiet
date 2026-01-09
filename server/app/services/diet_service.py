import json
import re
import io
import pdfplumber
import os
import typing_extensions as typing
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

# --- DATA SCHEMAS ---
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

        # [DEFAULT SYSTEM INSTRUCTION]
        self.system_instruction = """
You are an expert AI Nutritionist and Data Analyst capable of understanding any language.

YOUR TASK:
Extract the weekly diet plan from the provided document.

CRITICAL RULES FOR MULTI-LANGUAGE SUPPORT:
1. **Detect Language**: Read the document in its original language.
2. **Translate Structure (Required)**: 
   - You MUST translate the **Day of the Week** into Italian.
   - You MUST translate the **Meal Category** into Italian.
3. **Preserve Content**: 
   - Keep the **Dish Names**, **Ingredients**, and **Quantities** in the **ORIGINAL LANGUAGE**.

OUTPUT FORMAT (Strict JSON):
{
  "piano_settimanale": [],
  "tabella_sostituzioni": []
}"""

    def _extract_text_from_pdf(self, file_input: typing.Union[str, bytes]) -> str:
        text_buffer = io.StringIO()
        try:
            if isinstance(file_input, bytes):
                if len(file_input) > 10 * 1024 * 1024:
                    raise ValueError("PDF troppo grande (Max 10MB).")
                pdf_file = pdfplumber.open(io.BytesIO(file_input))
            else:
                if os.path.getsize(file_input) > 10 * 1024 * 1024: 
                    raise ValueError("PDF troppo grande.")
                pdf_file = pdfplumber.open(file_input)

            with pdf_file as pdf:
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

    def _sanitize_text(self, text: str) -> str:
        """
        Rimuove PII (Personally Identifiable Information) comuni per GDPR.
        """
        # 1. Codice Fiscale Italiano (Pattern generico)
        text = re.sub(r'[A-Z]{6}\d{2}[A-Z]\d{2}[A-Z]\d{3}[A-Z]', '[GDPR_CF_REDACTED]', text)
        
        # 2. Email
        text = re.sub(r'[\w\.-]+@[\w\.-]+\.\w+', '[GDPR_EMAIL_REDACTED]', text)
        
        # 3. Numeri di telefono (Generico Italia/Intl)
        text = re.sub(r'(?:\+39|0039)?\s?3\d{2}\s?\d{6,7}', '[GDPR_PHONE_REDACTED]', text)
        
        # 4. Pattern Intestazioni Comuni (Rimuove la riga intera)
        lines = text.split('\n')
        cleaned_lines = []
        for line in lines:
            lower_line = line.lower().strip()
            if any(prefix in lower_line for prefix in ['paziente:', 'nome:', 'indirizzo:', 'nato il:', 'cf:', 'dott.', 'biologo', 'nutrizionista']):
                continue # Salta la riga contenente dati anagrafici o medici
            cleaned_lines.append(line)
            
        return "\n".join(cleaned_lines)

    def parse_complex_diet(self, file_input: typing.Union[str, bytes], custom_instructions: str = None):
        if not self.client:
            raise ValueError("Client Gemini non inizializzato (manca API KEY).")

        raw_text = self._extract_text_from_pdf(file_input)

        if not raw_text:
             raise ValueError("PDF vuoto o illeggibile.")
        
        # APPLICAZIONE SANITIZZAZIONE
        safe_text = self._sanitize_text(raw_text)
             
        model_name = settings.GEMINI_MODEL
        final_instruction = custom_instructions if custom_instructions else self.system_instruction
        
        try:
            print(f"🤖 Analisi Gemini ({model_name})... Custom Prompt: {bool(custom_instructions)}")
            
            prompt = f"""
            Analizza il seguente testo ed estrai i dati della dieta e le sostituzioni CAD.
            
            <source_document>
            {safe_text}
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
                # Fallback per parsing manuale se SDK fallisce il binding
                cleaned_json = response.text.replace("```json", "").replace("```", "")
                return json.loads(cleaned_json)
            
            raise ValueError("Risposta vuota da Gemini")

        except Exception as e:
            print(f"⚠️ Errore con Gemini: {e}")
            raise e