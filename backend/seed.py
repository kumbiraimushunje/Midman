"""Creates a couple of demo accounts for local testing:
  customer@midman.app   / password123   (role=customer)
  staff@midman.app      / password123   (role=staff, can approve + update status)

Run once: python seed.py
"""

from datetime import date

from app.database import Base, SessionLocal, engine
from app.id_generator import generate_member_id
from app.models import User, UserRole
from app.security import hash_password

Base.metadata.create_all(bind=engine)

db = SessionLocal()
try:
    if not db.query(User).filter(User.email == "customer@midman.app").first():
        db.add(
            User(
                member_id=generate_member_id(db, "Demo Customer"),
                full_name="Demo Customer",
                date_of_birth=date(1990, 1, 1),
                email="customer@midman.app",
                phone="+10000000001",
                password_hash=hash_password("password123"),
                country_of_residence="Zimbabwe",
                role=UserRole.customer,
            )
        )
    if not db.query(User).filter(User.email == "staff@midman.app").first():
        db.add(
            User(
                member_id=generate_member_id(db, "Demo Staff"),
                full_name="Demo Staff",
                date_of_birth=date(1990, 1, 1),
                email="staff@midman.app",
                phone="+10000000002",
                password_hash=hash_password("password123"),
                country_of_residence="Zimbabwe",
                role=UserRole.staff,
            )
        )
    db.commit()
    print("Seed complete.")
finally:
    db.close()
