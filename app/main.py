from flask import Flask, jsonify

app = Flask(__name__)


@app.after_request
def set_security_headers(response):
    """Add conservative headers to every response, including errors."""
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Content-Security-Policy"] = "default-src 'none'; frame-ancestors 'none'"
    response.headers["Cache-Control"] = "no-store"
    return response


@app.route("/")
def hello():
    return jsonify(message="Hello from Flask demo!"), 200


@app.route("/healthz")
def healthz():
    """Liveness endpoint for the container HEALTHCHECK and Kubernetes probes."""
    return jsonify(status="ok"), 200
