# 🥗 Kybo

**Kybo** is a digital system for diet and pantry management.  
It converts nutritional plans from PDF into interactive schedules and automates shopping lists by scanning receipts.

---

## ✨ Features

- **PDF Diet Parsing**  
  Extracts meals, quantities, and days from unstructured PDF files using **Google Gemini AI**.

- **Receipt Scanner**  
  Adds products to the _Virtual Fridge_ via **OCR** and **fuzzy string matching**.

- **Smart Shopping List**  
  Automatically calculates necessary items by subtracting pantry inventory from the diet plan.

- **Meal Substitution**  
  Suggests alternatives based on food composition codes (**CAD**).

- **Inventory Management**  
  Tracks pantry items and expiration dates.

- **Cross-Platform**  
  Built with **Flutter** (Mobile / Web / Desktop) and **Python** (FastAPI).

---

## 🛠 Tech Stack

### Frontend

- Flutter
- Provider (State Management)
- HTTP

### Backend

- Python
- FastAPI
- Uvicorn

### Hosting

- Render (Backend)

### AI / OCR

- Google Gemini (PDF Parsing)
- Tesseract OCR (Receipts)
- TheFuzz (String Matching)

### Infrastructure

- Firebase (Notifications)

---

## ✅ Prerequisites

- **Flutter SDK**
- _(Optional – for local backend)_
  - Python 3.9+
  - Tesseract OCR

---

## 🚀 Installation

### 1️⃣ Backend

#### Live Environment (Render)

The backend is deployed on **Render**.  
No local installation is required for the client app to function.

#### Local Development (Optional)

```bash
cd server
pip install -r requirements.txt
```

Create a `.env` file inside `server/`:

```ini
GOOGLE_API_KEY=your_gemini_api_key
```

Run the server:

```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

---

### 2️⃣ Frontend (App)

```bash
cd Kybo
flutter pub get
```

Create a `.env` file in `Kybo/assets/`:

```ini
API_URL=https://<your-app-name>.onrender.com
```

#### Firebase Setup

- **Android**: `Kybo/android/app/google-services.json`
- **iOS**: `Kybo/ios/Runner/GoogleService-Info.plist`

Run:

```bash
flutter run
```

---

## 📖 Usage

1. Upload a PDF diet plan
2. Add pantry items manually or by scanning receipts
3. Generate a shopping list for selected days

---

## 📌 Project Status

Personal project — **under active development**.

---

## 👤 Author

**Riccardo Leone**

---

## 📄 License

**All Rights Reserved**  
Intended for personal use only.
