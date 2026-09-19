"""Entry point for Render's midman-reminder-cron job - see ../../render.yaml.

Calls the backend's own POST /reminders/property-inspection/run-due over
Render's private network (BACKEND_HOSTPORT, wired via render.yaml's
fromService), authenticating with the shared CRON_SECRET since the cron
job has no staff login of its own - see get_current_user_optional in
app/security.py and the X-Cron-Secret handling in app/main.py.
"""

import os
import sys

import httpx


def main() -> int:
    hostport = os.environ["BACKEND_HOSTPORT"]
    secret = os.environ["CRON_SECRET"]
    url = f"http://{hostport}/reminders/property-inspection/run-due"
    response = httpx.post(url, headers={"X-Cron-Secret": secret}, timeout=30)
    response.raise_for_status()
    print(response.json())
    return 0


if __name__ == "__main__":
    sys.exit(main())
