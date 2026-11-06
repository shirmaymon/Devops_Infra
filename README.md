# Devops_Infra

Infrastructure repo for the VM Calculator Dashboard (DevOps course final project).

- Application repo (code): https://github.com/shirmaymon/Devops_ProjectWeb
- This repo: Dockerfiles and Kubernetes configuration files.

## Current state

The app is split into a **frontend**, a **backend** and a **database**, each with its own image, Deployment and Service, in its own namespace. An NGINX Ingress routes `/` to the frontend and `/api` to the backend. The calculation itself still runs in the user's browser.

| Part | Image | Namespace | What it runs |
| --- | --- | --- | --- |
| Frontend | `shirmaymon/devops-front:v1` | `frontend` | Apache (`httpd:2.4`) serving the static pages. |
| Backend (Flask) | `shirmaymon/devops-backend:v1` | `backend` | `api.py` (Flask, port 5000): Save / Load routes. Saved files go to `/web-data`. |
| Database | `shirmaymon/devops-postgres-database:v1` | `database` | PostgreSQL 17 (port 5432). Tables are created from `init.sql` on the first start. |

The frontend and backend Dockerfiles are multi-stage builds. Stage 1 (`ubuntu:24.04`) clones the app repo with git (`REPO_URL`, `REPO_REF` build args) and copies only the needed files. The final stage (`httpd:2.4` for the frontend, `python:3.12-slim` for the backend) contains only those files, without git.

The database image is `postgres:17` plus `init.sql`, copied to `/docker-entrypoint-initdb.d/`. The scripts in that folder run only on the first start, when the data directory is empty. On later starts PostgreSQL finds the existing data and skips initialization (verified on the cluster: data survived deleting the pod).

Not built yet: the backend does not connect to the database yet, and the auth service is not built.

The old single-container (monolith) image is still on Docker Hub as `shirmaymon/devopsweb:v1`. Its Dockerfile and manifests are no longer in this repo; they are in the git history.

## Repo structure

| Path | What it is |
| --- | --- |
| `namespaces.yml` | The namespaces: `frontend`, `backend`, `database`, `monitoring`, `jenkins`. |
| `Frontend/Dockerfile` | Multi-stage build of the Apache frontend image. |
| `Frontend/apache-deployment.yml` | Deployment `vmcalc-apache-deployment` (namespace `frontend`). |
| `Frontend/apache-service.yml` | Service `vmcalc-apache-service` (ClusterIP, port 80). |
| `Frontend/apache-ingress.yml` | Ingress for the frontend: `/` to `vmcalc-apache-service:80`. |
| `Frontend/apache-pod.yml` | A single test Pod. Do not apply it together with the Deployment. |
| `Backend/Flask/Dockerfile` | Multi-stage build of the Flask backend image. |
| `Backend/Flask/deployment.yml` | Deployment `vmcalc-flask-deployment` (namespace `backend`), mounts the volume at `/web-data`. |
| `Backend/Flask/service.yml` | Service `vmcalc-flask-service` (ClusterIP, port 5000). |
| `Backend/Flask/ingress.yml` | Ingress for the backend: `/api` to `vmcalc-flask-service:5000`. |
| `Backend/Flask/pvc.yml` | PersistentVolumeClaim `vmcalc-pvc` (1Gi, StorageClass `csi-hostpath-sc`). |
| `Backend/Flask/pod.yml` | A single test Pod. Do not apply it together with the Deployment (same labels, same volume). |
| `Backend/DataBase/Dockerfile` | `postgres:17` plus `init.sql`. |
| `Backend/DataBase/init.sql` | Draft schema: `users`, `saved_files`, `cloud_prices`. Runs once, on the first start. |
| `Backend/DataBase/deployment.yml` | Deployment `vmcalc-postgres-deployment` (namespace `database`), strategy `Recreate`, 1 replica, data at `/var/lib/postgresql/data`. |
| `Backend/DataBase/service.yml` | Service `vmcalc-db-service` (ClusterIP, port 5432). |
| `Backend/DataBase/pvc.yml` | PersistentVolumeClaim `vmcalc-postgres-pvc` (1Gi, StorageClass `csi-hostpath-sc`). |
| `Backend/DataBase/secret.yml` | Template of the Secret `db-secret` (password is `CHANGE_ME`). Never commit the real password. |
| `Backend/DataBase/pod.yml` | A single test Pod. Do not apply it together with the Deployment (same labels, same volume). |

## Important: volumes

The backend saves user files under `/web-data`, and the database keeps its data under `/var/lib/postgresql/data`. Both Deployments mount a PersistentVolumeClaim at these paths, so the data is stored on the volume and not inside the container. **The data survives when a pod is deleted, restarted or recreated**: the new pod mounts the same volume and finds the data in place.

The database Deployment uses `strategy: type: Recreate`: the old pod stops before the new one starts, so two PostgreSQL servers never use the same data directory.


## The database password

PostgreSQL reads `POSTGRES_PASSWORD` only on the first start, when the data directory is empty. Changing the Secret later does not change the password inside an existing database.

Set the password in `Backend/DataBase/secret.yml` (replace `CHANGE_ME`) and apply the file. Do not commit the real password to git.

## Run it on Minikube

```
minikube start --nodes=3 --driver=docker --cpus=2 --memory=2048
minikube addons enable csi-hostpath-driver
minikube addons enable ingress
kubectl apply -f namespaces.yml
kubectl apply -f Backend/DataBase/secret.yml
kubectl apply -f Backend/DataBase/pvc.yml -f Backend/DataBase/deployment.yml -f Backend/DataBase/service.yml
kubectl apply -f Backend/Flask/pvc.yml -f Backend/Flask/deployment.yml -f Backend/Flask/service.yml -f Backend/Flask/ingress.yml
kubectl apply -f Frontend/apache-deployment.yml -f Frontend/apache-service.yml -f Frontend/apache-ingress.yml
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8080:80
```

Then open http://localhost:8080.

If the ingress controller pod stays Pending, remove the control-plane taint: `kubectl taint nodes minikube node-role.kubernetes.io/control-plane:NoSchedule-`

## Planned

Connect the backend to the database; auth service (JWT, Google sign-in); monitoring; Jenkins CI/CD; Helm, Terraform and logging.