import os
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    # Loads from .env automatically
    GOOGLE_API_KEY: str = ""
    # [FIX] Corrected model name. "2.5" does not exist.
    GEMINI_MODEL: str = "gemini-2.5-flash"
    
    # Paths
    DIET_PDF_PATH: str = "temp_dieta.pdf"
    RECEIPT_PATH_PREFIX: str = "temp_scontrino"
    DIET_JSON_PATH: str = "dieta.json"

    # Keywords
    MEAL_MAPPING: dict = {
        "prima colazione": "Colazione",
        "seconda colazione": "Seconda Colazione",
        "spuntino mattina": "Seconda Colazione",
        "pranzo": "Pranzo",
        "merenda": "Merenda",
        "cena": "Cena",
        "spuntino serale": "Spuntino Serale"
    }

    class Config:
        env_file = ".env"

settings = Settings()