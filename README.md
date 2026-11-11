# Devops_Infra

Kubernetes files of the VM Calculator Dashboard (DevOps course final project).
App code and Dockerfiles: https://github.com/shirmaymon/Devops_ProjectWeb

## Architecture

NGINX Ingress sends `/` to the frontend, `/api/auth` to the auth service and `/api` to the Flask API. Both backends use the same PostgreSQL database. Network rules (Calico) allow only: Ingress to the frontend and backend, and backend to the database. Jenkins builds the images from the app repo and writes the new tags into the Deployment files here; Argo CD deploys them.

| Part | Image | Namespace |
| --- | --- | --- |
| Frontend (Apache) | `shirmaymon/devops-front` | `frontend` |
| Flask API | `shirmaymon/devops-backend` | `backend` |
| Auth service | `shirmaymon/devops-auth` | `backend` |
| PostgreSQL 17 | `shirmaymon/devops-postgres-database:v3` | `database` |

## Repo structure

| Path | What it is |
| --- | --- |
| `namespaces.yml` | All namespaces. |
| `Frontend/` | Deployment, Service, Ingress, HPA (not applied). |
| `Backend/Flask/`, `Backend/Auth/` | Deployment, Service (Flask also `secret.yml`, HPA not applied). |
| `Backend/DataBase/` | Dockerfile, `init.sql`, Deployment, Service, PVC, `secret.yml`. |
| `Backend/backend-ingress.yml` | Ingress for `/api/auth` and `/api`. |
| `Security/NetworkPolicy/` | Network rules, one file per namespace. |
| `CICD/Argo/`, `CICD/Jenkins/` | Helm values, Argo CD Application, Jenkins admin Secret. |
| `Monitoring/` | Helm values of `kube-prometheus-stack`, Grafana admin Secret. |
| `DEPRECATED/` | Old files. Do not apply. |

The `secret.yml` files hold `CHANGE_ME` as the password. Never commit a real password.

## Run on Minikube

Run from the repo folder, in Windows PowerShell with Docker Desktop running. Mac commands are in the section below.

### Start Minikube and enable the addons

```
minikube delete
minikube start --nodes=3 --driver=docker --cni=calico --cpus=2 --memory=4096
minikube addons enable csi-hostpath-driver
minikube addons enable ingress
minikube addons enable metrics-server
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=180s
kubectl get nodes
kubectl get pods -n kube-system
```

### Run the app

```
kubectl apply -f namespaces.yml
$pw = "ChooseYourPassword1"
(Get-Content Backend/DataBase/secret.yml -Raw) -replace 'CHANGE_ME', $pw | kubectl apply -f -
(Get-Content Backend/Flask/secret.yml -Raw) -replace 'CHANGE_ME', $pw | kubectl apply -f -

kubectl apply -f Backend/DataBase/database-pvc.yml -f Backend/DataBase/database-deployment.yml -f Backend/DataBase/database-service.yml
kubectl rollout status deployment/vmcalc-postgres-deployment -n database

kubectl apply -f Backend/Flask/flask-deployment.yml -f Backend/Flask/flask-service.yml
kubectl apply -f Backend/Auth/auth-deployment.yml -f Backend/Auth/auth-service.yml
kubectl apply -f Frontend/apache-deployment.yml -f Frontend/apache-service.yml
kubectl wait --for=condition=available deployment --all -n backend --timeout=180s
kubectl wait --for=condition=available deployment --all -n frontend --timeout=180s

kubectl apply -f Security/NetworkPolicy/

kubectl apply -f Backend/backend-ingress.yml -f Frontend/frontend-ingress.yml
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8080:80
```

App: http://localhost:8080

### Run Argo CD, Jenkins, Prometheus and Grafana

```
helm repo add argo https://argoproj.github.io/argo-helm
helm repo add jenkins https://charts.jenkins.io
helm repo update

helm install argocd argo/argo-cd -n argo --version 10.4.0 -f CICD/Argo/argocd-values.yml
kubectl apply -f CICD/Argo/application.yml

(Get-Content CICD/Jenkins/secret.yml -Raw) -replace 'CHANGE_ME', 'ChooseYourPassword2' | kubectl apply -f -
helm install jenkins jenkins/jenkins -n jenkins --version 5.9.63 -f CICD/Jenkins/jenkins-values.yml

(Get-Content Monitoring/Grafana/secret.yml -Raw) -replace 'CHANGE_ME', 'ChooseYourPassword3' | kubectl apply -f -
helm install kube-prometheus-stack oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack --version 88.6.2 -n monitoring -f Monitoring/Prometheus/kube-prometheus-stack-values.yml
kubectl get pods -n monitoring -w
```

Port-forwards, each in a separate window:

```
kubectl port-forward svc/argocd-server -n argo 8081:443
kubectl port-forward svc/jenkins -n jenkins 8082:8080
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80
kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090
```

Argo CD admin password:

```
kubectl -n argo get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | ForEach-Object { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) }
```

Argo CD https://localhost:8081, Jenkins http://localhost:8082, Grafana http://localhost:3000, Prometheus http://localhost:9090. User `admin` in all four; the passwords are the ones chosen in the Secrets above.

### Mac Terminal

Use these in place of the PowerShell lines above.

```
pw="ChooseYourPassword1"
sed "s/CHANGE_ME/$pw/g" Backend/DataBase/secret.yml | kubectl apply -f -
sed "s/CHANGE_ME/$pw/g" Backend/Flask/secret.yml | kubectl apply -f -

sed "s/CHANGE_ME/ChooseYourPassword2/g" CICD/Jenkins/secret.yml | kubectl apply -f -
sed "s/CHANGE_ME/ChooseYourPassword3/g" Monitoring/Grafana/secret.yml | kubectl apply -f -

kubectl -n argo get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

In the optional checks use `curl` instead of `curl.exe`.

### Optional checks

```
kubectl get pods -A
kubectl exec deployment/vmcalc-postgres-deployment -n database -- psql -U vmcalc -d vmcalc -c "\dt"
curl.exe -i http://localhost:8080/api/auth/me
```

The tables are `cloud_prices`, `saved_files`, `sessions`, `users`. The `curl` answers `401` (not logged in).

## Notes

- The database password must be the same in both `db-secret` Secrets (letters and digits, at least one letter).
- If the Ingress controller stays `Pending`: `kubectl taint nodes minikube node-role.kubernetes.io/control-plane:NoSchedule-`
- Stop and start later (keeps the data): `minikube stop`, `minikube start`, then the port-forwards.
- Jenkins: the credentials `dockerhub` and `github-infra` and the pipeline job are set in the Jenkins UI. The pipeline is the `Jenkinsfile` in the app repo.
- Deleting the Argo CD Application also deletes everything it deployed, including the database PVC.

## Planned

Application metrics (`/metrics` and ServiceMonitors), then AWS with HTTPS and Google sign-in.