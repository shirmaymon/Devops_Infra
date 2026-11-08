#Stage 1/2 - clone app repo from github using ubuntu 
FROM ubuntu:24.04 AS builder

ARG REPO_URL=https://github.com/shirmaymon/Devops_ProjectWeb.git
ARG REPO_REF=main

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      git ca-certificates

RUN git clone --depth 1 --branch ${REPO_REF} ${REPO_URL} /tmp/src \
 && mkdir -p /BACKEND \
 && cd /tmp/src \
 && cp --parents auth.py common.py /BACKEND/

#Stage 2/2 - run auth service on python (flask)
FROM python:3.12-slim

WORKDIR /calc/backend/auth

RUN pip install --no-cache-dir flask psycopg2-binary argon2-cffi

COPY --from=builder /BACKEND .

CMD [ "python", "./auth.py" ]

EXPOSE 5001