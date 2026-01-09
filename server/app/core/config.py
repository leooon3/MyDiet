import os
import json
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    # Loads from .env automatically
    GOOGLE_API_KEY: str = ""
    GEMINI_MODEL: str = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")
    
    # [SECURITY FIX] Strict CORS Policy
    # Add your Flutter Web production domain here
    ALLOWED_ORIGINS: list[str] = [
        "http://localhost:3000",
        "http://localhost:8080",
        "http://localhost:4000",
        "http://localhost:5000",
        "https://mydiet-74rg.onrender.com",
        "https://my-diet-admin.vercel.app",
        "https://app.kybo.it/",
        "https://app.kybo.it"
    ]

    # Paths
    DIET_PDF_PATH: str = "temp_dieta.pdf"
    RECEIPT_PATH_PREFIX: str = "temp_scontrino"
    DIET_JSON_PATH: str = "dieta.json"


    class Config:
        env_file = ".env"

settings = Settings()