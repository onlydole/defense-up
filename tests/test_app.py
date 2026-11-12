"""Tests for the demo app.

These use only the standard library and Flask's test client, so the test
stage in the Dockerfile needs no packages beyond the locked runtime set.
"""

import unittest

from app.main import app

EXPECTED_HEADERS = {
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
    "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'",
    "Cache-Control": "no-store",
}


class AppTest(unittest.TestCase):
    def setUp(self):
        self.client = app.test_client()

    def test_hello(self):
        response = self.client.get("/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json(), {"message": "Hello from Flask demo!"})

    def test_healthz(self):
        response = self.client.get("/healthz")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json(), {"status": "ok"})

    def test_security_headers_on_success(self):
        response = self.client.get("/")
        for name, value in EXPECTED_HEADERS.items():
            self.assertEqual(response.headers.get(name), value)

    def test_security_headers_on_not_found(self):
        response = self.client.get("/missing")
        self.assertEqual(response.status_code, 404)
        for name, value in EXPECTED_HEADERS.items():
            self.assertEqual(response.headers.get(name), value)

    def test_write_methods_are_rejected(self):
        self.assertEqual(self.client.post("/").status_code, 405)


if __name__ == "__main__":
    unittest.main()
