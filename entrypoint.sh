#!/bin/sh

set -eu

umask 077

if [ -z "${LDAP_URI:-}" ]; then
    LDAP_URI="ldaps://ldap$(echo "$LDAP_BASEDN" | sed -e 's/,\?[[:alpha:]]\+=/\./g')"
fi

ipsilon-server-install \
    --root-instance \
    --hostname="id.foo.sh" \
    --ldap=yes \
    --ldap-server-url="${LDAP_URI}" \
    --ldap-tls-level=Demand \
    --ldap-bind-dn-template="uid=%(username)s,ou=People,${LDAP_BASEDN}" \
    --ldap-base-dn="${LDAP_BASEDN}"

# disable ssl redirection as we run behind proxy
sed -i -e 's/^\([[:space:]]]*\)\(Rewrite.*\)$/\1#\2/' /etc/httpd/conf.d/ipsilon-root.conf

unset LDAP_BASEDN LDAP_URI

exec "$@"
