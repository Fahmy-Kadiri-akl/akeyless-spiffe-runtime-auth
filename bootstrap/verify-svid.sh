#!/usr/bin/env bash
# Validate a SPIRE JWT-SVID before handing it to Akeyless: structure, sub,
# audience, expiry, and (when python3 + cryptography are available) the signature
# against the SPIRE bundle JWKS. SPIRE issues EC (ES256) SVIDs; RSA is handled
# too if your trust domain is configured for it.
#
#   ./verify-svid.sh <svid.jwt | path-to-file> [bundle.jwks]
set -euo pipefail

INPUT="${1:?usage: verify-svid.sh <svid-file-or-string> [bundle.jwks]}"
BUNDLE="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/spire/.data/bundle.jwks}"
EXPECT_SUB="${WORKLOAD_SPIFFE_ID:-spiffe://example.org/ns/default/sa/secret-consumer}"
EXPECT_AUD="${JWT_AUDIENCE:-akeyless}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required for this script" >&2
  exit 1
fi

if [ -f "$INPUT" ]; then SVID="$(cat "$INPUT")"; else SVID="$INPUT"; fi
[ -n "$SVID" ] || { echo "ERROR: empty SVID" >&2; exit 1; }

echo "=============================================="
echo "  JWT-SVID DIAGNOSTIC"
echo "=============================================="

python3 - "$SVID" "$BUNDLE" "$EXPECT_SUB" "$EXPECT_AUD" <<'PY'
import base64, json, sys, time
from cryptography.hazmat.primitives.asymmetric import ec, rsa, padding
from cryptography.hazmat.primitives.asymmetric.utils import encode_dss_signature
from cryptography.hazmat.primitives import hashes
from cryptography.exceptions import InvalidSignature

svid, bundle_path, expect_sub, expect_aud = sys.argv[1:5]
counts = {"PASS": 0, "FAIL": 0, "WARN": 0}

def line(level, msg):
    counts[level] += 1
    print(f"  {level}: {msg}")

def summarize():
    print(f"\n  {counts['PASS']} passed, {counts['FAIL']} failed, {counts['WARN']} warnings")
    sys.exit(1 if counts["FAIL"] else 0)

def b64url_decode(s):
    return base64.urlsafe_b64decode(s + '=' * (-len(s) % 4))

try:
    h_b64, p_b64, sig_b64 = svid.split('.')
    header = json.loads(b64url_decode(h_b64))
    payload = json.loads(b64url_decode(p_b64))
    line("PASS", f"JWT structure (alg={header.get('alg')}, kid={header.get('kid')})")
except Exception as e:
    line("FAIL", f"not a parseable JWT ({e})")
    summarize()

sub = payload.get("sub", "")
line("PASS" if sub == expect_sub else "FAIL",
     f"sub = {sub}" if sub == expect_sub else f"sub = {sub} (expected {expect_sub})")

aud = payload.get("aud", [])
auds = [aud] if isinstance(aud, str) else list(aud)
line("PASS" if expect_aud in auds else "FAIL",
     f"aud contains '{expect_aud}'" if expect_aud in auds else f"aud {auds} lacks '{expect_aud}'")

exp = payload.get("exp")
if exp is None:
    line("FAIL", "no exp claim")
elif exp <= int(time.time()):
    line("FAIL", f"expired (exp={exp})")
else:
    line("PASS", f"not expired (ttl={exp - int(time.time())}s)")

try:
    with open(bundle_path) as f:
        bundle = json.load(f)
except Exception as e:
    line("WARN", f"could not read bundle {bundle_path} ({e}); signature not verified")
    summarize()

kid = header.get("kid")
keys = bundle.get("keys", [])
match = [k for k in keys if kid is None or k.get("kid") == kid]
if not match:
    line("FAIL", f"no JWKS key matches kid={kid} (bundle has {len(keys)} keys)")
    summarize()
jwk = match[0]
signing_input = (h_b64 + '.' + p_b64).encode()
signature = b64url_decode(sig_b64)

try:
    if jwk.get("kty") == "EC":
        curve = {"P-256": ec.SECP256R1(), "P-384": ec.SECP384R1(),
                 "P-521": ec.SECP521R1()}[jwk["crv"]]
        pub = ec.EllipticCurvePublicNumbers(
            int.from_bytes(b64url_decode(jwk["x"]), "big"),
            int.from_bytes(b64url_decode(jwk["y"]), "big"), curve).public_key()
        # JWT ECDSA signatures are raw r||s; cryptography expects DER.
        half = len(signature) // 2
        der_sig = encode_dss_signature(
            int.from_bytes(signature[:half], "big"),
            int.from_bytes(signature[half:], "big"))
        pub.verify(der_sig, signing_input, ec.ECDSA(hashes.SHA256()))
    elif jwk.get("kty") == "RSA":
        pub = rsa.RSAPublicNumbers(
            int.from_bytes(b64url_decode(jwk["e"]), "big"),
            int.from_bytes(b64url_decode(jwk["n"]), "big")).public_key()
        pub.verify(signature, signing_input, padding.PKCS1v15(), hashes.SHA256())
    else:
        line("FAIL", f"unsupported JWKS key type {jwk.get('kty')}")
        summarize()
    line("PASS", f"signature verifies against bundle JWKS ({jwk.get('kty')}/{jwk.get('crv', jwk.get('alg'))})")
except InvalidSignature:
    line("FAIL", "signature does NOT verify against bundle JWKS")
except ImportError:
    line("WARN", "cryptography module missing; signature not verified (pip install cryptography)")
except Exception as e:
    line("FAIL", f"signature verification error ({e})")

summarize()
PY
