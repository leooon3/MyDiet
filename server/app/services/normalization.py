from app.core.config import settings

def normalize_meal_name(meal_name: str) -> str:
    """
    Normalizes the meal name using the mapping defined in settings.
    Example: "prima colazione" -> "Colazione"
    """
    if not meal_name:
        return "Altro"
        
    cleaned = meal_name.lower().strip()
    
    # Direct Key Match
    if cleaned in settings.MEAL_MAPPING:
        return settings.MEAL_MAPPING[cleaned]
    
    # Partial Match (e.g. "colazione (ore 8:00)")
    for key, val in settings.MEAL_MAPPING.items():
        if key in cleaned:
            return val
            
    return cleaned.capitalize()