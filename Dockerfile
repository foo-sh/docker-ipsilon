FROM fedora:41

RUN set -eux ; \
    groupadd -g 900 -r ipsilon ; \
    useradd -r -g ipsilon -d /var/lib/ipsilon -s /sbin/nologin \
        -c "Ipsilon Server" -u 900 ipsilon

RUN set -eux ; \
    dnf -y upgrade ; \
    dnf -y install --nodocs --setopt=install_weak_deps=False \
        ipsilon \
        ipsilon-authgssapi \
        ipsilon-authldap \
        ipsilon-openidc \
        python3-mysqlclient \
    ; \
    dnf -y clean all ; \
    rm -rf /var/cache/dnf

RUN set -eux ; \
    for f in autoindex.conf ssl.conf userdir.conf welcome.conf ; do \
        mv "/etc/httpd/conf.d/${f}" "/etc/httpd/conf.d/${f}.disabled" ; \
    done

COPY --chmod=0755 entrypoint.sh /

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/sbin/httpd", "-DFOREGROUND"]
