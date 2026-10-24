# PHP Distroless Images

Minimal, non-root PHP CLI and PHP-FPM images with no shell or package manager.
Supported PHP branches are assembled from current Wolfi packages and gated by
Trivy.

## Image matrix

| PHP | Status on 24 October 2026 | CLI image | FPM image |
|---|---|---|---|
| 8.5 | Active support | `ghcr.io/morningstar-sudo/php-distroless-8.5-cli:latest` | `ghcr.io/morningstar-sudo/php-distroless-8.5-fpm:latest` |
| 8.4 | Active support | `ghcr.io/morningstar-sudo/php-distroless-8.4-cli:latest` | `ghcr.io/morningstar-sudo/php-distroless-8.4-fpm:latest` |
| 8.3 | Security fixes | `ghcr.io/morningstar-sudo/php-distroless-8.3-cli:latest` | `ghcr.io/morningstar-sudo/php-distroless-8.3-fpm:latest` |
| 8.2 | Security fixes until 31 December 2026 | `ghcr.io/morningstar-sudo/php-distroless-8.2-cli:latest` | `ghcr.io/morningstar-sudo/php-distroless-8.2-fpm:latest` |

PHP does not designate releases as LTS. The supported matrix follows the
[upstream support calendar](https://www.php.net/supported-versions.php).

## CLI versus FPM

- Use `cli` for commands, Composer output, cron jobs, queue workers and
  migrations. Its entrypoint is `php`.
- Use `fpm` behind an HTTP server such as Nginx. It stays in the foreground and
  accepts FastCGI traffic on port 9000. It is not an HTTP server by itself.

## Application examples

CLI command or worker:

```dockerfile
FROM composer:2 AS dependencies
WORKDIR /app
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader

FROM ghcr.io/morningstar-sudo/php-distroless-8.5-cli:latest
COPY --from=dependencies --chown=65532:65532 /app /app
COPY --chown=65532:65532 . /app
ENTRYPOINT ["php"]
CMD ["artisan", "queue:work", "--no-interaction"]
```

PHP-FPM application:

```dockerfile
FROM composer:2 AS dependencies
WORKDIR /app
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader

FROM ghcr.io/morningstar-sudo/php-distroless-8.5-fpm:latest
COPY --from=dependencies --chown=65532:65532 /app /app
COPY --chown=65532:65532 . /app
```

Run FPM with a read-only root filesystem and a writable temporary filesystem:

```bash
docker run --rm --read-only --tmpfs /tmp:rw,noexec,nosuid,size=64m \
  -p 9000:9000 ghcr.io/morningstar-sudo/php-distroless-8.5-fpm:latest
```

## Included extensions

The supported images include a practical web baseline:

`bcmath`, `ctype`, `curl`, `dom`, `fileinfo`, `iconv`, `intl`, `mbstring`,
`mysqlnd`, `mysqli`, `openssl`, `pcntl`, `PDO`, `pdo_mysql`, `pdo_pgsql`,
`Phar`, `posix`, `SimpleXML`, `sodium`, `xml`, `xmlreader`, `xmlwriter`, and
`zip`, plus extensions compiled into the Wolfi PHP package such as OPcache,
JSON, session and SQLite.

Override `PHP_EXTENSIONS` when building if a smaller or different extension set
is required:

```bash
docker build \
  --build-arg PHP_VERSION=8.5 \
  --build-arg PHP_FLAVOR=cli \
  --build-arg 'PHP_EXTENSIONS=curl mbstring openssl pdo pdo_mysql' \
  -t php-distroless:8.5-cli .
```

## Security model

Supported images:

- are built from package-managed Wolfi components;
- retain APK inventory/SBOM metadata so scanners can identify packages;
- remove `sh`, BusyBox and `apk` from the final filesystem;
- run as UID/GID `65532:65532`;
- are compatible with a read-only root filesystem; and
- pass the `abxst/actions/strict@v3` Trivy gate across all severities before
  publication.

The absence of a shell is defense in depth, not a fix for arbitrary PHP code
execution. Compromised PHP code can still read application-accessible files,
make network connections and access environment variables. Continue to patch
PHP and the application, restrict secrets and egress, drop Linux capabilities,
and use seccomp/AppArmor where available.

## Local builds

```bash
# Supported Wolfi image
docker build --build-arg PHP_VERSION=8.5 --build-arg PHP_FLAVOR=cli \
  -t php-distroless:8.5-cli .
```

Verify that the runtime has no shell:

```bash
docker run --rm --entrypoint /bin/sh php-distroless:8.5-cli
# exec /bin/sh: no such file or directory
```

## CI

`.github/workflows/build.yml` uses `abxst/actions/strict@v3` for all matrix
entries and builds `linux/amd64` and `linux/arm64`. Releases publish immutable
SHA/date tags plus `latest` only after the full strict gate passes.
