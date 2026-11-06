FROM postgres:17

# first start script to build the databse
COPY init.sql /docker-entrypoint-initdb.d/

EXPOSE 5432