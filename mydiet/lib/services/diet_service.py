import google.generativeai as genai
import os
import pdfplumber
from app.models.schemas import DietResponseRaw

class DietParser:
    def __init__(self):
        api_key = os.environ.get("GOOGLE_API_KEY")
        if not api_key:
            raise ValueError("GOOGLE_API_KEY not found in environment")
        
        # Clean key just in case
        clean_key = api_key.strip().replace('"', '').replace("'", "")
        genai.configure(api_key=clean_key)

        self.system_instruction = """
        You are an expert nutritionist. Analyze the PDF diet plan (table format) and extract data into JSON.
        
        CRITICAL RULES:
        1. EXTRACT CAD CODES: The document is a table. Food name is on the left. The CAD Code is the integer in the far right column. 
           Example: "Tuna ... 1189" -> cad_code: 1189.
        2. SUBSTITUTIONS: Found at the end of the document (Pages 20+). Group by CAD code.
        3. STRICT SCHEMA: You must return valid JSON matching the provided schema.
        """

    def _extract_text_from_pdf(self, pdf_path: str) -> str:
        text = ""
        try:
            with pdfplumber.open(pdf_path) as pdf:
                for page in pdf.pages:
                    # layout=True preserves visual columns, essential for this table format
                    extracted = page.extract_text(layout=True)
                    if extracted:
                        text += extracted + "\n"
        except Exception as e:
            print(f"PDF Read Error: {e}")
            raise e
        return text

    def parse_complex_diet(self, file_path: str) -> DietResponseRaw:
        diet_text = self._extract_text_from_pdf(file_path)
        if not diet_text:
            raise ValueError("Empty PDF extracted.")

        model = genai.GenerativeModel(
            model_name="gemini-2.5-flash",
            system_instruction=self.system_instruction,
            generation_config={
                "response_mime_type": "application/json",
                "response_schema": DietResponseRaw
            }
        )
        
        prompt = f"Analyze the document. Extract CAD codes and Weekly Plan.\n\nTEXT:\n{diet_text}"

        try:
            print("Sending request to Gemini...")
            response = model.generate_content(prompt)
            
            # Validate immediately using Pydantic
            # This throws a clear error if Gemini hallucinates the schema
            return DietResponseRaw.model_validate_json(response.text)
            
        except Exception as e:
            print(f"Gemini/Validation Error: {e}")
            raise e