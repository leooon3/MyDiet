# 🍃 NutriScan - La Tua Dieta Intelligente

**NutriScan** è un'applicazione mobile innovativa che digitalizza la tua dieta cartacea e gestisce automaticamente la tua dispensa. Grazie all'intelligenza artificiale, trasforma i PDF del nutrizionista e le foto degli scontrini in un piano alimentare interattivo e una lista della spesa automatica.

---

## ✨ Funzionalità Chiave

- 📄 **Parsing Dieta PDF:** Carica il file del nutrizionista e l'app estrarrà automaticamente pasti, quantità e giorni.
- 🧾 **Scanner Scontrino:** Fai una foto allo scontrino e l'app aggiungerà i prodotti compatibili direttamente al tuo "Frigo Virtuale".
- 🥦 **Modalità Relax:** Nasconde i grammi di frutta e verdura per ridurre lo stress, suggerendo porzioni "a volontà" o "1 frutto".
- 🔄 **Sostituzioni Smart:** Clicca su un alimento per vedere le alternative consentite (basate sui codici CAD della dieta).
- 🛒 **Lista Spesa Automatica:** Calcola cosa ti manca in base ai pasti dei prossimi giorni e a cosa hai già in dispensa.
- ✏️ **Modifica Rapida:** Correggi manualmente nomi o quantità se l'AI ha sbagliato a leggere.

---

## 🚀 Installazione

Il progetto è diviso in due parti: il **Cervello (Backend Python)** che elabora i dati e l'**App (Frontend Flutter)** che usi sul telefono.

### 1. Requisiti

- **Python 3.8+** installato sul PC.
- **Flutter SDK** installato e configurato.
- **Tesseract OCR** installato sul PC (per leggere gli scontrini).

### 2. Configurazione Backend (Python)

Il backend si trova nella cartella `test/`.

1.  Installa le dipendenze Python:
    ```bash
    pip install fastapi uvicorn pdfplumber pytesseract pillow thefuzz python-multipart
    ```
2.  Assicurati di avere `tesseract` installato (su Windows di solito in `C:\Program Files\Tesseract-OCR`).

### 3. Configurazione Frontend (Flutter)

L'app si trova nella cartella `diet_app/`.

1.  Installa le dipendenze Flutter:
    ```bash
    cd diet_app
    flutter pub get
    ```
2.  **IMPORTANTE:** Apri il file `lib/main.dart` e cerca la riga `const String serverUrl`. Sostituisci l'indirizzo IP con l'indirizzo IP locale del tuo computer (es. `http://192.168.1.15:8000`).

---

## ▶️ Come Avviare il Progetto

### Passo 1: Avvia il Cervello (Server)

Apri un terminale nella cartella `test` ed esegui:

```bash
python server.py
Il server partirà su https://www.google.com/search?q=http://0.0.0.0:8000 e sarà pronto a ricevere file.

Passo 2: Avvia l'App
Collega il tuo telefono Android (con Debug USB attivo) o usa un emulatore. Apri un altro terminale nella cartella diet_app ed esegui:

Bash

flutter run
📖 Guida all'Uso
Primo Avvio: Apri il menu laterale (in alto a sinistra) e premi "Carica Nuova Dieta PDF". Seleziona il file PDF del nutrizionista.

Gestione Pasti: Scorri i giorni. Se un alimento non ti va, premi l'icona Swap (frecce) per cambiarlo. Tieni premuto su un cibo per modificarlo manualmente (matita).

Dispensa: Vai nella tab "Dispensa". Aggiungi cibi manualmente o premi "Scan Scontrino" per caricare una foto o un PDF della spesa.

Mangiare: Quando mangi un pasto, clicca sul pallino accanto al cibo. Se l'alimento è in dispensa, verrà scalato automaticamente e apparirà una spunta verde ✅.

Lista Spesa: Premi il carrello 🛒 in alto a destra. Scegli per quanti giorni vuoi comprare e l'app ti dirà esattamente cosa manca.

🛠️ Struttura del Progetto
test/

server.py: Il server API che riceve i file.

diet_parser.py: Motore di analisi del PDF della dieta (con regex avanzate).

receipt_scanner.py: Motore OCR per leggere gli scontrini e filtrarli.

diet_app/

lib/main.dart: Tutto il codice dell'interfaccia Flutter.

assets/: Cartella dove vengono salvati temporaneamente i JSON (se usati localmente).

👨‍💻 Crediti
Sviluppato da Riccardo Leone.
```
