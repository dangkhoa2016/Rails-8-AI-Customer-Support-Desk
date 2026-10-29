"""Diagnose Colab browser-side rendering and proxyPort without secrets or GPU.

Run this from the connected Google Colab NOTEBOOK CELL, not a terminal:
  %run /content/Rails-8-AI-Customer-Support-Desk/script/diagnose_colab_iframe.py
"""
import json
import socket
from urllib import request as url_request
from IPython.display import display, HTML
from google.colab import output

print("=== COLAB IFRAME DIAGNOSTICS (read only, no tokens) ===", flush=True)
try:
    with socket.create_connection(("127.0.0.1",3068),timeout=3):
        print("LOCAL_PORT_3068: TCP_OK", flush=True)
    with url_request.urlopen("http://127.0.0.1:3068/__private_preview/sign_in",timeout=6) as r:
        page = r.read().decode("utf-8",errors="replace")
        print("RAILS_GATE: HTTP",r.status,"PASSWORD_FORM", "Private Colab preview" in page,flush=True)
except Exception as exc:
    print("RAILS_LOCAL_ERROR:",type(exc).__name__, str(exc)[:150],flush=True)

display(HTML(
    '<div style="margin:12px 0;padding:16px;background:#132a43;'
    'color:#fff;border:2px solid #5ec7f6;border-radius:10px">'
    '<strong>COLAB HTML OUTPUT TEST</strong> — If you can see this blue panel,'
    ' HTML rendering is working without JavaScript.</div>'
))
print("Testing browser JavaScript permission and Colab proxy (no model calls)...",flush=True)

script=r"""(async () => {
  const result = {
    browser_js: true,
    colab_api: Boolean(window.google && google.colab && google.colab.kernel),
    access_allowed: null,
    proxy_port: 'NOT_ATTEMPTED',
    proxy_response: null,
    browser_error: null
  };
  try {
    if (!result.colab_api) return result;
    result.access_allowed = Boolean(google.colab.kernel.accessAllowed);
    if (!result.access_allowed) return result;
    const proxy = await google.colab.kernel.proxyPort(3068);
    const url = new URL('/__private_preview/sign_in', proxy);
    result.proxy_port = 'RESOLVED';
    // Report only a trusted hostname suffix, never the actual proxy URL.
    result.proxy_host_class = url.hostname.endsWith('.colab.dev') ? 'colab.dev'
      : url.hostname.endsWith('.googleusercontent.com') ? 'googleusercontent.com'
      : 'OTHER';
    const response = await fetch(url.toString(), {method: 'GET', credentials:'include'});
    result.proxy_response = response.status;
  } catch(err) {
    result.browser_error = String(err && err.name || 'Error') + ': ' +
      String(err && err.message || '').slice(0, 140);
  }
  return result;
})()"""
try:
    state = output.eval_js(script, timeout_sec=25)
    print("BROWSER_CHECK:",json.dumps(state,ensure_ascii=False,sort_keys=True),flush=True)
    if state.get('access_allowed') is False:
        print("ROOT_CAUSE: Colab accessAllowed is FALSE. Built-in iframe helper returns"
              " without rendering. Verify notebook runtime access permissions and browser"
              " extensions; do not change Rails or disable its password gate.",flush=True)
    elif state.get('proxy_port')=='RESOLVED' and state.get('proxy_response')==200:
        print("PROXY_OK: browser reached the password form. Run the iframe helper again.",flush=True)
    elif state.get('proxy_port')=='RESOLVED' and state.get('proxy_response') is None:
        print("PROXY_URL_RESOLVED_BUT_FETCH_FAILED: no HTTP status was received/readable.",flush=True)
        print("Possible causes include browser CORS restrictions, local DNS resolution"
              " for *.prod.r.colab.dev, browser security settings or blocked requests."
              " This does NOT establish a Rails HTTP error.",flush=True)
        print("Colab documented a DNS issue for *.prod.r.colab.dev on 2026-10-27."
              " In Edge/Chrome consider selecting Google Public DNS under Secure DNS,"
              " then refresh the notebook; do not change Rails security.",flush=True)
    elif state.get('browser_error'):
        print("BROWSER_PROXY_ERROR: This is a frontend/proxy issue; not a Rails"
              " model inference problem.",flush=True)
except Exception as exc:
    print("BROWSER_JS_EVAL_FAILED:", type(exc).__name__, str(exc)[:220],flush=True)
    print("Check whether the blue HTML panel rendered and whether notebook outputs"
          " are trusted/enabled. The proxy diagnostic did NOT bypass security.",flush=True)
