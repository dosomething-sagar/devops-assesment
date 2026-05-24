# DevSecOps Pipeline Project

A production-style DevSecOps portfolio project that demonstrates a CI/CD flow from GitHub Actions to Jenkins, Trivy, Docker Hub, ArgoCD, and Amazon EKS.

## What this repository contains

- `backend/` — Node.js + Express app and Docker image
- `k8s/` — Kubernetes manifests for the app, service, HPA, MongoDB StatefulSet, and MongoDB service
- `argocd/` — ArgoCD Application manifest
- `.github/workflows/ci.yml` — GitHub Actions workflow
- `Jenkinsfile` — Jenkins pipeline with Trivy, Docker build/push, and Git manifest update
- `.trivyignore` — accepted CVE exceptions

## Architecture flow

1. Push to `main`
2. GitHub Actions runs:
   - `npm ci`
   - `npm test`
   - Trivy filesystem scan
   - Jenkins webhook trigger (only if secrets are configured)
3. Jenkins runs:
   - checkout
   - Trivy filesystem scan
   - Docker build
   - Trivy image scan
   - Docker push to Docker Hub
   - update `k8s/deployment.yaml`
4. ArgoCD detects the Git change and syncs the cluster
5. EKS runs the application with HPA, readiness/liveness probes, and MongoDB persistence

## Local validation

### Backend

```bash
cd backend
npm install
npm test
```

### Docker build (local)

```bash
cd backend
docker build -t devops-demo-local:latest .
```

## Required secrets and configuration

### GitHub Actions secrets

Add the following secrets in **GitHub Settings → Secrets and variables → Actions**:

- `JENKINS_URL`
- `JENKINS_USER`
- `JENKINS_TOKEN`

### Jenkins credentials

In Jenkins, add the following credentials in **Manage Jenkins → Credentials → Global**:

- `dockerhub-creds` — Docker Hub username/password or access token
- `github-creds` — GitHub username/personal access token with repo write access

### Replace placeholders before use

Update the following placeholders in the repo before running the full pipeline:

- `yourdockerhubusername` in `Jenkinsfile` and `k8s/deployment.yaml`
- `yourusername` in `Jenkinsfile` and `argocd/application.yaml`
- `your-devops-project` in `argocd/application.yaml` if your repo name differs

## Jenkins pipeline behavior

The Jenkins pipeline performs these checks:

- Trivy filesystem scan on `./backend`
- Docker image build
- Trivy image scan
- Docker push to Docker Hub
- Git update of `k8s/deployment.yaml`
- Cleanup of local Docker images

If Trivy finds a **CRITICAL** vulnerability, the build fails and the image is not pushed.

## ArgoCD setup

### Install ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=120s
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

### Register the application

```bash
kubectl apply -f argocd/application.yaml
kubectl get application -n argocd
kubectl get pods -n production -w
```

## EKS deployment notes

### Create the cluster

```bash
eksctl create cluster \
  --name devops-demo \
  --region ap-south-1 \
  --nodegroup-name workers \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 2 \
  --nodes-max 5 \
  --managed
```

### Apply the manifests

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/
```

## Failure debugging demo

To demonstrate the failure scenario during a video or interview:

```bash
kubectl set image deployment/devops-demo \
  app=yourdockerhubusername/devops-demo:999-doesnotexist \
  -n production

kubectl get pods -n production
kubectl describe pod <failing-pod-name> -n production
kubectl get events -n production --sort-by='.lastTimestamp'

# Recovery
kubectl rollout undo deployment/devops-demo -n production
kubectl rollout status deployment/devops-demo -n production
```

## Tradeoffs and production notes

- The service uses a `LoadBalancer` for simplicity and does not include TLS termination.
- `MONGO_URI` is currently hardcoded in the deployment manifest.
- MongoDB uses a single replica and PVC-backed storage, which is suitable for demos but not high-availability production.
- Trivy is configured to fail on `CRITICAL,HIGH` in GitHub Actions and `CRITICAL` in the image scan stage.

## Resume-ready impact

- Built a complete GitHub Actions → Jenkins → Trivy → Docker Hub → ArgoCD → EKS pipeline
- Implemented Trivy-based fail-fast security scanning before image promotion
- Configured readiness/liveness probes, HPA, and persistent MongoDB storage
- Demonstrated GitOps-driven deployment and rollback behavior
