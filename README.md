# Devops_Infra
 
Infrastructure repo for the VM Calculator Dashboard (DevOps course final project).
 
- Application repo (code): https://github.com/shirmaymon/Devops_ProjectWeb
- This repo: Dockerfiles and Kubernetes configuration files.
## Current state
 
The app is split into a **frontend** and a **backend**, each with its own image, Deployment and Service, in its own namespace. The calculation itself still runs in the user's browser.
 
| Part | Image | Namespace | What it runs |
| --- | --- | --- | --- |
| Frontend | `shirmaymon/devops-front:v1` | `frontend` | Apache (`httpd:2.4`) serving the static pages. |
| Backend (Flask) | `shirmaymon/devops-backend:v1` | `backend` | `api.py` (Flask, port 5000): Save / Load routes. Saved files go to `/web-data`. |
 
Both Dockerfiles are multi-stage builds. Stage 1 (`ubuntu:24.04`) clones the app repo with git (`REPO_URL`, `REPO_REF` build args) and copies only the needed files. The final stage (`httpd:2.4` for the frontend, `python:3.12-slim` for the backend) contains only those files, without git.
 
Not built yet: the Ingress (it will route `/` to the frontend and `/api` to the backend), the database and the auth service. Until the Ingress exists, the frontend pages load but Save / Load do not reach the backend.
 
The old single-container (monolith) image is still on Docker Hub as `shirmaymon/devopsweb:v1`. Its Dockerfile and manifests are no longer in this repo; they are in the git history.
 
## Repo structure
 
| Path | What it is |
| --- | --- |
| `Frontend/Dockerfile` | Multi-stage build of the Apache frontend image. |
| `Frontend/apache-deployment.yml` | Deployment `vmcalc-apache-deployment` (namespace `frontend`). |
| `Frontend/apache-service.yml` | Service `vmcalc-apache-service` (ClusterIP, port 80). |
| `Frontend/apache-pod.yml` | A single test Pod. Do not apply it together with the Deployment. |
| `Backend/Flask/Dockerfile` | Multi-stage build of the Flask backend image. |
| `Backend/Flask/deployment.yml` | Deployment `vmcalc-flask-deployment` (namespace `backend`), mounts the volume at `/web-data`. |
| `Backend/Flask/service.yml` | Service `vmcalc-flask-service` (ClusterIP, port 5000). |
| `Backend/Flask/pvc.yml` | PersistentVolumeClaim `vmcalc-pvc` (1Gi, StorageClass `csi-hostpath-sc`). |
| `Backend/Flask/pod.yml` | A single test Pod. Do not apply it together with the Deployment (same labels, same volume). |
| `Backend/DataBase/Dockerfile` | Placeholder for the database image (empty for now). |
 
## Important: the saved files need a volume
 
The backend saves user files under `/web-data` inside the container. **Without a volume mounted at `/web-data`, the saved files are lost when the pod is recreated** (pod deleted, rolling update, node failure, container restart). The backend Deployment mounts the PVC `vmcalc-pvc` at `/web-data`.
 
With plain Docker, use `docker run -v <volume>:/web-data ...`.
 
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
 
Namespaces:
 
```
kubectl create namespace frontend
kubectl create namespace backend
```
 
Deploy the backend, then the frontend:
 
```
kubectl apply -f Backend/Flask/pvc.yml
kubectl apply -f Backend/Flask/deployment.yml
kubectl apply -f Backend/Flask/service.yml
kubectl apply -f Frontend/apache-deployment.yml
kubectl apply -f Frontend/apache-service.yml
kubectl get deployments,pods,svc,pvc -n backend
kubectl get deployments,pods,svc -n frontend
```
 
Open the frontend locally (until the Ingress exists):
 
```
kubectl port-forward -n frontend svc/vmcalc-apache-service 8080:80
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
 
Both Dockerfiles clone the app repo while building, and Docker caches that step. After the app repo changes, build with `--no-cache` or change `REPO_REF`. The Docker Hub repos are public, so the cluster pulls the images without credentials.
 
## Planned
 
Ingress (`/` to the frontend, `/api` to the backend); database (PostgreSQL) and auth service (JWT, Google sign-in); Helm, Terraform, Jenkins CI/CD, monitoring and logging.