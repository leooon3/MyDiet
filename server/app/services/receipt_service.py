import pytesseract
from PIL import Image
import pdfplumber
import re
from thefuzz import process, fuzz

class ReceiptScanner:
    def __init__(self, allowed_foods_list: list[str]):
        """
        Initialize with a list of allowed food names provided by the client.
        This makes the service stateless.
        """
        self.allowed_foods = set()
        self.corrections = {
            "YOG": "YOGURT",
            "NAURALE": "NATURALE",
            "S/G": "PROSCIUTTO",
            "COTTO": "PROSCIUTTO COTTO",
            "FESA": "AFFETTATO DI TACCHINO",
            "PETTO": "PETTO DI POLLO",
            "FILETTI": "FILETTI",
            "MACINATO": "CARNE MACINATA",
            "NODINI": "MOZZARELLA",
            "FIOCCHI": "FIOCCHI DI LATTE"
        }
        self._load_from_list(allowed_foods_list)

    def _load_from_list(self, food_list):
        self.allowed_foods.add("filetti") # Hardcoded generic
        
        for name in food_list:
            clean = self._clean_diet_name(name)
            if len(clean) > 2:
                self.allowed_foods.add(clean)
                
        print(f"[INFO] Receipt Context: {len(self.allowed_foods)} allowed foods loaded.")

    def _clean_diet_name(self, raw_name):
        name = raw_name.lower().strip()
        name = re.sub(r'^[\W_]+', '', name)
        name = re.sub(r'\s+(?:gr|g)\s*\d+.*', '', name)
        return name.strip()

    def extract_text_from_file(self, file_path):
        text = ""
        try:
            if file_path.lower().endswith('.pdf'):
                print("  📄 Mode: Digital PDF")
                with pdfplumber.open(file_path) as pdf:
                    for page in pdf.pages:
                        extracted = page.extract_text()
                        if extracted: text += extracted + "\n"
            else:
                print("  📷 Mode: Image OCR")
                text = pytesseract.image_to_string(Image.open(file_path), lang='ita')
        except Exception as e:
            print(f"[FILE ERROR] {e}")
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
        print(f"\n--- Receipt Analysis (Stateless): {file_path} ---")
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

        for line in lines:
            original_line = line.strip().upper()
            if len(original_line) < 4: continue 
            if any(bad_word in original_line for bad_word in BLACKLIST): continue

            cleaned_line = self.clean_receipt_line(original_line)
            if len(cleaned_line) < 3: continue

            # Fuzzy Match Logic
            candidates = process.extract(cleaned_line.lower(), self.allowed_foods, scorer=fuzz.token_set_ratio, limit=5)
            
            best_match = None
            best_score = 0
            
            for candidate, score in candidates:
                if score < 75: continue 
                if len(candidate) < 5 and score < 90: continue

                if best_match is None:
                    best_match = candidate
                    best_score = score
                else:
                    diff_old = abs(len(cleaned_line) - len(best_match))
                    diff_new = abs(len(cleaned_line) - len(candidate))
                    
                    if score > best_score:
                        best_match = candidate
                        best_score = score
                    elif score == best_score and diff_new < diff_old:
                        best_match = candidate
                        best_score = score

            if best_match:
                print(f"  ✅ MATCH: '{cleaned_line}' -> '{best_match.title()}' ({best_score}%)")
                found_items.append({
                    "name": best_match.title(), 
                    "quantity": 1.0, 
                    "original_scan": original_line
                })

        return found_items