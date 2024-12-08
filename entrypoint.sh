#!/bin/sh

set -eu

umask 077

if [ -z "${LDAP_URI:-}" ]; then
    LDAP_URI="ldaps://ldap$(echo "$LDAP_BASEDN" | sed -e 's/,\?[[:alpha:]]\+=/\./g')"
fi

[ "${IPSILON_DB_USER:-}" = "" ] && IPSILON_DB_USER="ipsilon"
[ "${IPSILON_DB_CA:-}" = "" ] && IPSILON_DB_CA="/etc/ssl/certs/ca-bundle.crt"
[ "${IPSILON_DB_USERPREFS:-}" = "" ] && IPSILON_DB_USERPREFS="ipsilon"
[ "${IPSILON_DB_TRANSACTIONS:-}" = "" ] && IPSILON_DB_TRANSACTIONS="ipsilon"
[ "${IPSILON_DB_SESSIONS:-}" = "" ] && IPSILON_DB_SESSIONS="ipsilon"
[ "${IPSILON_DB_OPENID:-}" = "" ] && IPSILON_DB_OPENID="ipsilon"

install -m 0640 --owner root --group ipsilon "$IPSILON_DB_KEY" "/etc/ssl/private/ipsilon.key"

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
    --users-dburi="mysql://${IPSILON_DB_USER}:${IPSILON_DB_PASS}@${IPSILON_DB_HOST}/${IPSILON_DB_USERPREFS}?ssl=true&ssl_ca=${IPSILON_DB_CA}&ssl_key=/etc/ssl/private/ipsilon.key&ssl_cert=${IPSILON_DB_CERT}" \
    --transaction-dburi="mysql://${IPSILON_DB_USER}:${IPSILON_DB_PASS}@${IPSILON_DB_HOST}/${IPSILON_DB_TRANSACTIONS}?ssl=true&ssl_ca=${IPSILON_DB_CA}&ssl_key=/etc/ssl/private/ipsilon.key&ssl_cert=${IPSILON_DB_CERT}" \
    --openid=yes \
    --openid-dburi="mysql://${IPSILON_DB_USER}:${IPSILON_DB_PASS}@${IPSILON_DB_HOST}/${IPSILON_DB_OPENID}?ssl=true&ssl_ca=${IPSILON_DB_CA}&ssl_key=/etc/ssl/private/ipsilon.key&ssl_cert=${IPSILON_DB_CERT}"

# enable proxy support manually
{
    echo ""
    echo "tools.proxy.on = True"
} >> /etc/ipsilon/root/ipsilon.conf

# disable ssl redirection as we run behind proxy
sed -i -e 's/^\([[:space:]]*\)\(Rewrite.*\)$/\1#\2/' /etc/httpd/conf.d/ipsilon-root.conf

# send apache logs to stdout/stderr
sed -i \
    -e 's|^\(\s*CustomLog\s\+\).\+\(\s\+.*\)$|\1/proc/self/fd/1\2|' \
    -e 's|^\(\s*ErrorLog\s\+\).*|\1/proc/self/fd/2|' \
    /etc/httpd/conf/httpd.conf

unset LDAP_BASEDN LDAP_URI
# shellcheck disable=SC2046
unset $(env | awk -F= '/^IPSILON_/ { print $1 }')

exec "$@"
