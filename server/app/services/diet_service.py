import google.generativeai as genai
import typing_extensions as typing
import os
import json
import pdfplumber

# --- SCHEMI DATI ---
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
        api_key = os.environ.get("GOOGLE_API_KEY")
        if not api_key:
            print("❌ ERRORE CRITICO: GOOGLE_API_KEY non trovata!")
        else:
            clean_key = api_key.strip().replace('"', '').replace("'", "")
            genai.configure(api_key=clean_key)

        self.system_instruction = """
        Sei un nutrizionista esperto. Analizza il PDF (che è strutturato come una tabella) ed estrai i dati in JSON.
        
        IL DOCUMENTO HA DUE SEZIONI FONDAMENTALI:

        1. **IL PIANO SETTIMANALE (Pagine iniziali)**:
           - Estrai TUTTI i pasti: Prima colazione, Spuntino, Pranzo, Merenda, Cena, Spuntino serale.
           - **ESTRAZIONE CODICI CAD (CRUCIALE):**
             - Il documento è una tabella. Il nome del cibo è a sinistra. **Il Codice CAD è il numero che si trova nella colonna più a destra della riga.**
             - Esempio Piatto Singolo: "Tonno ... 100gr ... 1189". -> 'cad_code': 1189.
             - Esempio Piatto Composto: "Pasta alle melanzane ... 30". -> 'cad_code': 30.
           - Non ignorare mai il numero a destra, è fondamentale per le sostituzioni.

        2. **L'ELENCO NUMERI DI CAD (Pagine finali)**:
           - Scorri fino alla fine del documento (pag 20+). Troverai tabelle intitolate "Elenco numeri di CAD" o "CAD: [Numero]".
           - Per ogni CAD, crea un 'GruppoSostituzione'.
           - 'cad_code': Il numero identificativo (es. 16, 19, 1076).
           - 'titolo': Il nome dell'alimento principale (es. "PASTA CON I FRUTTI DI MARE").
           - 'opzioni': Elenca gli alimenti alternativi nella tabella sotto il titolo.

        Restituisci un JSON completo.
        """

    def _extract_text_from_pdf(self, pdf_path: str) -> str:
        text = ""
        try:
            with pdfplumber.open(pdf_path) as pdf:
                for page in pdf.pages:
                    # Estraiamo il testo mantenendo il layout visivo per aiutare a capire le colonne
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
            raise ValueError("PDF vuoto.")

        # Usiamo gemini-2.5-flash che dal tuo log precedente risulta disponibile e performante
        model_name = "gemini-2.5-flash" 
        
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
            
            prompt = f"Analizza l'intero documento e recupera tutti i codici CAD (colonna destra) e le tabelle finali.\n\nTESTO DOCUMENTO:\n{diet_text}"

            response = model.generate_content(prompt)
            return json.loads(response.text)

        except Exception as e:
            print(f"⚠️ Errore con Gemini: {e}")
            raise e