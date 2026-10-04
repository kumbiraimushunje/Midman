# MidMen

Premium remote-execution and concierge platform. See
[`PROJECT_PLAN.md`](PROJECT_PLAN.md) for the full concept, data model,
status lifecycle, and phased roadmap.

## Quick start

Backend (`backend/README.md` has the full version):

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
copy .env.example .env
# edit .env with your Neon DATABASE_URL and a JWT_SECRET
alembic upgrade head   # creates the schema
python seed.py         # first run only, creates demo accounts
uvicorn app.main:app --reload
```

Mobile:

```bash
cd mobile
flutter pub get
flutter run
```

The app talks to `http://10.0.2.2:8000` on the Android emulator (maps to
your machine's localhost) — see `mobile/lib/api_service.dart` to point it
elsewhere (a physical device, or a deployed API URL).
