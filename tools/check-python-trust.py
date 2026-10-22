"""Test installed Requests/certifi TLS defaults without startup hooks or credentials.

Invoked by Test-VerifiedRuntimeUpdate.ps1 using Python -I -S.
"""
import importlib.metadata
import json
import ssl
import sys
import sysconfig

if not sys.flags.isolated or not sys.flags.no_site:
    raise RuntimeError("Run with -I -S")
sys.path.append(sysconfig.get_path("purelib"))
import requests

hosts = ["rustsec.org"]
for issuer in ["dv-g3b", "dv-g3c", "ov-g3b", "ov-g3c", "ev-g3b", "ev-g3c"]:
    hosts += [f"{issuer}{cross}-emudhra.we-have-a-problem.com" for cross in ["", "-aaa"]]
hosts += ["dv-g3b-noct-emudhra.we-have-a-problem.com", "dv-g3b-aaa-noct-emudhra.we-have-a-problem.com"]


def certificate_error(error):
    pending, visited = [error], set()
    while pending:
        current = pending.pop()
        if id(current) in visited:
            continue
        visited.add(id(current))
        if isinstance(current, ssl.SSLCertVerificationError):
            return True
        if isinstance(current, BaseException):
            pending.extend(arg for arg in current.args if isinstance(arg, BaseException))
            pending.extend(item for item in [current.__cause__, current.__context__,
                                           getattr(current, "reason", None)] if isinstance(item, BaseException))
    return False


checks = []
with requests.Session() as session:
    session.trust_env = False
    for host in hosts:
        try:
            with session.head(f"https://{host}/", verify=True, timeout=8, allow_redirects=False) as response:
                checks.append({"host": host, "classification": "tls_accepted", "http_status": response.status_code})
        except requests.RequestException as error:
            checks.append({"host": host, "classification": "certificate_rejected" if certificate_error(error)
                           else "unverified_transport_failure", "error_type": type(error).__name__})
print(json.dumps({"python_version": sys.version.split()[0], "openssl_version": ssl.OPENSSL_VERSION,
                  "pip_version": importlib.metadata.version("pip"),
                  "certifi_version": importlib.metadata.version("certifi"),
                  "requests_version": requests.__version__, "checks": checks,
                  "positive_control_passed": checks[0]["classification"] == "tls_accepted",
                  "scope": "Installed Requests/certifi default verification, no env/proxies/netrc or startup hooks; existing app overrides remain separate."}))
