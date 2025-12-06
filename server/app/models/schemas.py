from pydantic import BaseModel, Field
from typing import List, Optional

# --- Gemini/LLM Raw Output Models ---

class Ingredient(BaseModel):
    nome: str
    quantita: str

class Dish(BaseModel):
    nome_piatto: str
    tipo: Optional[str] = None
    cad_code: int = 0
    quantita_totale: str = ""
    ingredienti: List[Ingredient] = []

class Meal(BaseModel):
    tipo_pasto: str
    elenco_piatti: List[Dish]

class DietDay(BaseModel):
    giorno: str
    pasti: List[Meal]

class SubstitutionOption(BaseModel):
    nome: str
    quantita: str

class SubstitutionGroup(BaseModel):
    cad_code: int
    titolo: str
    opzioni: List[SubstitutionOption]

class DietResponseRaw(BaseModel):
    piano_settimanale: List[DietDay]
    tabella_sostituzioni: List[SubstitutionGroup]

# --- App Internal/API Response Models ---

class AppDishItem(BaseModel):
    name: str
    qty: str
    cad_code: int
    is_composed: bool
    ingredients: List[Ingredient]

class AppSubstitution(BaseModel):
    name: str
    options: List[dict]  # [{"name": "x", "qty": "y"}]

class AppDietPlan(BaseModel):
    plan: dict  # { "Monday": { "Lunch": [AppDishItem...] } }
    substitutions: dict # { "123": AppSubstitution }