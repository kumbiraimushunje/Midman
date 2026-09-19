from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    database_url: str
    jwt_secret: str
    jwt_expire_minutes: int = 60

    # Lets the Render cron job trigger POST /reminders/property-inspection/run-due
    # without a staff login of its own - see security.get_current_user_optional
    # and main.run_due_inspection_reminders. Leave blank and only staff/admin JWTs
    # can trigger that endpoint (the KYC Review bell-icon button still works).
    cron_secret: str = ""

    openai_api_key: str = ""
    openai_model: str = "gpt-4o-mini"

    smtp_host: str = ""
    smtp_port: int = 587
    smtp_username: str = ""
    smtp_password: str = ""
    smtp_from_email: str = "notifications@midman.app"

    # Leave s3_bucket_name blank and evidence uploads fall back to local
    # disk storage (backend/uploads/) - no AWS needed for local dev.
    aws_access_key_id: str = ""
    aws_secret_access_key: str = ""
    aws_region: str = "us-east-1"
    s3_bucket_name: str = ""

    # Where the customer's browser lands after completing a payment on either
    # gateway's hosted page (a page in the deployed web app). Shared by both
    # providers below - it plays the same role in each's API.
    payment_return_url: str = ""

    # Zimbabwe-local payments (EcoCash/OneMoney/ZimSwitch/local bank cards).
    # Leave blank and the app works normally, just without the Paynow checkout
    # option - customers only see the international-card option instead.
    paynow_integration_id: str = ""
    paynow_integration_key: str = ""
    paynow_result_url: str = ""  # our public /payments/paynow/webhook URL - Paynow calls this server-to-server

    # International card payments. Leave blank and the app works normally,
    # just without the international-card checkout option.
    flutterwave_secret_key: str = ""
    flutterwave_webhook_secret_hash: str = ""  # the "secret hash" you set in the Flutterwave dashboard's webhook settings


settings = Settings()
