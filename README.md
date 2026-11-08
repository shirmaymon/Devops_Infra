# Devops_Infra

Infrastructure repo for the VM Calculator Dashboard (DevOps course final project).

- Application repo (code): https://github.com/shirmaymon/Devops_ProjectWeb
- This repo: Dockerfiles and Kubernetes configuration files.

## Current state

The app is split into a **frontend**, a **backend** (Flask API and auth service) and a **database**, each with its own image, Deployment and Service. An NGINX Ingress routes `/` to the frontend, `/api/auth` to the auth service and `/api` to the Flask API. The calculation itself still runs in the user's browser.

| Part | Image | Namespace | What it runs |
| --- | --- | --- | --- |
| Frontend | `shirmaymon/devops-front:v2` | `frontend` | Apache (`httpd:2.4`) serving the static pages. |
| Backend (Flask) | `shirmaymon/devops-backend:v4` | `backend` | `api.py` (Flask, port 5000): Save / Load routes for a logged-in user. Saved files are stored in PostgreSQL. |
| Auth service | `shirmaymon/devops-auth:v1` | `backend` | `auth.py` (Flask, port 5001): register, login, logout, who-am-I. Sessions are stored in PostgreSQL. |
| Database | `shirmaymon/devops-postgres-database:v3` | `database` | PostgreSQL 17 (port 5432). Tables are created from `init.sql` on the first start. |

The frontend, backend and auth Dockerfiles are multi-stage builds. Stage 1 (`ubuntu:24.04`) clones the app repo with git (`REPO_URL`, `REPO_REF` build args) and copies only the needed files. The final stage (`httpd:2.4` for the frontend, `python:3.12-slim` for the backend) contains only those files, without git.

The database image is `postgres:17` plus `init.sql`, copied to `/docker-entrypoint-initdb.d/`. The scripts in that folder run only on the first start, when the data directory is empty. On later starts PostgreSQL finds the existing data and skips initialization (verified on the cluster: data survived deleting the pod).

### Saved files

The backend saves each user's data in the table `saved_files`, as JSON (`JSONB`). The owner is the logged-in user (`user_id`). Every save gets its own ID, which is part of the filename (`<name>_<DD-MM-YYYY>_<HH-MM>_<id>.json`), and each user can keep up to 5 saves. When the limit is reached, the user must delete one (the oldest is offered) before saving a new one.

The Flask API and the auth service read the database settings from environment variables: `DB_HOST` (`vmcalc-db-service.database`), `DB_NAME`, `DB_USER` and `DB_PASSWORD` (from the Secret `db-secret`).

### Login

Local accounts (email + password, hashed with Argon2id) are handled by the auth service. After login the browser holds a random session ID in an `HttpOnly`, `SameSite=Strict` cookie. The session record is in the table `sessions` of PostgreSQL, so every pod of both services can check it and logout works at once. Requests that change data also send a CSRF token. Settings of both services (environment variables): `COOKIE_SECURE` (`false` while the site runs over HTTP, `true` once HTTPS is on), `SESSION_IDLE_MINUTES` (30) and `SESSION_ABSOLUTE_HOURS` (8). Not built yet: Sign in with Google.

The old single-container (monolith) image is still on Docker Hub as `shirmaymon/devopsweb:v1`. Its Dockerfile and manifests are no longer in this repo; they are in the git history.

## Repo structure

| Path | What it is |
| --- | --- |
| `namespaces.yml` | The namespaces: `frontend`, `backend`, `database`, `monitoring`, `jenkins`. |
| `Frontend/Dockerfile` | Multi-stage build of the Apache frontend image (the pages, `login.html` and the scripts). |
| `Frontend/apache-deployment.yml` | Deployment `vmcalc-apache-deployment` (namespace `frontend`). |
| `Frontend/apache-service.yml` | Service `vmcalc-apache-service` (ClusterIP, port 80). |
| `Frontend/frontend-ingress.yml` | Ingress for the frontend: `/` to `vmcalc-apache-service:80`. |
| `Frontend/apache-hpa.yml` | HorizontalPodAutoscaler for Apache (1 to 3 replicas, CPU 70%, memory 80%). Not applied yet. |
| `Backend/Flask/Dockerfile` | Multi-stage build of the Flask backend image (installs Flask and psycopg2; copies `api.py` and `common.py`). |
| `Backend/Flask/flask-deployment.yml` | Deployment `vmcalc-flask-deployment` (namespace `backend`), database settings from environment variables, no volume. |
| `Backend/Flask/flask-service.yml` | Service `vmcalc-flask-service` (ClusterIP, port 5000). |
| `Backend/Flask/backend-ingress.yml` | Ingress for the backend: `/api/auth` to `vmcalc-auth-service:5001`, and `/api` to `vmcalc-flask-service:5000`. |
| `Backend/Flask/secret.yml` | Template of the Secret `db-secret` in the `backend` namespace (password is `CHANGE_ME`). Never commit the real password. |
| `Backend/Flask/flask-hpa.yml` | HorizontalPodAutoscaler for Flask (1 to 3 replicas, CPU 70%, memory 80%). Not applied yet. |
| `Backend/Auth/Dockerfile` | Multi-stage build of the auth service image (installs Flask, psycopg2 and argon2-cffi; copies `auth.py` and `common.py`). |
| `Backend/Auth/auth-deployment.yml` | Deployment `vmcalc-auth-deployment` (namespace `backend`), database settings and cookie settings from environment variables. |
| `Backend/Auth/auth-service.yml` | Service `vmcalc-auth-service` (ClusterIP, port 5001). |
| `Backend/DataBase/Dockerfile` | `postgres:17` plus `init.sql`. |
| `Backend/DataBase/init.sql` | Schema: `users`, `saved_files`, `sessions`, `cloud_prices`. Runs once, on the first start. |
| `Backend/DataBase/database-deployment.yml` | Deployment `vmcalc-postgres-deployment` (namespace `database`), strategy `Recreate`, 1 replica, data at `/var/lib/postgresql/data`. |
| `Backend/DataBase/database-service.yml` | Service `vmcalc-db-service` (ClusterIP, port 5432). |
| `Backend/DataBase/database-pvc.yml` | PersistentVolumeClaim `vmcalc-postgres-pvc` (1Gi, StorageClass `csi-hostpath-sc`). |
| `Backend/DataBase/database-vpa.yml` | VerticalPodAutoscaler for Postgres (`InPlaceOrRecreate`, 100m/256Mi up to 1 CPU/1Gi). Not applied yet; VPA must be installed separately. |
| `Backend/DataBase/secret.yml` | Template of the Secret `db-secret` in the `database` namespace (password is `CHANGE_ME`). Never commit the real password. |
| `DEPRECATED/` | Files that are no longer used: the single test Pods (apache, flask, database, auth) and the old Flask PVC. Do not apply them. |

## Important: volumes

The database keeps its data under `/var/lib/postgresql/data`, on a PersistentVolumeClaim. **The data survives when the pod is deleted, restarted or recreated**: the new pod mounts the same volume and finds the data in place.

The backend and the auth service have no volume: the saved files and the sessions are stored in the database, so their pods keep no data.

The database Deployment uses `strategy: type: Recreate`: the old pod stops before the new one starts, so two PostgreSQL servers never use the same data directory.

## The database password

PostgreSQL reads `POSTGRES_PASSWORD` only on the first start, when the data directory is empty. Changing the Secret later does not change the password inside an existing database.

A pod can only use a Secret from its own namespace, so the password is kept in two Secrets with the same name and password (the auth service runs in `backend` and uses the same copy as Flask): `Backend/DataBase/secret.yml` (namespace `database`) and `Backend/Flask/secret.yml` (namespace `backend`). Set the password in both (replace `CHANGE_ME`) and apply them. Do not commit the real password to git.

## Changing the database schema

`init.sql` runs only on an empty data directory. To apply a changed `init.sql`: build and push a new database image tag, set it in `database-deployment.yml`, delete the Deployment and the PVC (`kubectl delete deployment vmcalc-postgres-deployment -n database`, then `kubectl delete pvc vmcalc-postgres-pvc -n database`), and apply the PVC, Deployment and Service again. This deletes all stored data.

## Run it on Minikube

PowerShell:

```
minikube start --nodes=3 --driver=docker --cpus=2 --memory=2048
minikube addons enable csi-hostpath-driver; minikube addons enable ingress; minikube addons enable metrics-server
kubectl apply -f namespaces.yml -f Backend/DataBase/secret.yml -f Backend/Flask/secret.yml -f Backend/DataBase/database-pvc.yml
Get-ChildItem -Path Backend,Frontend -Recurse -Include *-deployment.yml,*-service.yml,*-ingress.yml | ForEach-Object { kubectl apply -f $_.FullName }
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8080:80
```

Then open http://localhost:8080.

If the ingress controller pod stays Pending, remove the control-plane taint: `kubectl taint nodes minikube node-role.kubernetes.io/control-plane:NoSchedule-`

See the saved files in the database:

```
kubectl exec -it deployment/vmcalc-postgres-deployment -n database -- psql -U vmcalc -d vmcalc -c "SELECT id, first_name, last_name, filename, created_at FROM saved_files ORDER BY created_at;"
```

## Scaling

- **Apache and Flask:** `apache-hpa.yml` and `flask-hpa.yml` need the Metrics Server (enabled in the run block above) and CPU / memory requests on the containers. The backend keeps no data in the pod, so it can run more than one replica.
- **Postgres:** `database-vpa.yml` resizes the single pod (vertical scaling). The Vertical Pod Autoscaler is not built in and must be installed separately (see the kubernetes/autoscaler repository).

## Test the login

Open http://localhost:8080 and check: Save without a login goes to the login page; after creating an account, Save, Load, Delete and Log out work. If the old page behaviour appears after a frontend update, hard-refresh the browser (Ctrl+Shift+R): it may be using a cached `saveload.js`.

## Planned

In this order: Argo CD and Jenkins (CI/CD), a change in the app to verify the pipeline, Prometheus and Grafana, a health check of the whole app. If there is time: move to AWS with HTTPS (`COOKIE_SECURE=true`), then Google sign-in. Also listed: Helm, Terraform and logging.