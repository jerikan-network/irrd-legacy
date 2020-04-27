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

# Cache busting. Use `--build-arg TODAY=$(date +%F)` to bust cache daily.
ARG TODAY=2020-01-01

# Sources: <http://www.irr.net/docs/list.html>
#
# Tools like bgpq3 are using RADB server by default. So, as per the
# URL, we should mirror AFRINIC, ALTDB, AOLTW, APNIC, ARIN, BELL,
# BBOI, CANARIE, EASYNET, EPOCH, HOST, JPIRR, LEVEL3, NESTEGG, NTTCOM,
# OPENFACE, OTTIX, PANIX, REACH, RGNET, RIPE, RISQ, ROGERS, TC.
#
# This is a lot, we limit ourselves to a few DB:
# - AFRINIC
# - APNIC
# - ARIN
# - RADB
# - RIPE

# AFRINIC
RUN curl -fsS https://ftp.afrinic.net/pub/dbase/afrinic.db.gz | gunzip -c | irr-prune > /databases/afrinic.db

# APNIC
RUN set -e; (for db in as-set aut-num route-set route route6; do \
        curl -fsS https://ftp.apnic.net/apnic/whois/apnic.db.$db.gz | gunzip -c; \
        echo; \
    done) | irr-prune > /databases/apnic.db

# ARIN
RUN curl -fsS https://ftp.arin.net/pub/rr/arin.db | irr-prune > /databases/arin.db

# RADB
RUN curl -fsS ftp://ftp.radb.net/radb/dbase/radb.db.gz | gunzip -c | irr-prune > /databases/radb.db

# RIPE
RUN set -e; (for db in as-set aut-num route-set route route6; do \
        curl -fsS https://ftp.ripe.net/ripe/dbase/split/ripe.db.$db.gz | gunzip -c; \
        echo; \
    done) | irr-prune > /databases/ripe.db

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
