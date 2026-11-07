#!/usr/bin/env python3
"""Renew public loopback TLS fixtures; requires Python's cryptography package.

This does not use or create production credentials. The committed server key is
public test data. CA private keys exist only in this process and are discarded.
"""

from datetime import datetime, timedelta, timezone
from ipaddress import ip_address
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID


DIRECTORY = Path(__file__).resolve().parent
PEM = serialization.Encoding.PEM


def name(common_name):
    return x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, common_name)])


def write_certificate(filename, builder, signing_key):
    certificate = builder.sign(signing_key, hashes.SHA256())
    (DIRECTORY / filename).write_bytes(certificate.public_bytes(PEM))


def ca(filename, common_name, serial):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    subject = name(common_name)
    builder = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(subject)
        .public_key(key.public_key())
        .serial_number(serial)
        .not_valid_before(datetime(2020, 1, 1, tzinfo=timezone.utc))
        .not_valid_after(datetime(2049, 12, 31, tzinfo=timezone.utc))
        .add_extension(x509.BasicConstraints(ca=True, path_length=1), critical=True)
        .add_extension(
            x509.KeyUsage(False, False, False, False, False, True, True, None, None),
            critical=True,
        )
        .add_extension(
            x509.SubjectKeyIdentifier.from_public_key(key.public_key()), critical=False
        )
        .add_extension(
            x509.AuthorityKeyIdentifier.from_issuer_public_key(key.public_key()),
            critical=False,
        )
    )
    write_certificate(filename, builder, key)
    return key, subject


def main():
    server_key = serialization.load_pem_private_key(
        (DIRECTORY / "server.key").read_bytes(), password=None
    )
    root_key, root_name = ca("ca.pem", "CrispCloud Test Root", 1000)
    other_key, _ = ca("other-ca.pem", "CrispCloud Other Test Root", 2000)

    # Apple enforces leaf lifetime limits in addition to current validity.
    # A one-year lifetime is below its 825-day general TLS limit. These tests
    # use an explicitly imported private trust anchor.
    today = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    start = today - timedelta(days=1)
    end = start + timedelta(days=365)
    for filename, serial, wrong_host, expired, forged in (
        ("server.pem", 1001, False, False, False),
        ("wrong-host.pem", 1002, True, False, False),
        ("expired.pem", 1003, False, True, False),
        ("forged-issuer.pem", 1004, False, False, True),
    ):
        host = "wrong.invalid" if wrong_host else "localhost"
        alternatives = [x509.DNSName(host)]
        if not wrong_host:
            alternatives.append(x509.IPAddress(ip_address("127.0.0.1")))
        builder = (
            x509.CertificateBuilder()
            .subject_name(name(host))
            .issuer_name(root_name)
            .public_key(server_key.public_key())
            .serial_number(serial)
            .not_valid_before(
                datetime(2020, 1, 1, tzinfo=timezone.utc) if expired else start
            )
            .not_valid_after(
                datetime(2021, 1, 1, tzinfo=timezone.utc) if expired else end
            )
            .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
            .add_extension(x509.SubjectAlternativeName(alternatives), critical=False)
            .add_extension(
                x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]), critical=False
            )
            .add_extension(
                x509.KeyUsage(True, False, True, False, False, False, False, None, None),
                critical=True,
            )
            .add_extension(
                x509.SubjectKeyIdentifier.from_public_key(server_key.public_key()),
                critical=False,
            )
            .add_extension(
                x509.AuthorityKeyIdentifier.from_issuer_public_key(root_key.public_key()),
                critical=False,
            )
        )
        # Keep the forged issuer and authority identifier identical to the
        # real root. Only cryptographic signature verification can reject it.
        write_certificate(filename, builder, other_key if forged else root_key)
    print(f"Renewed public TLS fixtures; valid leaves expire {end.date().isoformat()}")


if __name__ == "__main__":
    main()
