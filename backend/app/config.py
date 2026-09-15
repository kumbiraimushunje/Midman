from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    database_url: str
    jwt_secret: str
    jwt_expire_minutes: int = 60

    openai_api_key: str = ""
    openai_model: str = "gpt-4o-mini"

    smtp_host: str = ""
    smtp_port: int = 587
    smtp_username: str = ""
    smtp_password: str = ""
    smtp_from_email: str = "notifications@midman.app"


settings = Settings()
