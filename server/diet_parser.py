import google.generativeai as genai
import typing_extensions as typing
import os
import json
import pdfplumber

# --- SCHEMI DATI PER GEMINI (Input/Output Strutturato) ---

# 1. Schema per gli ingredienti dei piatti composti
class Ingrediente(typing.TypedDict):
    nome: str
    quantita: str

# 2. Schema per il Piatto (Singolo o Composto)
class Piatto(typing.TypedDict):
    nome_piatto: str
    tipo: str  # "composto" o "singolo"
    cad_code: int # IL CODICE CAD per le sostituzioni (es. 1045)
    quantita_totale: str # Solo se è singolo
    ingredienti: list[Ingrediente] # Solo se è composto

# 3. Schema per il Pasto (Colazione, Pranzo, etc.)
class Pasto(typing.TypedDict):
    tipo_pasto: str # Es: "Colazione", "Spuntino", "Pranzo", "Cena"
    elenco_piatti: list[Piatto]

# 4. Schema per il Giorno
class GiornoDieta(typing.TypedDict):
    giorno: str 
    pasti: list[Pasto]

# --- SCHEMA PER LE TABELLE DI SOSTITUZIONE (CAD) ---
class OpzioneSostituzione(typing.TypedDict):
    nome: str
    quantita: str

class GruppoSostituzione(typing.TypedDict):
    cad_code: int # Es. 19
    titolo: str # Es. "PASTA CON I PISELLI"
    opzioni: list[OpzioneSostituzione]

# --- OUTPUT FINALE COMPLETO ---
class OutputDietaCompleto(typing.TypedDict):
    piano_settimanale: list[GiornoDieta]
    tabella_sostituzioni: list[GruppoSostituzione]

class DietParser:
    def __init__(self):
        # Configurazione API Key robusta
        api_key = os.environ.get("GOOGLE_API_KEY")
        if not api_key:
            print("❌ ERRORE CRITICO: GOOGLE_API_KEY non trovata!")
        else:
            clean_key = api_key.strip().replace('"', '').replace("'", "")
            genai.configure(api_key=clean_key)

        self.system_instruction = """
        Sei un nutrizionista esperto. Il tuo compito è analizzare il documento PDF della dieta ed estrarre le informazioni in un JSON strutturato.
        
        DEVI ESTRARRE DUE SEZIONI PRINCIPALI:

        1. **IL PIANO SETTIMANALE**:
           - Analizza giorno per giorno (Lunedì, Martedì...).
           - Estrai TUTTI i pasti presenti: "Prima colazione", "Seconda colazione", "Pranzo", "Merenda", "Cena", "Spuntino serale" , "Nell'Arco della giornata".
           - **Codici CAD**: Se accanto a un piatto c'è scritto "CAD" seguito da un numero (es. "Pane... CAD 1770"), estrai quel numero nel campo 'cad_code'.
           - **Tipologia Piatto**:
             - "composto": Se è un titolo di ricetta senza quantità (es. "Pasta e fagioli") seguito da ingredienti con pallino (•).
             - "singolo": Se è un alimento con la sua quantità sulla stessa riga (es. "Mela 200gr").

        2. **LE TABELLE DI SOSTITUZIONE (CAD)**:
           - Scorri fino alla fine del documento dove ci sono le schede numerate "CAD: [Numero]".
           - Per ogni CAD, crea un oggetto 'GruppoSostituzione'.
           - 'cad_code': Il numero del CAD.
           - 'titolo': Il nome del gruppo (es. "PASTA CON I PISELLI").
           - 'opzioni': La lista degli alimenti alternativi elencati nella tabella sotto il titolo. Prendi solo Nome e Quantità.

        Restituisci un unico JSON completo rispettando lo schema 'OutputDietaCompleto'.
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
            raise e
        return text

    def parse_complex_diet(self, file_path: str):
        diet_text = self._extract_text_from_pdf(file_path)
        if not diet_text:
            raise ValueError("PDF vuoto o illeggibile.")

        # Usiamo il modello Pro che ha una finestra di contesto più ampia per leggere tutto il file
        model_name = "gemini-1.5-pro"
        
        try:
            print(f"🤖 Richiesta a Gemini ({model_name}) per analisi completa...")
            model = genai.GenerativeModel(
                model_name=model_name,
                system_instruction=self.system_instruction,
                generation_config={
                    "response_mime_type": "application/json",
                    "response_schema": OutputDietaCompleto
                }
            )

            prompt = f"Analizza questa dieta completa (Piano Settimanale + Tabelle CAD):\n{diet_text}"

            response = model.generate_content(prompt)
            return json.loads(response.text)

        except Exception as e:
            print(f"⚠️ Errore con {model_name}: {e}")
            # Tentativo di fallback con Flash se Pro fallisce o non è disponibile
            try:
                print("🔄 Provo fallback con gemini-1.5-flash...")
                model = genai.GenerativeModel(
                    model_name="gemini-1.5-flash",
                    system_instruction=self.system_instruction,
                    generation_config={
                        "response_mime_type": "application/json",
                        "response_schema": OutputDietaCompleto
                    }
                )
                response = model.generate_content(prompt)
                return json.loads(response.text)
            except Exception as e2:
                print(f"❌ Fallito anche il fallback: {e2}")
                raise e2