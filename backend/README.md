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

Apply migrations to create the schema (first run, and after pulling any
migration someone else added):

```bash
alembic upgrade head
```

Seed two demo accounts (first run only):

```bash
python seed.py
```

## Run

```bash
uvicorn app.main:app --reload
```

API docs: http://127.0.0.1:8000/docs

## Changing the data model

1. Edit `app/models.py`.
2. Generate a migration: `alembic revision --autogenerate -m "describe the change"`.
3. **Read the generated file in `alembic/versions/`** - autogenerate is a
   starting point, not a guarantee (it can miss things like column renames,
   which it sees as a drop + add and will silently lose data).
4. Apply it: `alembic upgrade head`.
5. Commit the migration file alongside your model change.
