import pdfplumber
import re
import json

class DietParser:
    def __init__(self):
        self.diet_plan = {} 
        self.substitutions_db = {} 

    def parse_simple_diet(self, pdf_path):
        return self.diet_plan

    def parse_complex_diet(self, pdf_path):
        print(f"--- [DEBUG] Avvio Analisi V21 (Sniper): {pdf_path} ---")
        
        # Mappa dei pasti standard
        meal_map = {
            "seconda colazione": "Seconda Colazione",
            "prima colazione": "Colazione",
            "colazione": "Colazione",
            "spuntino serale": "Spuntino Serale",
            "spuntino": "Spuntino",
            "pranzo": "Pranzo",
            "merenda": "Merenda",
            "cena": "Cena",
            "nell'arco della giornata": "Nell'Arco Della Giornata"
        }
        
        # RIPARAZIONI TESTUALI (Eseguite PRIMA di cercare i titoli)
        repairs = [
            (r"Nell'\s*arc\s*odella\s*giornata", "Nell'Arco Della Giornata"), 
            (r"Nell'\s*arc\s*odella", "Nell'Arco Della"),
            (r"Spu\s*ntino", "Spuntino"),
            (r"Pri\s*ma", "Prima"), (r"Seco\s*nda", "Seconda"), (r"ser\s*ale", "serale"),
            (r"vasett\s*o", "vasetto"), (r"cucchiain\s*[io]", "cucchiaino"),
            (r"ipis\s*elli", "i piselli"), (r"ifru\s*tti", "i frutti"),
            (r"mar\s*e\b", "mare"), (r"onas\s*ello", "o nasello"), (r"nas\s*ello", "nasello"),
            (r"affum\s*icato", "affumicato"), (r"veget\s*ale", "vegetale"),
            (r"sem\s*ola", "semola"), (r"natur\s*ale", "naturale"),
            (r"integr\s*ale", "integrale"), (r"screm\s*ato", "scremato"),
            (r"co\s*npasta", "con pasta"), (r"cott\s*o", "cotto"),
            (r"epeperoncino", "e peperoncino"), (r"eparmigi\s*ano", "e parmigiano"),
            (r"pa\s*rmigiano", "parmigiano"), (r"fon\s*dente", "fondente"),
            (r"mist\s*[ae]", "mista"), (r"tazz\s*a", "tazza"), (r"cu\s*cchiaini", "cucchiaini")
        ]

        # Trigger Pasti
        meal_triggers = {
            r"Nell'?\s*Arco\s*Della\s*Giornata": "Nell'Arco Della Giornata",
            r"Nell\W*arc\W*odella": "Nell'Arco Della Giornata", 
            r"Seconda\s+Colazione": "Seconda Colazione",
            r"(?:Prima\s+)?Colazione": "Colazione",
            r"Spuntino\s+Serale": "Spuntino Serale",
            r"Pranzo": "Pranzo",
            r"Merenda": "Merenda",
            r"Cena": "Cena",
            r"(?<!Spuntino )Spuntino(?! Serale)": "Spuntino"
        }
        
        search_order = sorted(meal_triggers.keys(), key=len, reverse=True)
        table_settings = {"vertical_strategy": "text", "horizontal_strategy": "text", "snap_tolerance": 4}
        
        with pdfplumber.open(pdf_path) as pdf:
            for i, page in enumerate(pdf.pages):
                text = page.extract_text()
                if not text: continue

                day_match = re.search(r"(?:Piano alimentare\s+)?(Lunedì|Martedì|Mercoledì|Giovedì|Venerdì|Sabato|Domenica)", text, re.IGNORECASE)
                if day_match:
                    current_day = day_match.group(1).title()
                    if current_day not in self.diet_plan: self.diet_plan[current_day] = {}

                    tables = page.extract_tables(table_settings)
                    current_meal = "Generico"
                    
                    for table in tables:
                        for row in table:
                            clean_row = [str(x).strip() for x in row if x and str(x).strip()]
                            if not clean_row: continue
                            
                            row_str = " ".join(clean_row)

                            # 1. Pulizia Spazzatura
                            if any(x in row_str.lower() for x in ["copyright", "progeo", "elaborato da", "pagina"]):
                                continue

                            # 2. Riparazioni Testuali
                            for pattern, replacement in repairs:
                                row_str = re.sub(pattern, replacement, row_str, flags=re.IGNORECASE)
                            
                            while re.search(r'\b\d+\s+\d\b', row_str): 
                                row_str = re.sub(r'\b(\d+)\s+(\d)\b', r'\1\2', row_str)
                            row_str = re.sub(r'\b([a-z])\s+([a-z]{3,})', r'\1\2', row_str)

                            # 3. Rilevamento Pasto
                            found_title_key = None
                            for pattern, meal_name in meal_triggers.items():
                                if re.search(pattern, row_str, re.IGNORECASE):
                                    current_meal = meal_name
                                    if current_meal not in self.diet_plan[current_day]: 
                                        self.diet_plan[current_day][current_meal] = []
                                    found_title_key = pattern
                                    break 
                            
                            if found_title_key:
                                row_str = re.sub(found_title_key, "", row_str, flags=re.IGNORECASE).strip()
                                if len(row_str) < 3: continue

                            # 4. Estrazione Cibo
                            cad = None
                            qty = "N/A"
                            name = row_str
                            
                            end_qty_match = re.search(r'(?:gr|g)\s*(\d+)$', row_str, re.IGNORECASE)
                            if end_qty_match:
                                qty = f"gr {end_qty_match.group(1)}"
                                name = re.sub(r'(?:gr|g)\s*\d+$', '', row_str, flags=re.IGNORECASE).strip()
                            else:
                                cad_match = re.search(r'\b(\d{2,4})$', row_str)
                                if cad_match:
                                    cad = cad_match.group(1)
                                    name = row_str[:cad_match.start()].strip()
                                qty_match = re.search(r'(\b(?:gr|g|ml)\s*\d+|\d+\s*(?:gr|g|ml)|1\s*vasetto|n\s*\d+|n°\s*\d+)', name, re.IGNORECASE)
                                if qty_match:
                                    qty = qty_match.group(1)
                                    name = name.replace(qty, "").strip()

                            name = re.sub(r'^[•\-\.]\s*', '', name).strip()
                            
                            # 5. FILTRO SNIPER (Rimuove residui orfani)
                            # Se la riga è solo "giornata" o "serale" (perché la regex ha tolto il resto), ignorala
                            if name.lower() in ["giornata", "serale", "arco", "della"]:
                                continue

                            is_valid_food = (cad is not None) or (qty != "N/A") or ("•" in " ".join(clean_row)) or (found_title_key and len(name) > 2)
                            
                            if is_valid_food and len(name) > 2:
                                is_title = any(re.search(p, name, re.IGNORECASE) for p in meal_triggers.keys())
                                if not is_title:
                                    if current_meal not in self.diet_plan[current_day]: 
                                        self.diet_plan[current_day][current_meal] = []
                                    self.diet_plan[current_day][current_meal].append({"name": name, "qty": qty, "cad_code": cad})

            # --- FASE 2: SOSTITUZIONI (Invariata) ---
            full_text = ""
            for page in pdf.pages:
                extracted = page.extract_text()
                if extracted: full_text += extracted + "\n"
            if "Elenco numeri di CAD" in full_text: full_text = full_text.split("Elenco numeri di CAD")[0]

            cad_blocks = re.split(r"CAD:\s*(\d+)", full_text)
            for i in range(1, len(cad_blocks), 2):
                code = cad_blocks[i]
                content = cad_blocks[i+1]
                options = []
                description_lines = []
                lines = content.split('\n')
                for line in lines[:20]:
                    line = line.strip()
                    if not line or "ALIMENTO" in line or "Qty" in line: continue
                    is_option = line.startswith("-") or (len(line) < 50 and any(char.isdigit() for char in line))
                    if is_option:
                        opt_name = line.replace("-", "").strip()
                        opt_qty = "N/A"
                        qty_match = re.search(r'((?:gr|g)\s*\d+)', opt_name, re.IGNORECASE)
                        if qty_match:
                            opt_qty = qty_match.group(1)
                            opt_name = opt_name.replace(opt_qty, "").strip()
                        options.append({"name": opt_name, "qty": opt_qty})
                    else:
                        if len(line) > 10: description_lines.append(line)
                self.substitutions_db[code] = {"info": " ".join(description_lines), "options": options}

        return self.diet_plan, self.substitutions_db

if __name__ == "__main__":
    parser = DietParser()
    file_complesso = "Dieta di Leone Riccardo Della visita del 23-09-25.pdf"
    try:
        import os
        if not os.path.exists(file_complesso):
            print(f"ERRORE: File '{file_complesso}' non trovato!")
        else:
            plan, subs = parser.parse_complex_diet(file_complesso)
            final_data = {"type": "complex", "plan": plan, "substitutions": subs}
            with open("dieta.json", "w", encoding="utf-8") as f:
                json.dump(final_data, f, indent=2, ensure_ascii=False)
            print("\n[SUCCESS] File 'dieta.json' RIGENERATO CON FIX ORFANI!")
    except Exception as e:
        print(f"Errore: {e}")