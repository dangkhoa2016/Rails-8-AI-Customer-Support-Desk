"""Open the LOCAL Rails AI Search inside YOUR active Colab notebook.

Run from a cell in the same attached Colab runtime:
  %run /content/Rails-8-AI-Customer-Support-Desk/script/open_private_ai_search_colab.py

Do not share the resulting URL or notebook output. The Rails server must
already run on 127.0.0.1:3068 with its separate password-form preview gate.
"""
from google.colab import output
import urllib.request
import urllib.error

url = "http://127.0.0.1:3068/__private_preview/sign_in"
response = urllib.request.urlopen(url, timeout=5)
page = response.read().decode("utf-8")
if response.status != 200 or "Private Colab preview" not in page or 'type="password"' not in page:
    raise RuntimeError("Expected password-form gate is not active; refusing to expose the preview.")
print("Private password-form gate: PASS (no password displayed).")
print("The application opens INSIDE this Colab notebook output, not a new tab.")
print("Enter only the password from ~/.config/rails8-support-desk-modal/rails-private-preview.env")
print("Do not share the proxy URL or secret, and do not enter real customer data.")
output.serve_kernel_port_as_iframe(3068, path="/__private_preview/sign_in", height="950", width="100%")
