from app.core.config import settings

def normalize_meal_name(raw_name: str) -> str:
    """Normalizes PDF meal names to App keys."""
    name = raw_name.lower().strip()
    
    for key, value in settings.MEAL_MAPPING.items():
        if key in name:
            return value
            
    return raw_name.title()