#!/usr/bin/env python3
"""Convert a SPIRE trust bundle into a standard JWKS for Akeyless.

`spire-server bundle show -format spiffe -output json` lists the JWT-SVID
signing keys under `jwt_authorities` as base64-encoded SubjectPublicKeyInfo
blobs, not as standard JWKs. Akeyless's OAuth2/JWT auth method needs a standard
JWKS document: `{"keys": [ {kty, crv, alg, kid, x, y}, ... ]}`. This script
converts each authority into an EC JWK and prints the JWKS as JSON.

Usage:
    spiffe-bundle-to-jwks.py <bundle.spiffe.json> [> bundle.jwks]

Requires the `cryptography` package (pip install cryptography).
"""
import base64
import json
import sys

from cryptography.hazmat.primitives.serialization import load_der_public_key

_CURVE = {"secp256r1": "P-256", "secp384r1": "P-384", "secp521r1": "P-521"}
# JWT "alg" for ECDSA per curve. P-521 maps to ES512 in JWS, not ES521.
_ALG = {"P-256": "ES256", "P-384": "ES384", "P-521": "ES512"}


def b64u(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def main(bundle_path: str) -> int:
    with open(bundle_path) as f:
        bundle = json.load(f)

    keys = []
    for authority in bundle.get("jwt_authorities", []):
        spki = base64.b64decode(authority["public_key"])
        public_key = load_der_public_key(spki)
        crv = _CURVE.get(public_key.curve.name)
        if crv is None:
            raise SystemExit(f"unsupported curve {public_key.curve.name}")
        size = (public_key.curve.key_size + 7) // 8
        numbers = public_key.public_numbers()
        keys.append({
            "kty": "EC",
            "crv": crv,
            "alg": _ALG[crv],
            "kid": authority["key_id"],
            "x": b64u(numbers.x.to_bytes(size, "big")),
            "y": b64u(numbers.y.to_bytes(size, "big")),
        })

    json.dump({"keys": keys}, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        raise SystemExit(2)
    raise SystemExit(main(sys.argv[1]))
