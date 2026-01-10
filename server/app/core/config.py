import os
import json
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    # Loads from .env automatically
    GOOGLE_API_KEY: str = ""
    GEMINI_MODEL: str = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")
    ENV: str = os.getenv("ENV", "DEV") # [NUOVO] Legge l'ambiente (DEV o PROD)
    
    _dev_origins: list[str] = [
        "http://localhost:3000",
        "http://localhost:8080",
        "http://localhost:4000",
        "http://localhost:5000",
        "https://my-diet-admin.vercel.app",
    ]
    
    _prod_origins: list[str] = [
        "https://app.kybo.it",
        "https://kybo.it"
    ]

    @property
    def ALLOWED_ORIGINS(self) -> list[str]:
        if self.ENV == "PROD":
            return self._prod_origins
        # In DEV o STAGING permettiamo tutto (locale + prod per test)
        return self._dev_origins + self._prod_origins

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