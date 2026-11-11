#Stage 1/2 - clone app repo from github using ubuntu 
FROM ubuntu:24.04 AS builder

ARG REPO_URL=https://github.com/shirmaymon/Devops_ProjectWeb.git
ARG REPO_REF=main

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      git ca-certificates

RUN git clone --depth 1 --branch ${REPO_REF} ${REPO_URL} /tmp/src \
 && mkdir -p /FRONTEND \
 && cd /tmp/src \
 && cp --parents index.html login.html servers.html users.html machines.html calculator.html showdelete.html css/style.css js/app.js js/auth.js js/data.js js/saveload.js /FRONTEND/

#Stage 2/2 - run frontend on apache2
FROM httpd:2.4

COPY --from=builder /FRONTEND /usr/local/apache2/htdocs/

EXPOSE 80