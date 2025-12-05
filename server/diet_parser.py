import google.generativeai as genai
import typing_extensions as typing
import os
import json
import pdfplumber

# --- SCHEMA ---
class Ingrediente(typing.TypedDict):
    nome: str
    quantita: str

class Piatto(typing.TypedDict):
    nome_piatto: str
    tipo: str  
    quantita_totale: str 
    ingredienti: list[Ingrediente]

class Pasto(typing.TypedDict):
    tipo_pasto: str 
    elenco_piatti: list[Piatto]

class GiornoDieta(typing.TypedDict):
    giorno: str 
    pasti: list[Pasto]

class DietParser:
    def __init__(self):
        # 1. Configurazione API Key
        api_key = os.environ.get("GOOGLE_API_KEY")
        if not api_key:
            print("❌ ERRORE CRITICO: GOOGLE_API_KEY non trovata nelle env vars!")
        else:
            # Pulizia preventiva: rimuove spazi o virgolette accidentali
            clean_key = api_key.strip().replace('"', '').replace("'", "")
            genai.configure(api_key=clean_key)
            print(f"🔑 API Key configurata (prime 5 cifre): {clean_key[:5]}...")

        self.system_instruction = """
        Sei un nutrizionista. Estrai la dieta in JSON rigoroso.
        Regole:
        1. Piatto senza quantità = Titolo Composto.
        2. Righe sotto con pallino (•) = Ingredienti.
        3. Alimento con quantità = Piatto Singolo.
        """

    def _debug_list_available_models(self):
        """Chiede a Google quali modelli sono disponibili per questa chiave"""
        print("🔍 DIAGNOSTICA: Richiedo lista modelli a Google...")
        try:
            available = []
            for m in genai.list_models():
                if 'generateContent' in m.supported_generation_methods:
                    available.append(m.name)
            print(f"✅ Modelli Trovati: {available}")
            return available
        except Exception as e:
            print(f"❌ DIAGNOSTICA FALLITA: La chiave API sembra non funzionare. Errore: {e}")
            return []

    def _extract_text_from_pdf(self, pdf_path: str) -> str:
        text = ""
        try:
            with pdfplumber.open(pdf_path) as pdf:
                for page in pdf.pages:
                    extracted = page.extract_text()
                    if extracted:
                        text += extracted + "\n"
        except Exception as e:
            print(f"❌ Errore lettura PDF: {e}")
            raise e 
        return text

    def parse_complex_diet(self, file_path: str):
        # 1. Diagnostica preliminare
        available_models = self._debug_list_available_models()
        
        # 2. Estrazione Testo
        diet_text = self._extract_text_from_pdf(file_path)
        if not diet_text:
            raise ValueError("Il PDF sembra vuoto o non leggibile.")

        # 3. Selezione intelligente del modello
        # Cerchiamo un modello valido tra quelli disponibili
        chosen_model = None
        
        # Priorità
        preferences = ["models/gemini-1.5-flash", "models/gemini-1.5-pro", "models/gemini-pro"]
        
        # Cerca il primo match tra preferenze e disponibili
        for pref in preferences:
            if pref in available_models:
                chosen_model = pref
                break
        
        # Fallback: se non trovo le preferenze, uso il primo disponibile che sia "gemini"
        if not chosen_model:
            for m in available_models:
                if "gemini" in m:
                    chosen_model = m
                    break
        
        if not chosen_model:
            # Se la lista era vuota o nessun modello gemini trovato
            # Provo comunque con il nome standard sperando funzioni
            print("⚠️ Nessun modello trovato in lista, provo blind attempt con 'gemini-1.5-flash'")
            chosen_model = "gemini-1.5-flash"
        else:
            print(f"🎯 Modello selezionato: {chosen_model}")

        # 4. Generazione
        try:
            # Rimuoviamo il prefisso 'models/' se presente per l'instanziazione
            model_name_clean = chosen_model.replace("models/", "")
            
            model = genai.GenerativeModel(
                model_name=model_name_clean,
                system_instruction=self.system_instruction,
                generation_config={
                    "response_mime_type": "application/json",
                    "response_schema": list[GiornoDieta]
                }
            )

            prompt = f"Analizza questa dieta:\n{diet_text}"

            response = model.generate_content(prompt)
            return json.loads(response.text)

        except Exception as e:
            print(f"❌ Errore FATALE con modello {chosen_model}: {e}")
            raise e