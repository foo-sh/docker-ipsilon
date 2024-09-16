FROM rockylinux:9

RUN set -eux ; \
    dnf -y upgrade ; \
    dnf -y install --nodocs --setopt=install_weak_deps=False epel-release ; \
    dnf -y install --nodocs --setopt=install_weak_deps=False \
        ipsilon \
        ipsilon-authgssapi \
        ipsilon-authldap \
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
