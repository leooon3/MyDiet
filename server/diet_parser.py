import google.generativeai as genai
import typing_extensions as typing
import os
import json
import pdfplumber

# --- DEFINIZIONE DELLA STRUTTURA DATI (Schema) ---
class Ingrediente(typing.TypedDict):
    nome: str
    quantita: str

class Piatto(typing.TypedDict):
    nome_piatto: str
    tipo: str  # "composto" o "singolo"
    quantita_totale: str # Solo se è singolo (es. "200 gr")
    ingredienti: list[Ingrediente] # Solo se è composto

class Pasto(typing.TypedDict):
    tipo_pasto: str # "Colazione", "Pranzo", "Cena", etc.
    elenco_piatti: list[Piatto]

class GiornoDieta(typing.TypedDict):
    giorno: str # "Lunedì", "Martedì", etc.
    pasti: list[Pasto]

class DietParser:
    def __init__(self):
        # 1. Configurazione Esplicita dell'API Key
        api_key = os.environ.get("GOOGLE_API_KEY")
        if not api_key:
            print("⚠️ ATTENZIONE: GOOGLE_API_KEY non trovata nelle variabili d'ambiente!")
        else:
            genai.configure(api_key=api_key)
        
        self.system_instruction = """
        Sei un assistente nutrizionista esperto in parsing di documenti dietetici.
        Il tuo compito è estrarre il piano alimentare dal testo fornito e strutturarlo in JSON.

        **REGOLE FONDAMENTALI DI PARSING (CRUCIALE):**
        1.  **Analisi Riga per Riga:** Leggi attentamente ogni riga di alimento.
        2.  **Rilevamento PIATTO COMPOSTO:**
            * Se una riga contiene il nome di un piatto ma **NON contiene alcuna quantità**, consideralo un "Titolo di Piatto Composto".
            * Gli alimenti nelle righe immediatamente successive con un pallino (•) sono i suoi **Ingredienti**.
        3.  **Rilevamento ALIMENTO SINGOLO:**
            * Se una riga contiene un nome alimento E **contiene una quantità**, è un "Alimento Singolo".
            * **ECCEZIONE:** Se un alimento con quantità segue un piatto composto ma NON ha il pallino (•), è un piatto separato.
        
        Restituisci solo il JSON strutturato secondo lo schema fornito.
        """

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
            raise e # Rilanciamo l'errore per fermare il processo
        return text

    def parse_complex_diet(self, file_path: str):
        # 1. Estrazione Testo
        diet_text = self._extract_text_from_pdf(file_path)
        if not diet_text:
            raise ValueError("Il PDF sembra vuoto o non leggibile.")

        # 2. Lista di modelli da provare (in ordine di preferenza)
        models_to_try = [
            "gemini-1.5-flash",
            "gemini-1.5-flash-001",
            "gemini-1.5-flash-latest",
            "gemini-pro" # Fallback sicuro
        ]

        last_error = None

        for model_name in models_to_try:
            print(f"🔄 Tentativo con modello: {model_name}...")
            try:
                model = genai.GenerativeModel(
                    model_name=model_name,
                    system_instruction=self.system_instruction,
                    generation_config={
                        "response_mime_type": "application/json",
                        "response_schema": list[GiornoDieta]
                    }
                )

                prompt = f"""
                Analizza il seguente testo estratto da una dieta e applica RIGOROSAMENTE le regole.
                
                TESTO DIETA:
                {diet_text}
                """

                response = model.generate_content(prompt)
                print(f"✅ Successo con {model_name}!")
                return json.loads(response.text)

            except Exception as e:
                print(f"⚠️ Fallito con {model_name}: {e}")
                last_error = e
                continue # Prova il prossimo modello
        
        # Se siamo qui, tutti i modelli hanno fallito
        print("❌ Tutti i tentativi con Gemini sono falliti.")
        raise last_error # Rilancia l'ultimo errore al server (così l'app riceve 500)