import pytesseract
from PIL import Image
import json
import os
import pdfplumber
import re
from thefuzz import process, fuzz

class ReceiptScanner:
    def __init__(self, diet_json_path):
        self.allowed_foods = set()
        self.load_allowed_foods(diet_json_path)
        
        # Mappa correzioni (Scontrino -> Italiano)
        self.corrections = {
            "YOG": "YOGURT",
            "NAURALE": "NATURALE",
            "S/G": "PROSCIUTTO",
            "COTTO": "PROSCIUTTO COTTO",
            "FESA": "AFFETTATO DI TACCHINO",
            "PETTO": "PETTO DI POLLO",
            "FILETTI": "FILETTI", # Lasciamo generico!
            "MACINATO": "CARNE MACINATA",
            "NODINI": "MOZZARELLA",
            "FIOCCHI": "FIOCCHI DI LATTE"
        }

    def load_allowed_foods(self, json_path):
        try:
            with open(json_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
            
            # Aggiungiamo manualmente i Filetti generici per permettere il match
            self.allowed_foods.add("filetti")
            
            def clean_diet_name(raw_name):
                name = raw_name.lower().strip()
                name = re.sub(r'^[\W_]+', '', name)
                name = re.sub(r'\s+(?:gr|g)\s*\d+.*', '', name)
                return name.strip()

            plan = data.get("plan", {})
            for day, meals in plan.items():
                for meal, foods in meals.items():
                    for food in foods:
                        clean = clean_diet_name(food['name'])
                        if len(clean) > 2: self.allowed_foods.add(clean)
            
            subs = data.get("substitutions", {})
            for code, sub_data in subs.items():
                for opt in sub_data.get('options', []):
                    opt_name = opt['name'] if isinstance(opt, dict) else opt
                    clean = clean_diet_name(opt_name)
                    if len(clean) > 2: self.allowed_foods.add(clean)
                        
            print(f"[INFO] Database Dieta: {len(self.allowed_foods)} alimenti caricati.")
        except Exception as e:
            print(f"[ERRORE] Impossibile leggere dieta: {e}")

    def extract_text_from_file(self, file_path):
        text = ""
        try:
            if file_path.lower().endswith('.pdf'):
                print("  📄 Modalità PDF Digitale...")
                with pdfplumber.open(file_path) as pdf:
                    for page in pdf.pages:
                        extracted = page.extract_text()
                        if extracted: text += extracted + "\n"
            else:
                print("  📷 Modalità Immagine (OCR)...")
                text = pytesseract.image_to_string(Image.open(file_path), lang='ita')
        except Exception as e:
            print(f"[ERRORE FILE] {e}")
        return text

    def clean_receipt_line(self, line):
        line = re.sub(r'\s*\*VI.*', '', line)
        line = re.sub(r'\s+\d+[,.]\d+.*', '', line)
        words = line.split()
        fixed_words = []
        for w in words:
            replaced = False
            for abbr, full in self.corrections.items():
                if abbr in w:
                    fixed_words.append(full)
                    replaced = True
                    break
            if not replaced:
                fixed_words.append(w)
        return " ".join(fixed_words)

    def scan_receipt(self, file_path):
        print(f"\n--- Analisi Scontrino V6 (Smart Logic): {file_path} ---")
        full_text = self.extract_text_from_file(file_path)
        if not full_text: return []

        lines = full_text.split('\n')
        found_items = []
        
        BLACKLIST = [
            "TOTALE", "CASSA", "IVA", "EURO", "SCONTRINO", "RESTO", "PAGAMENTO", 
            "TRENTO", "VIA", "TEL", "PARTITA", "DOC", "VENDITA", "PREZZO", "DESCRIZIONE",
            "FIRMA", "ELETTRONICA", "SERVER", "RT", "DUPLICARD", "CUORI", "TERRITORIO",
            "ASSOCIAZIONI", "RISPARMIATO", "SALDO", "PRECEDENTE", "MOVIMENTATI", "UTILIZZATI",
            "SACCHETTO", "BIO", "BORSA", "SPESA", "SCONTO", "UNISPESA", "IPER", "POLIS",
            "BRENNERO", "DOCUMENTO", "COMMERCIALE"
        ]

        print("[INFO] Ricerca alimenti...")
        for line in lines:
            original_line = line.strip().upper()
            if len(original_line) < 4: continue 
            if any(bad_word in original_line for bad_word in BLACKLIST): continue

            cleaned_line = self.clean_receipt_line(original_line)
            if len(cleaned_line) < 3: continue

            # --- NUOVA LOGICA DI CONFRONTO ---
            # Estraiamo i migliori 5 candidati invece di uno solo
            candidates = process.extract(cleaned_line.lower(), self.allowed_foods, scorer=fuzz.token_set_ratio, limit=5)
            
            best_match = None
            best_score = 0
            
            # Filtriamo e scegliamo il migliore basandoci su Punteggio E Lunghezza
            for candidate, score in candidates:
                if score < 75: continue # Soglia minima
                
                # Se è una parola corta (<5 lettere), siamo severissimi
                if len(candidate) < 5 and score < 90: continue

                # Se non abbiamo ancora un match, prendiamo questo
                if best_match is None:
                    best_match = candidate
                    best_score = score
                else:
                    # Se il punteggio è simile (o migliore), controlliamo la lunghezza!
                    # Preferiamo la stringa più simile in lunghezza alla riga dello scontrino
                    # Esempio: "MELANZANE" (len 9) vs "Melanzane" (len 9) -> Diff 0
                    # Esempio: "MELANZANE" (len 9) vs "Pasta con le melanzane" (len 22) -> Diff 13
                    
                    diff_old = abs(len(cleaned_line) - len(best_match))
                    diff_new = abs(len(cleaned_line) - len(candidate))
                    
                    # Se il nuovo candidato ha score maggiore O (score simile ma lunghezza molto migliore)
                    if score > best_score:
                        best_match = candidate
                        best_score = score
                    elif score == best_score and diff_new < diff_old:
                        # Stesso punteggio ma lunghezza più precisa -> VINCE IL NUOVO!
                        print(f"    -> Preferisco '{candidate}' a '{best_match}' per lunghezza.")
                        best_match = candidate
                        best_score = score

            if best_match:
                print(f"  ✅ TROVATO: '{cleaned_line}' -> Match: '{best_match.title()}' ({best_score}%)")
                found_items.append({
                    "name": best_match.title(), 
                    "quantity": 1.0, 
                    "original_scan": original_line
                })

        return found_items

if __name__ == "__main__":
    diet_file = "dieta.json"
    if not os.path.exists(diet_file): diet_file = "../diet_app/assets/dieta.json"
    
    scanner = ReceiptScanner(diet_file)
    file_scontrino = "scontrino.pdf" 
    
    if os.path.exists(file_scontrino):
        items = scanner.scan_receipt(file_scontrino)
        if items:
            with open("spesa_importata.json", "w", encoding='utf-8') as f:
                json.dump(items, f, indent=2, ensure_ascii=False)
            print(f"\n[SUCCESS] Salvati {len(items)} alimenti in 'spesa_importata.json'!")
        else:
            print("\n[WARN] Nessun alimento trovato.")
    else:
        print(f"\n[ATTENZIONE] Manca il file '{file_scontrino}'")