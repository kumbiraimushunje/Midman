# MidMan backend

FastAPI + PostgreSQL (Neon).

## Setup

```bash
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
copy .env.example .env
```

Edit `.env` and paste in your Neon `DATABASE_URL` (Neon dashboard -> Connect
-> psycopg) and a random `JWT_SECRET`.

## Run

```bash
uvicorn app.main:app --reload
```

Tables are created automatically on startup for now (`Base.metadata.create_all`
in `app/main.py`). Swap this for Alembic migrations before this goes near
production data.

Seed two demo accounts (first run only):

```bash
python seed.py
```

API docs: http://127.0.0.1:8000/docs
