# Devops_Infra

Infrastructure repo for the VM Calculator Dashboard (DevOps course final project).

- Application repo (code): https://github.com/shirmaymon/Devops_ProjectWeb
- This repo: Dockerfile and Kubernetes configuration files.

## Current state

The app runs as a **monolith**: one image and one container run Apache (static pages, proxy for `/api/`) and Flask (`api.py`, port 5000) together. It runs on a local 3-node Minikube cluster.

| File | What it is |
| --- | --- |
| `Frontend/Dockerfile` | Builds the image. Clones the app repo (`REPO_URL`, `REPO_REF` build args), installs Apache and Flask, enables the Apache proxy and `vmcalc.conf`, starts Flask and Apache. |
| `Frontend/deployment.yml` | Deployment `vmcalc-deployment`: 1 replica, image `shirmaymon/devopsweb:v1`, rolling update, resource requests and limits, readiness probe on `/`, scheduled on nodes labeled `role=front`. |
| `Frontend/service.yml` | Service `vmcalc-service` (ClusterIP), port 80 to container port 80. |
| `Frontend/pod.yml` | A single Pod used for the first test. Do not run it together with the Deployment (both use the label `app: vmcalc`). |

The image is on Docker Hub: `shirmaymon/devopsweb:v1`.

## Important: the saved files need a volume

The app saves user files under `/web-data` inside the container. **Without a volume mounted at `/web-data`, the saved files are lost when the pod or container is recreated** (pod deleted, rolling update, node failure, container restart). With more than one replica, each pod would also have its own separate files.

The volume is not mapped yet. To add it:

1. Create a PersistentVolumeClaim (in the same namespace as the Deployment).
2. In the Deployment, add `volumeMounts` (`mountPath: /web-data`) to the container, and `volumes` (with `persistentVolumeClaim.claimName`) to the pod spec.

With plain Docker, use `docker run -v <volume>:/web-data ...`.

## Run it on Minikube

Cluster (3 nodes, Docker driver):

```
minikube config set driver docker
minikube start --nodes=3 --driver=docker --cpus=2 --memory=2048
```

Label the nodes (check the names with `kubectl get nodes`). The Deployment needs a node labeled `role=front`:

```
kubectl label node minikube-m02 role=front
kubectl label node minikube-m03 role=back
```

Deploy. The manifests do not set a namespace. Create one and add `-n <namespace>`, or use the default:

```
kubectl apply -f Frontend/deployment.yml
kubectl apply -f Frontend/service.yml
kubectl get deployments,pods,svc -o wide
kubectl port-forward svc/vmcalc-service 8080:80
```

Open http://localhost:8080.

## Build and push the image

From the `Frontend` folder:

```
docker build -t shirmaymon/devopsweb:v1 .
docker push shirmaymon/devopsweb:v1
```

The Dockerfile clones the app repo while building, and Docker caches that step. After the app repo changes, build with `--no-cache` or change `REPO_REF`.

## Planned

Mount the volume for `/web-data`; split the app into a frontend and microservices (Flask and auth) with a database; Helm, Terraform, Jenkins CI/CD, monitoring and logging.
