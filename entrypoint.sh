#!/bin/sh

set -eu

umask 077

if [ -z "${LDAP_URI:-}" ]; then
    LDAP_URI="ldaps://ldap$(echo "$LDAP_BASEDN" | sed -e 's/,\?[[:alpha:]]\+=/\./g')"
fi

[ "${IPSILON_DB_USER:-}" = "" ] && IPSILON_DB_USER="ipsilon"
[ "${IPSILON_DB_CA:-}" = "" ] && IPSILON_DB_CA="/etc/ssl/certs/ca-bundle.crt"

ipsilon-server-install \
    --root-instance \
    --hostname="idp.foo.sh" \
    --ldap=yes \
    --ldap-server-url="${LDAP_URI}" \
    --ldap-tls-level=Demand \
    --ldap-bind-dn-template="uid=%(username)s,ou=People,${LDAP_BASEDN}" \
    --ldap-base-dn="${LDAP_BASEDN}" \
    --info-ldap=yes \
    --info-ldap-server-url="${LDAP_URI}" \
    --info-ldap-user-dn-template="uid=%(username)s,ou=People,${LDAP_BASEDN}" \
    --users-dburi="mysql://${IPSILON_DB_USER}:${IPSILON_DB_PASS}@${IPSILON_DB_HOST}/${IPSILON_DB_USERPREFS}?ssl=true&ssl_ca=${IPSILON_DB_CA}" \
    --transaction-dburi="mysql://${IPSILON_DB_USER}:${IPSILON_DB_PASS}@${IPSILON_DB_HOST}/${IPSILON_DB_TRANSACTIONS}?ssl=true&ssl_ca=${IPSILON_DB_CA}" \
    --samlsessions-dburi="mysql://${IPSILON_DB_USER}:${IPSILON_DB_PASS}@${IPSILON_DB_HOST}/${IPSILON_DB_SESSIONS}?ssl=true&ssl_ca=${IPSILON_DB_CA}"

# enable proxy support manually
{
    echo ""
    echo "tools.proxy.on = True"
} >> /etc/ipsilon/root/ipsilon.conf

# disable ssl redirection as we run behind proxy
sed -i -e 's/^\([[:space:]]*\)\(Rewrite.*\)$/\1#\2/' /etc/httpd/conf.d/ipsilon-root.conf

unset LDAP_BASEDN LDAP_URI
unset IPSILON_DB_USER IPSILON_DB_PASS IPSILON_DB_HOST IPSILON_DB_USERS IPSILON_DB_TRANSACTIONS IPSILON_DB_SESSIONS

exec "$@"
