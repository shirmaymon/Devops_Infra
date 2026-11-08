# Devops_Infra

Infrastructure repo for the VM Calculator Dashboard (DevOps course final project).

- Application repo (code): https://github.com/shirmaymon/Devops_ProjectWeb
- This repo: Dockerfiles and Kubernetes configuration files.

## Current state

The app is split into a **frontend**, a **backend** and a **database**, each with its own image, Deployment and Service, in its own namespace. An NGINX Ingress routes `/` to the frontend and `/api` to the backend. The calculation itself still runs in the user's browser.

| Part | Image | Namespace | What it runs |
| --- | --- | --- | --- |
| Frontend | `shirmaymon/devops-front:v1` | `frontend` | Apache (`httpd:2.4`) serving the static pages. |
| Backend (Flask) | `shirmaymon/devops-backend:v3` | `backend` | `api.py` (Flask, port 5000): Save / Load routes. Saved files are stored in PostgreSQL. |
| Database | `shirmaymon/devops-postgres-database:v2` | `database` | PostgreSQL 17 (port 5432). Tables are created from `init.sql` on the first start. |

The frontend and backend Dockerfiles are multi-stage builds. Stage 1 (`ubuntu:24.04`) clones the app repo with git (`REPO_URL`, `REPO_REF` build args) and copies only the needed files. The final stage (`httpd:2.4` for the frontend, `python:3.12-slim` for the backend) contains only those files, without git.

The database image is `postgres:17` plus `init.sql`, copied to `/docker-entrypoint-initdb.d/`. The scripts in that folder run only on the first start, when the data directory is empty. On later starts PostgreSQL finds the existing data and skips initialization (verified on the cluster: data survived deleting the pod).

### Saved files

The backend saves each user's data in the table `saved_files`, as JSON (`JSONB`). The owner is identified by first and last name (stored in lowercase). Every save gets its own ID, which is part of the filename (`<first>_<last>_<DD-MM-YYYY>_<HH-MM>_<id>.json`), and each user can keep up to 5 saves. When the limit is reached, the user must delete one (the oldest is offered) before saving a new one.

The backend reads the database settings from environment variables: `DB_HOST` (`vmcalc-db-service.database`), `DB_NAME`, `DB_USER` and `DB_PASSWORD` (from the Secret `db-secret`).

Not built yet: the auth service.

The old single-container (monolith) image is still on Docker Hub as `shirmaymon/devopsweb:v1`. Its Dockerfile and manifests are no longer in this repo; they are in the git history.

## Repo structure

| Path | What it is |
| --- | --- |
| `namespaces.yml` | The namespaces: `frontend`, `backend`, `database`, `monitoring`, `jenkins`. |
| `Frontend/Dockerfile` | Multi-stage build of the Apache frontend image. |
| `Frontend/apache-deployment.yml` | Deployment `vmcalc-apache-deployment` (namespace `frontend`). |
| `Frontend/apache-service.yml` | Service `vmcalc-apache-service` (ClusterIP, port 80). |
| `Frontend/frontend-ingress.yml` | Ingress for the frontend: `/` to `vmcalc-apache-service:80`. |
| `Frontend/apache-hpa.yml` | HorizontalPodAutoscaler for Apache (1 to 3 replicas, CPU 70%, memory 80%). Not applied yet. |
| `Backend/Flask/Dockerfile` | Multi-stage build of the Flask backend image (installs Flask and psycopg2). |
| `Backend/Flask/flask-deployment.yml` | Deployment `vmcalc-flask-deployment` (namespace `backend`), database settings from environment variables, no volume. |
| `Backend/Flask/flask-service.yml` | Service `vmcalc-flask-service` (ClusterIP, port 5000). |
| `Backend/Flask/backend-ingress.yml` | Ingress for the backend: `/api` to `vmcalc-flask-service:5000`. |
| `Backend/Flask/secret.yml` | Template of the Secret `db-secret` in the `backend` namespace (password is `CHANGE_ME`). Never commit the real password. |
| `Backend/Flask/flask-hpa.yml` | HorizontalPodAutoscaler for Flask (1 to 3 replicas, CPU 70%, memory 80%). Not applied yet. |
| `Backend/DataBase/Dockerfile` | `postgres:17` plus `init.sql`. |
| `Backend/DataBase/init.sql` | Schema: `users`, `saved_files`, `cloud_prices`. Runs once, on the first start. |
| `Backend/DataBase/database-deployment.yml` | Deployment `vmcalc-postgres-deployment` (namespace `database`), strategy `Recreate`, 1 replica, data at `/var/lib/postgresql/data`. |
| `Backend/DataBase/database-service.yml` | Service `vmcalc-db-service` (ClusterIP, port 5432). |
| `Backend/DataBase/database-pvc.yml` | PersistentVolumeClaim `vmcalc-postgres-pvc` (1Gi, StorageClass `csi-hostpath-sc`). |
| `Backend/DataBase/database-vpa.yml` | VerticalPodAutoscaler for Postgres (`InPlaceOrRecreate`, 100m/256Mi up to 1 CPU/1Gi). Not applied yet; VPA must be installed separately. |
| `Backend/DataBase/secret.yml` | Template of the Secret `db-secret` in the `database` namespace (password is `CHANGE_ME`). Never commit the real password. |
| `DEPRECATED/` | Files that are no longer used: the single test Pods (apache, flask, database) and the old Flask PVC. Do not apply them. |

## Important: volumes

The database keeps its data under `/var/lib/postgresql/data`, on a PersistentVolumeClaim. **The data survives when the pod is deleted, restarted or recreated**: the new pod mounts the same volume and finds the data in place.

The backend has no volume: the saved files are stored in the database, so the backend pods keep no data.

The database Deployment uses `strategy: type: Recreate`: the old pod stops before the new one starts, so two PostgreSQL servers never use the same data directory.

## The database password

PostgreSQL reads `POSTGRES_PASSWORD` only on the first start, when the data directory is empty. Changing the Secret later does not change the password inside an existing database.

A pod can only use a Secret from its own namespace, so the password is kept in two Secrets with the same name and password: `Backend/DataBase/secret.yml` (namespace `database`) and `Backend/Flask/secret.yml` (namespace `backend`). Set the password in both (replace `CHANGE_ME`) and apply them. Do not commit the real password to git.

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

## Planned

Auth service (JWT, Google sign-in); Jenkins CI/CD, Argo, Prometheus and Grafana; Helm, Terraform and logging.
