ARG PHP_VERSION=8.5

FROM ghcr.io/morningstar-sudo/baseless-glibc:latest AS baseless-runtime

FROM cgr.dev/chainguard/wolfi-base:latest AS rootfs

ARG PHP_VERSION
ARG PHP_FLAVOR=cli
ARG PHP_EXTENSIONS="bcmath ctype curl dom fileinfo iconv intl mbstring mysqlnd mysqli openssl pcntl pdo pdo_mysql pdo_pgsql phar posix simplexml sodium xml xmlreader xmlwriter zip"
ARG CACHE_BUST=local

COPY --from=baseless-runtime /lib/apk/db/installed /tmp/baseless-installed

# Build a complete package-managed root filesystem, then remove every executable
# except the selected PHP SAPI. The APK database and package SBOMs remain so
# vulnerability scanners can still report the contents honestly.
RUN set -eu; \
    test -n "$CACHE_BUST"; \
    case "$PHP_FLAVOR" in \
      cli) sapi_package=""; sapi_binary="php" ;; \
      fpm) sapi_package="php-${PHP_VERSION}-fpm"; sapi_binary="php-fpm" ;; \
      *) echo "unsupported PHP_FLAVOR: $PHP_FLAVOR" >&2; exit 1 ;; \
    esac; \
    extension_packages=""; \
    for extension in $PHP_EXTENSIONS; do \
      extension_packages="$extension_packages php-${PHP_VERSION}-${extension}"; \
    done; \
    mkdir -p /rootfs; \
    attempt=1; \
    until apk add \
        --root /rootfs \
        --initdb \
        --no-cache \
        --no-scripts \
        --repositories-file /etc/apk/repositories \
        --keys-dir /etc/apk/keys \
        ca-certificates-bundle \
        glibc-locale-posix \
        tzdata \
        "php-${PHP_VERSION}" \
        $sapi_package \
        $extension_packages; do \
      if [ "$attempt" -ge 3 ]; then exit 1; fi; \
      attempt=$((attempt + 1)); \
      sleep 5; \
    done; \
    if [ "$PHP_FLAVOR" = "fpm" ]; then \
      sed -i -e 's/^user = /;user = /' -e 's/^group = /;group = /' \
        /rootfs/etc/php/php-fpm.d/www.conf; \
    fi; \
    cp "/rootfs/usr/bin/$sapi_binary" "/tmp/$sapi_binary"; \
    rm -rf /rootfs/usr/bin; \
    mkdir -p /rootfs/usr/bin /rootfs/app /rootfs/tmp; \
    cp "/tmp/$sapi_binary" "/rootfs/usr/bin/$sapi_binary"; \
    ln -s "$sapi_binary" /rootfs/usr/bin/php-entrypoint; \
    chmod 1777 /rootfs/tmp; \
    test ! -e /rootfs/bin/sh; \
    test ! -e /rootfs/usr/bin/apk; \
    test -x /rootfs/usr/bin/php-entrypoint; \
    smoke_output="$(chroot /rootfs /usr/bin/php-entrypoint --version 2>&1)"; \
    printf '%s\n' "$smoke_output"; \
    ! printf '%s\n' "$smoke_output" | grep -q 'PHP Warning'

RUN set -eu; \
    { \
      printf '%s\n' wolfi-baselayout ca-certificates-bundle tzdata; \
      apk --root /rootfs info | \
        grep -E '^(glibc-[0-9]+(\.[0-9]+)*|ld-linux-[0-9]+(\.[0-9]+)*)$'; \
    } | sort -u > /tmp/baseless-replaced-packages; \
    while IFS= read -r package; do \
      apk --root /rootfs info -L "$package" | sed '1d' | \
        while IFS= read -r path; do \
          [ -n "$path" ] || continue; \
          if [ -f "/rootfs/$path" ] || [ -L "/rootfs/$path" ]; then \
            rm -f "/rootfs/$path"; \
          fi; \
        done; \
    done < /tmp/baseless-replaced-packages; \
    drop_regex="$(paste -sd'|' /tmp/baseless-replaced-packages)"; \
    awk -v RS='' -v ORS='\n\n' -v drop_regex="$drop_regex" ' \
      { \
        package = ""; \
        for (field = 1; field <= NF; field++) { \
          if ($field ~ /^P:/) { \
            package = substr($field, 3); \
            break; \
          } \
        } \
        if (package !~ ("^(" drop_regex ")$")) print; \
      } \
    ' /rootfs/usr/lib/apk/db/installed > /tmp/php-installed; \
    cat /tmp/baseless-installed /tmp/php-installed > /rootfs/usr/lib/apk/db/installed; \
    rm -f /rootfs/etc/apk/world; \
    test ! -e /rootfs/etc/os-release; \
    test ! -e /rootfs/usr/lib/libc.so.6

FROM baseless-runtime

ARG PHP_VERSION
ARG PHP_FLAVOR=cli

LABEL org.opencontainers.image.title="PHP distroless" \
      org.opencontainers.image.description="Minimal Baseless PHP ${PHP_VERSION} ${PHP_FLAVOR} runtime" \
      org.opencontainers.image.vendor="morningstar-sudo" \
      org.opencontainers.image.source="https://github.com/morningstar-sudo/php-distroless"

COPY --from=rootfs /rootfs/ /

ENV PATH=/usr/bin \
    LANG=C.UTF-8 \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

WORKDIR /app
USER 65532:65532
EXPOSE 9000
STOPSIGNAL SIGQUIT
ENTRYPOINT ["/usr/bin/php-entrypoint"]
