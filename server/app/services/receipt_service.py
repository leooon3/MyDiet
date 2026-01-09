import typing_extensions as typing
from google import genai
from google.genai import types
from app.core.config import settings

# --- DATA SCHEMAS ---
class ReceiptItem(typing.TypedDict):
    name: str
    quantity: str 

class ReceiptAnalysis(typing.TypedDict):
    items: list[ReceiptItem]

class ReceiptScanner:
    def __init__(self, allowed_foods_list: list[str]):
        # [INIT] Setup Gemini Client
        api_key = settings.GOOGLE_API_KEY
        if not api_key:
            print("❌ CRITICAL ERROR: GOOGLE_API_KEY not found!")
            self.client = None
        else:
            clean_key = api_key.strip().replace('"', '').replace("'", "")
            self.client = genai.Client(api_key=clean_key)

        # Optimize list for Prompt Context
        self.allowed_foods_str = ", ".join([str(f).lower().strip() for f in allowed_foods_list if f])
        print(f"[INFO] Receipt Context: {len(allowed_foods_list)} allowed foods loaded for AI context.")

        # [FIX] Relaxed rules to allow all food items while prioritizing the diet list
        self.system_instruction = """
        You are an AI assistant for a diet app. Your task is to analyze receipt images and extract purchased food items.
        
        CRITICAL RULES:
        1. **Extract Food Items**: Identify and extract all clearly identifiable food and grocery items from the image.
        2. **Use Context for Cleanup**: You are provided with an 'ALLOWED FOODS LIST'. 
           - If an item on the receipt matches a food in the list (even vaguely), prefer the naming from the list.
           - If an item is NOT in the list but is clearly food, EXTRACT IT ANYWAY using its name from the receipt.
        3. **Ignore Non-Food**: Strictly ignore taxes, totals, discounts, store info, payment details, and non-edible goods.
        4. **Output Format**: Return a strictly structured JSON with a list of items.
        """

    def scan_receipt(self, file_content, mime_type):
        print(f"\n--- Receipt Analysis (Gemini Vision) ---")
        
        if not self.client:
            print("⚠️ Gemini Client missing. Returning empty.")
            return []

        prompt = f"""
        <allowed_foods_list>
        {self.allowed_foods_str}
        </allowed_foods_list>

        Analizza l'immagine dello scontrino fornita. Estrai gli articoli che corrispondono alla lista consentita.
        """

        try:
            model_name = settings.GEMINI_MODEL
            print(f"🤖 Sending Image + Prompt to Gemini ({model_name})...")

            # 1. Prepare Image Part
            image_part = types.Part.from_bytes(data=file_content, mime_type=mime_type)

            # 2. Call Gemini (Multimodal: Text + Image)
            response = self.client.models.generate_content(
                model=model_name,
                contents=[prompt, image_part],
                config=types.GenerateContentConfig(
                    system_instruction=self.system_instruction,
                    response_mime_type="application/json",
                    response_schema=ReceiptAnalysis
                )
            )

            # 3. Parse Response
            found_items = []
            if hasattr(response, 'parsed') and response.parsed:
                data = response.parsed
                # Gestione robusta sia per dict che per oggetti tipizzati
                items_list = data.get('items', []) if isinstance(data, dict) else data.items
                
                for item in items_list:
                    name = item.get('name') if isinstance(item, dict) else item.name
                    qty = item.get('quantity') if isinstance(item, dict) else item.quantity
                    
                    if name:
                        print(f"  ✅ MATCH: {name} (Qty: {qty})")
                        found_items.append({
                            "name": name,
                            "quantity": qty, 
                            "original_scan": name 
                        })
            
            print(f"[SUCCESS] Extracted {len(found_items)} items.")
            return found_items

        except Exception as e:
            print(f"⚠️ Gemini Error: {e}")
            return []