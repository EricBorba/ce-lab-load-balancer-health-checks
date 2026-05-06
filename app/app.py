from flask import Flask, jsonify
import requests

app = Flask(__name__)

# --- IMDSv2 helper ---
def get_metadata(path):
    # Get IMDSv2 token
    token = requests.put(
        "http://169.254.169.254/latest/api/token",
        headers={"X-aws-ec2-metadata-token-ttl-seconds": "21600"},
        timeout=2
    ).text

    # Use token to query metadata
    response = requests.get(
        f"http://169.254.169.254/latest/meta-data/{path}",
        headers={"X-aws-ec2-metadata-token": token},
        timeout=2
    )
    return response.text


# Fetch once at startup
try:
    INSTANCE_ID = get_metadata("instance-id")
    AZ = get_metadata("placement/availability-zone")
except Exception:
    INSTANCE_ID = "unknown"
    AZ = "unknown"


@app.route("/health")
def health():
    return jsonify({
        "status": "healthy",
        "instance": INSTANCE_ID,
        "az": AZ
    })


@app.route("/")
def home():
    return f"""
    <html>
      <head><title>Load Balanced App</title></head>
      <body style="font-family: Arial; text-align: center; padding: 50px;">
        <h1>Load Balanced Application</h1>
        <p><strong>Instance:</strong> {INSTANCE_ID}</p>
        <p><strong>AZ:</strong> {AZ}</p>
      </body>
    </html>
    """


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)