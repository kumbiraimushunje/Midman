"""Creates a couple of demo accounts for local testing:
  customer@midmen.app   / password123   (role=customer)
  staff@midmen.app      / password123   (role=staff, can approve + update status)
  admin@midmen.app      / password123   (role=admin, full Admin System access)

Run `alembic upgrade head` first to create the schema, then: python seed.py
"""

from datetime import date

from app.database import SessionLocal
from app.id_generator import generate_member_id
from app.models import User, UserRole
from app.security import hash_password

db = SessionLocal()
try:
    if not db.query(User).filter(User.email == "customer@midmen.app").first():
        db.add(
            User(
                member_id=generate_member_id(db, "Demo Customer"),
                full_name="Demo Customer",
                date_of_birth=date(1990, 1, 1),
                email="customer@midmen.app",
                phone="+10000000001",
                password_hash=hash_password("password123"),
                country_of_residence="Zimbabwe",
                role=UserRole.customer,
            )
        )
    if not db.query(User).filter(User.email == "staff@midmen.app").first():
        db.add(
            User(
                member_id=generate_member_id(db, "Demo Staff"),
                full_name="Demo Staff",
                date_of_birth=date(1990, 1, 1),
                email="staff@midmen.app",
                phone="+10000000002",
                password_hash=hash_password("password123"),
                country_of_residence="Zimbabwe",
                role=UserRole.staff,
            )
        )
    if not db.query(User).filter(User.email == "admin@midmen.app").first():
        db.add(
            User(
                member_id=generate_member_id(db, "Demo Admin"),
                full_name="Demo Admin",
                date_of_birth=date(1990, 1, 1),
                email="admin@midmen.app",
                phone="+10000000003",
                password_hash=hash_password("password123"),
                country_of_residence="Zimbabwe",
                role=UserRole.admin,
            )
        )
    db.commit()
    print("Seed complete.")
finally:
    db.close()
