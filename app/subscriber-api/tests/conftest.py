"""Test configuration: the application reads its settings at import time, so the environment
is prepared here before any test module imports ``subscriber_api.main``."""

import os

os.environ["API_KEY"] = "test-key"
os.environ["APP_ENV"] = "test"
