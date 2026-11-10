# Devops_Infra

Dockerfiles and Kubernetes files of the VM Calculator Dashboard (DevOps course final project).
App code: https://github.com/shirmaymon/Devops_ProjectWeb

## Architecture

NGINX Ingress sends `/` to the frontend, `/api/auth` to the auth service and `/api` to the Flask API. Both backend services use the same PostgreSQL database.

| Part | Image | Namespace |
| --- | --- | --- |
| Frontend (Apache) | `shirmaymon/devops-front:v2` | `frontend` |
| Flask API (save / load) | `shirmaymon/devops-backend:v4` | `backend` |
| Auth service (register, login, logout) | `shirmaymon/devops-auth:v1` | `backend` |
| PostgreSQL 17 | `shirmaymon/devops-postgres-database:v3` | `database` |

## Repo structure

| Path | What it is |
| --- | --- |
| `namespaces.yml` | All namespaces: `frontend`, `backend`, `database`, `monitoring`, `jenkins`, `argo`. |
| `Frontend/` | Dockerfile, Deployment, Service, Ingress, HPA (not applied). |
| `Backend/Flask/` | Dockerfile, Deployment, Service, HPA (not applied), `secret.yml`. |
| `Backend/Auth/` | Dockerfile, Deployment, Service. |
| `Backend/backend-ingress.yml` | Ingress for `/api/auth` and `/api`. |
| `Backend/DataBase/` | Dockerfile, `init.sql`, Deployment, Service, PVC, VPA (not applied), `secret.yml`. |
| `CICD/Argo/` | Argo CD Helm values and the Argo CD Application. |
| `CICD/Jenkins/` | Jenkins Helm values and the admin Secret template. |
| `Monitoring/Prometheus/` | Helm values of `kube-prometheus-stack` (Prometheus, Grafana, Prometheus Operator). |
| `Monitoring/Grafana/` | Grafana admin Secret template (`CHANGE_ME`). |
| `DEPRECATED/` | Old single-pod files. Do not apply. |

The `secret.yml` files hold `CHANGE_ME` as the password. Never commit a real password.

## Run on Minikube

Run from the repo folder. Windows: PowerShell. Mac: Terminal. Docker Desktop must be running.

### 1. Start Minikube

```
minikube delete
minikube start --nodes=3 --driver=docker --cpus=2 --memory=4096
kubectl get nodes
```

`minikube delete` removes the old cluster and all its data. Skip it on a first run.

### 2. Enable the addons

```
minikube addons enable csi-hostpath-driver
minikube addons enable ingress
minikube addons enable metrics-server
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=180s
```

If the controller stays `Pending`: `kubectl taint nodes minikube node-role.kubernetes.io/control-plane:NoSchedule-`

### 3. Run the app

Namespaces and the database password (same password in both Secrets):

Windows PowerShell:

```
kubectl apply -f namespaces.yml
$pw = "ChooseYourPassword1"
(Get-Content Backend/DataBase/secret.yml -Raw) -replace 'CHANGE_ME', $pw | kubectl apply -f -
(Get-Content Backend/Flask/secret.yml -Raw) -replace 'CHANGE_ME', $pw | kubectl apply -f -
```

Mac:

```
kubectl apply -f namespaces.yml
pw="ChooseYourPassword1"
sed "s/CHANGE_ME/$pw/g" Backend/DataBase/secret.yml | kubectl apply -f -
sed "s/CHANGE_ME/$pw/g" Backend/Flask/secret.yml | kubectl apply -f -
```

Database, backend, frontend, Ingress (same on both):

```
kubectl apply -f Backend/DataBase/database-pvc.yml -f Backend/DataBase/database-deployment.yml -f Backend/DataBase/database-service.yml
kubectl rollout status deployment/vmcalc-postgres-deployment -n database

kubectl apply -f Backend/Flask/flask-deployment.yml -f Backend/Flask/flask-service.yml
kubectl apply -f Backend/Auth/auth-deployment.yml -f Backend/Auth/auth-service.yml
kubectl apply -f Frontend/apache-deployment.yml -f Frontend/apache-service.yml
kubectl wait --for=condition=available deployment --all -n backend --timeout=180s
kubectl wait --for=condition=available deployment --all -n frontend --timeout=180s

kubectl apply -f Backend/backend-ingress.yml -f Frontend/frontend-ingress.yml
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8080:80
```

The password: letters and digits, at least one letter. Leave the port-forward running, then open http://localhost:8080 (register, save, load, delete, log out). After a frontend update, hard-refresh the browser (Ctrl+Shift+R).

Optional checks:

```
kubectl get pods -A
kubectl exec deployment/vmcalc-postgres-deployment -n database -- psql -U vmcalc -d vmcalc -c "\dt"
curl.exe -i http://localhost:8080/api/auth/me
```

On a Mac use `curl` instead of `curl.exe`.

The tables are `cloud_prices`, `saved_files`, `sessions`, `users`. The `curl` must answer `401` (not logged in).

Stop and start later (keeps the data): `minikube stop`, then `minikube start`, then the port-forward.

## Notes

- The database keeps its data on a PVC, so it survives pod restarts. `init.sql` runs only on an empty data directory; to change the schema, build a new database image tag, delete the database Deployment and PVC, and apply them again.
- Both Secrets `db-secret` (in `database` and `backend`) must have the same password.

## Argo CD and Jenkins (installed with Helm)

Install (the Jenkins Secret line differs by system):

```
kubectl apply -f namespaces.yml
helm repo add argo https://argoproj.github.io/argo-helm
helm repo add jenkins https://charts.jenkins.io
helm repo update
helm install argocd argo/argo-cd -n argo --version 10.4.0 -f CICD/Argo/argocd-values.yml
kubectl apply -f CICD/Argo/application.yml
```

Jenkins admin Secret, Windows PowerShell:

```
(Get-Content CICD/Jenkins/secret.yml -Raw) -replace 'CHANGE_ME', 'ChooseYourPassword2' | kubectl apply -f -
```

Mac:

```
sed "s/CHANGE_ME/ChooseYourPassword2/g" CICD/Jenkins/secret.yml | kubectl apply -f -
```

Then:

```
helm install jenkins jenkins/jenkins -n jenkins --version 5.9.63 -f CICD/Jenkins/jenkins-values.yml
```

Open Argo CD and Jenkins. Each port-forward keeps running, so use a separate window for each:

```
kubectl port-forward svc/argocd-server -n argo 8081:443
```

```
kubectl port-forward svc/jenkins -n jenkins 8082:8080
```

Argo CD admin password, Windows PowerShell:

```
kubectl -n argo get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | ForEach-Object { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) }
```

Mac:

```
kubectl -n argo get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

Argo CD: https://localhost:8081, user `admin`. Jenkins: http://localhost:8082, user `admin`.

The Argo CD Application follows this repo. It does not sync `namespaces.yml`, the Secrets, the HPA / VPA files, `CICD/` and `DEPRECATED/`. It has the Argo CD finalizer: deleting it (`kubectl delete -f CICD/Argo/application.yml`) also deletes everything it deployed, including the database PVC.

## Prometheus and Grafana (installed with Helm)

`kube-prometheus-stack` in the `monitoring` namespace. Grafana admin Secret, Windows PowerShell:

```
(Get-Content Monitoring/Grafana/secret.yml -Raw) -replace 'CHANGE_ME', 'ChooseYourPassword3' | kubectl apply -f -
```

Mac:

```
sed "s/CHANGE_ME/ChooseYourPassword3/g" Monitoring/Grafana/secret.yml | kubectl apply -f -
```

Install and wait until all pods are `Running`:

```
helm install kube-prometheus-stack oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack --version 88.6.2 -n monitoring -f Monitoring/Prometheus/kube-prometheus-stack-values.yml
kubectl get pods -n monitoring -w
```

Open Grafana and Prometheus. Each port-forward keeps running, so use a separate window for each:

```
kubectl get svc -n monitoring
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80
```

```
kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090
```

Grafana: http://localhost:3000, user `admin`, password as chosen in the Secret. Prometheus: http://localhost:9090.

Notes: Alertmanager is off, Prometheus keeps 2 days of metrics and has no volume , and the Minikube control-plane scrape targets are off. The Argo CD Application does not sync `Monitoring/Grafana/secret.yml` and the Helm values file.

## Planned

Jenkins pipeline, application metrics (`/metrics` and ServiceMonitors), then AWS with HTTPS and Google sign-in.