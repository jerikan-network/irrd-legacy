FROM debian:10 AS builder
RUN apt-get -qqy update \
    && apt-get install -qqy --no-install-recommends \
        autoconf \
        automake \
        byacc \
        flex \
        gcc \
        git \
        gnupg \
        libglib2.0-dev \
        make \
    && rm -rf /var/cache/apt
COPY src/ /app/src/
RUN cd /app/src \
    && sed -i "s/git describe/echo 0.0 ||/" configure.ac \
    && mkdir m4 && autoreconf -fi \
    && ./configure --prefix=/app/irrd \
    && make \
    && make install

FROM debian:10 AS fetcher
RUN apt-get -qqy update \
    && apt-get install -qqy --no-install-recommends \
        ca-certificates \
        curl \
        gzip \
        python3 \
    && rm -rf /var/cache/apt
WORKDIR /databases
COPY irr-prune /usr/bin/irr-prune
RUN ln -sf /bin/bash /bin/sh

# Cache busting. Use `--build-arg TODAY=$(date +%F)` to bust cache daily.
ARG TODAY=2020-01-01

# We use this list: <https://www.gin.ntt.net/support-center/policies-procedures/routing-registry/>

# NTTCOM
RUN set -o pipefail && curl -fsS ftp://rr1.ntt.net/nttcomRR/nttcom.db.gz | gunzip -c | irr-prune > /databases/nttcom.db
# RADB
RUN set -o pipefail && curl -fsS ftp://ftp.radb.net/radb/dbase/radb.db.gz | gunzip -c | irr-prune > /databases/radb.db
# RIPE
RUN set -eo pipefail && (for db in as-set aut-num route-set route route6; do \
        curl -fsS https://ftp.ripe.net/ripe/dbase/split/ripe.db.$db.gz | gunzip -c; \
        echo; \
    done) | irr-prune > /databases/ripe.db
# RIPE-NONAUTH
RUN set -o pipefail && curl -fsS https://ftp.ripe.net/ripe/dbase/ripe-nonauth.db.gz | gunzip -c | irr-prune > /databases/ripe-nonauth.db
# ALTDB
RUN set -o pipefail && curl -fsS ftp://ftp.altdb.net/pub/altdb/altdb.db.gz | gunzip -c | irr-prune > /databases/altdb.db
# BELL
RUN set -o pipefail && curl -fsS ftp://ftp.radb.net/radb/dbase/bell.db.gz | gunzip -c | irr-prune > /databases/bell.db
# LEVEL3
RUN set -o pipefail && curl -fsS ftp://rr.Level3.net/pub/rr/level3.db.gz | gunzip -c | irr-prune > /databases/level3.db
# RGNET
RUN set -o pipefail && curl -fsS ftp://rg.net/rgnet/RGNET.db.gz | gunzip -c | irr-prune > /databases/rgnet.db
# APNIC
RUN set -eo pipefail && (for db in as-set aut-num route-set route route6; do \
        curl -fsS https://ftp.apnic.net/apnic/whois/apnic.db.$db.gz | gunzip -c; \
        echo; \
    done) | irr-prune > /databases/apnic.db
# JPIRR
RUN set -o pipefail && curl -fsS ftp://ftp.radb.net/radb/dbase/jpirr.db.gz | gunzip -c | irr-prune > /databases/jpirr.db
# ARIN
RUN set -o pipefail && curl -fsS https://ftp.arin.net/pub/rr/arin.db.gz | gunzip -c | irr-prune > /databases/arin.db
# ARIN-NONAUTH
RUN set -o pipefail && curl -fsS https://ftp.arin.net/pub/rr/arin-nonauth.db.gz | gunzip -c | irr-prune > /databases/arin-nonauth.db
# BBOI
RUN set -o pipefail && curl -fsS ftp://ftp.radb.net/radb/dbase/bboi.db.gz | irr-prune > /databases/bboi.db
# TC
RUN set -o pipefail && curl -fsS ftp://ftp.bgp.net.br/dbase/tc.db.gz | irr-prune > /databases/tc.db
# AFRINIC
RUN set -o pipefail && curl -fsS https://ftp.afrinic.net/pub/dbase/afrinic.db.gz | gunzip -c | irr-prune > /databases/afrinic.db
# ARIN-WHOIS
# ???
# RPKI
# ???
# REGISTROBR
# ???


# APNIC




RUN cd /databases; for h in $(ls -rt *.db); do \
        echo "irr_database ${h%.db}" >> irrd.conf; \
    done

FROM debian:10
RUN apt-get -qqy update \
    && apt-get install -qqy --no-install-recommends \
        libglib2.0-0
RUN groupadd -r irrd && useradd --no-log-init -r -g irrd irrd
COPY --from=builder /app/irrd/ /app/irrd/
COPY --from=fetcher /databases /app/databases/
EXPOSE 5674
EXPOSE 43
STOPSIGNAL SIGINT
ENTRYPOINT ["/app/irrd/sbin/irrd", "-n", "-g", "irrd", "-l", "irrd", "-d", "/app/databases", "-f", "/app/databases/irrd.conf"]
