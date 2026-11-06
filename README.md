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

The backend saves user files under `/web-data`, and the database keeps its data under `/var/lib/postgresql/data`. **Without a volume, both are lost when the pod is recreated.** Both Deployments mount a PVC.

The database Deployment uses `strategy: type: Recreate`: the old pod stops before the new one starts, so two PostgreSQL servers never use the same data directory.

A PVC cannot be expanded here (`ALLOWVOLUMEEXPANSION` is false on the StorageClasses), so choose the size before you create it.

## The database password

PostgreSQL reads `POSTGRES_PASSWORD` only on the first start, when the data directory is empty. Changing the Secret later does not change the password inside an existing database.

Create the Secret by command, so the password never lands in a file:

```
kubectl create secret generic db-secret --from-literal=password=<choose-a-password> -n database
```

Or edit `Backend/DataBase/secret.yml` locally and apply it, but do not commit it with the real password.

## Run it on Minikube

Cluster (3 nodes, Docker driver):

```
minikube config set driver docker
minikube start --nodes=3 --driver=docker --cpus=2 --memory=2048
```

Storage for a multi-node cluster. The default host-path provisioner does not support multi-node clusters, so enable the CSI hostpath driver (it creates the StorageClass `csi-hostpath-sc`):

```
minikube addons enable csi-hostpath-driver
kubectl get storageclass
```

Ingress controller (NGINX):

```
minikube addons enable ingress
kubectl get pods -n ingress-nginx
```

If the controller pod stays Pending because of the control-plane taint, remove the taint:

```
kubectl taint nodes minikube node-role.kubernetes.io/control-plane:NoSchedule-
```

Namespaces:

```
kubectl apply -f namespaces.yml
```

Deploy the database first (from `Backend/DataBase`):

```
kubectl create secret generic db-secret --from-literal=password=<choose-a-password> -n database
kubectl apply -f pvc.yml
kubectl apply -f deployment.yml
kubectl apply -f service.yml
```

Then the backend, then the frontend (from the repo root):

```
kubectl apply -f Backend/Flask/pvc.yml
kubectl apply -f Backend/Flask/deployment.yml
kubectl apply -f Backend/Flask/service.yml
kubectl apply -f Backend/Flask/ingress.yml
kubectl apply -f Frontend/apache-deployment.yml
kubectl apply -f Frontend/apache-service.yml
kubectl apply -f Frontend/apache-ingress.yml
```

Check:

```
kubectl get deployments,pods,svc,pvc -n database
kubectl get deployments,pods,svc,pvc,ingress -n backend
kubectl get deployments,pods,svc,ingress -n frontend
```

Check the database:

```
kubectl logs deployment/vmcalc-postgres-deployment -n database
kubectl exec -it deployment/vmcalc-postgres-deployment -n database -- psql -U vmcalc -d vmcalc -c "\dt"
```

`\dt` should list `users`, `saved_files` and `cloud_prices`.

Open the app locally (Docker driver on Windows):

```
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8080:80
```

Then open http://localhost:8080.

Switch the default namespace of `kubectl`:

```
kubectl config set-context --current --namespace=backend
```

## Build and push the images

Frontend, from the `Frontend` folder:

```
docker build -t shirmaymon/devops-front:v1 .
docker push shirmaymon/devops-front:v1
```

Backend, from the `Backend/Flask` folder:

```
docker build -t shirmaymon/devops-backend:v1 .
docker push shirmaymon/devops-backend:v1
```

Database, from the `Backend/DataBase` folder:

```
docker build -t shirmaymon/devops-postgres-database:v1 .
docker push shirmaymon/devops-postgres-database:v1
```

The frontend and backend Dockerfiles clone the app repo while building, and Docker caches that step. After the app repo changes, build with `--no-cache` or change `REPO_REF`. The Docker Hub repos are public, so the cluster pulls the images without credentials.

## Planned

Connect the backend to the database; auth service (JWT, Google sign-in); monitoring; Jenkins CI/CD; Helm, Terraform and logging.