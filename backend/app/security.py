from datetime import datetime, timedelta

import bcrypt
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
from sqlalchemy.orm import Session

from .config import settings
from .database import get_db
from .models import User

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")
oauth2_scheme_optional = OAuth2PasswordBearer(tokenUrl="/auth/login", auto_error=False)

# bcrypt's own limit - reject/truncate before hashing rather than erroring deep in the C extension.
_MAX_PASSWORD_BYTES = 72


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8")[:_MAX_PASSWORD_BYTES], bcrypt.gensalt()).decode("utf-8")


def verify_password(plain: str, hashed: str) -> bool:
    return bcrypt.checkpw(plain.encode("utf-8")[:_MAX_PASSWORD_BYTES], hashed.encode("utf-8"))


def create_access_token(user_id: str) -> str:
    expire = datetime.utcnow() + timedelta(minutes=settings.jwt_expire_minutes)
    payload = {"sub": user_id, "exp": expire}
    return jwt.encode(payload, settings.jwt_secret, algorithm="HS256")


def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)) -> User:
    credentials_error = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=["HS256"])
        user_id = payload.get("sub")
        if user_id is None:
            raise credentials_error
    except JWTError:
        raise credentials_error

    user = db.query(User).filter(User.id == user_id, User.deleted_at.is_(None)).first()
    if user is None:
        raise credentials_error
    return user


def get_current_user_optional(token: str | None = Depends(oauth2_scheme_optional), db: Session = Depends(get_db)) -> User | None:
    """Same as get_current_user, but returns None instead of raising when
    there's no (or an invalid) bearer token - for endpoints like the
    reminder cron trigger that also accept a non-JWT auth path."""
    if token is None:
        return None
    try:
        return get_current_user(token, db)
    except HTTPException:
        return None
