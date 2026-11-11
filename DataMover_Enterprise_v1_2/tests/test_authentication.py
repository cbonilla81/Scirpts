import pytest

from app.authentication import (
    DirectoryUnavailable,
    hash_password,
    authenticate_ad,
    verify_password,
)


def test_password_hashes_are_salted_and_verify():
    first = hash_password('correct horse battery staple')
    second = hash_password('correct horse battery staple')

    assert first != second
    assert verify_password('correct horse battery staple', first)
    assert not verify_password('incorrect password', first)


def test_password_verification_rejects_malformed_hash():
    assert not verify_password('correct horse battery staple', 'not-a-hash')


@pytest.mark.parametrize('url', ['ldaps://dc.example.com', 'http://dc.example.com', 'ldap://'])
def test_active_directory_requires_ldap_starttls_url(url):
    with pytest.raises(DirectoryUnavailable):
        authenticate_ad('operator@example.com', 'password', url)
