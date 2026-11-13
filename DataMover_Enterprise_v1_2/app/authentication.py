"""Authentication primitives shared by the DataMover sign-in flows."""
import base64
import hashlib
import hmac
import secrets
import ssl
from urllib.parse import urlsplit


_SCRYPT_N = 1 << 14
_SCRYPT_R = 8
_SCRYPT_P = 1
_SCRYPT_LENGTH = 64


class InvalidCredentials(Exception):
    pass


class DirectoryUnavailable(Exception):
    pass


def hash_password(password: str) -> str:
    if not isinstance(password, str) or len(password) < 12 or len(password) > 1024:
        raise ValueError('Password must contain 12–1024 characters')
    salt = secrets.token_bytes(16)
    digest = hashlib.scrypt(
        password.encode('utf-8'),
        salt=salt,
        n=_SCRYPT_N,
        r=_SCRYPT_R,
        p=_SCRYPT_P,
        dklen=_SCRYPT_LENGTH,
    )
    return 'scrypt${}${}${}${}${}'.format(
        _SCRYPT_N,
        _SCRYPT_R,
        _SCRYPT_P,
        base64.urlsafe_b64encode(salt).decode('ascii'),
        base64.urlsafe_b64encode(digest).decode('ascii'),
    )


def verify_password(password: str, encoded: str) -> bool:
    try:
        scheme, n, r, p, salt_text, digest_text = encoded.split('$')
        if scheme != 'scrypt':
            return False
        n, r, p = int(n), int(r), int(p)
        if n != _SCRYPT_N or r != _SCRYPT_R or p != _SCRYPT_P:
            return False
        salt = base64.urlsafe_b64decode(salt_text.encode('ascii'))
        expected = base64.urlsafe_b64decode(digest_text.encode('ascii'))
        actual = hashlib.scrypt(
            password.encode('utf-8'),
            salt=salt,
            n=n,
            r=r,
            p=p,
            dklen=len(expected),
        )
        return hmac.compare_digest(actual, expected)
    except (AttributeError, ValueError, TypeError, UnicodeError):
        return False


def authenticate_ad(username: str, password: str, ldap_url: str, ca_cert: str | None = None,
                    search_base: str | None = None, timeout: int = 5) -> set[str]:
    parsed = urlsplit(ldap_url)
    if parsed.scheme.casefold() != 'ldap' or not parsed.hostname or parsed.path not in ('', '/'):
        raise DirectoryUnavailable('AD must be configured with an ldap:// URL for StartTLS')

    try:
        from ldap3 import AUTO_BIND_TLS_BEFORE_BIND, NONE, SIMPLE, SUBTREE, Connection, Server, Tls
        from ldap3.core.exceptions import LDAPBindError, LDAPException
        from ldap3.utils.conv import escape_filter_chars
    except ImportError as exc:
        raise DirectoryUnavailable('The LDAP authentication dependency is unavailable') from exc

    connection = None
    try:
        tls = Tls(validate=ssl.CERT_REQUIRED, ca_certs_file=ca_cert)
        server = Server(
            parsed.hostname,
            port=parsed.port or 389,
            use_ssl=False,
            tls=tls,
            get_info=NONE,
            connect_timeout=timeout,
        )
        connection = Connection(
            server,
            user=username,
            password=password,
            authentication=SIMPLE,
            auto_bind=AUTO_BIND_TLS_BEFORE_BIND,
            receive_timeout=timeout,
            auto_referrals=False,
            raise_exceptions=True,
        )
        if not search_base:
            raise DirectoryUnavailable('Active Directory search base is not configured')
        search_filter = (
            '(&(objectCategory=person)(objectClass=user)'
            f'(userPrincipalName={escape_filter_chars(username)}))'
        )
        if not connection.search(search_base, search_filter, search_scope=SUBTREE,
                                 attributes=['memberOf']) or not connection.entries:
            raise DirectoryUnavailable('Authenticated account was not found in the configured search base')
        groups = connection.entries[0].entry_attributes_as_dict.get('memberOf', [])
        return {str(group).strip().casefold() for group in groups}
    except LDAPBindError as exc:
        raise InvalidCredentials('Invalid Active Directory credentials') from exc
    except LDAPException as exc:
        raise DirectoryUnavailable('Active Directory sign-in is unavailable') from exc
    finally:
        if connection is not None:
            connection.unbind()
