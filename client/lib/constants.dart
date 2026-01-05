import 'package:flutter/material.dart';

// --- CONFIGURAZIONE SERVER ---
// IMPORTANTE: Sostituisci con il TUO indirizzo IP locale aggiornato
const String serverUrl = 'https://Kybo-74rg.onrender.com';

// --- THEME COLORS ---
class AppColors {
  static const primary = Color(0xFF2E7D32); // Primary Green
  static const secondary = Color(0xFFE65100); // Accent Orange
  static const scaffoldBackground = Color(0xFFF5F5F5);
  static const surface = Colors.white;
  static const inputFill = Color(0xFFF5F5F5); // Grey 100 equivalent
}

// --- LISTE KEYWORDS ---
const Set<String> fruitKeywords = {
  'mela',
  'mele',
  'pera',
  'pere',
  'banana',
  'banane',
  'arance',
  'arancia',
  'ananas',
  'kiwi',
  'pesche',
  'albicocche',
  'fragole',
  'ciliegie',
  'prugne',
  'fichi',
  'uva',
  'caco',
  'cachi',
};

const Set<String> veggieKeywords = {
  'zucchine',
  'melanzane',
  'pomodori',
  'cetrioli',
  'insalata',
  'rucola',
  'bieta',
  'spinaci',
  'carote',
  'finocchi',
  'verza',
  'cavolfiore',
  'broccoli',
  'minestrone',
  'verdure',
  'fagiolini',
  'cicoria',
  'radicchio',
  'indivia',
  'zucca',
  'asparagi',
  'peperoni',
  'sedano',
  'lattuga',
  'funghi',
};
