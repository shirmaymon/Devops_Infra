FROM ubuntu:24.04

ARG REPO_URL=https://github.com/shirmaymon/Devops_ProjectWeb.git
ARG REPO_REF=main

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      apache2 python3 python3-pip git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir --break-system-packages flask flask-cors

RUN a2enmod proxy proxy_http

# Get the app repo, then split it: static files -> web root, api.py -> /app, vmcalc.conf -> Apache
RUN git clone --depth 1 --branch ${REPO_REF} ${REPO_URL} /tmp/src \
 && mkdir -p /var/www/html/vm-calculator /app /web-data \
 && cp -r /tmp/src/. /var/www/html/vm-calculator/ \
 && mv /var/www/html/vm-calculator/api.py /app/api.py \
 && mv /var/www/html/vm-calculator/vmcalc.conf /etc/apache2/sites-available/vmcalc.conf \
 && rm -rf /var/www/html/vm-calculator/.git /var/www/html/vm-calculator/README.md /tmp/src \
 && a2dissite 000-default.conf \
 && a2ensite vmcalc.conf

EXPOSE 80

# Flask (api.py, port 5000) in the background, Apache in the foreground as PID 1
CMD ["bash", "-c", "python3 /app/api.py & exec apachectl -D FOREGROUND"]