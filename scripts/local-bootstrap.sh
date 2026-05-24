#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v minikube >/dev/null 2>&1; then
  echo "minikube is required but not installed" >&2
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required but not installed" >&2
  exit 1
fi

if ! minikube status >/dev/null 2>&1; then
  echo "Starting Minikube cluster..."
  minikube start --driver=docker --cpus=2 --memory=4096 --disk-size=20g
fi

minikube addons enable metrics-server >/dev/null 2>&1 || true

kubectl apply -f k8s/namespace.yaml
minikube image build -t local/devops-demo:latest ./backend
kubectl apply -f k8s/

kubectl create namespace argocd >/dev/null 2>&1 || true
helm repo add argo-cd https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1 || true
helm upgrade --install argocd argo-cd/argo-cd \
  --namespace argocd \
  --create-namespace \
  --set server.service.type=ClusterIP \
  --set configs.params.server.insecure=true \
  --wait

kubectl create namespace jenkins >/dev/null 2>&1 || true
kubectl apply -f k8s/jenkins/namespace.yaml
kubectl apply -f k8s/jenkins/pvc.yaml

minikube image build -t local/jenkins-devops:latest ./jenkins

if [[ -n "${GITHUB_USER:-}" && -n "${GITHUB_TOKEN:-}" ]]; then
  kubectl create secret generic github-creds \
    --namespace=jenkins \
    --from-literal=username="$GITHUB_USER" \
    --from-literal=password="$GITHUB_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -
else
  echo "GITHUB_USER/GITHUB_TOKEN not set. Jenkins manifest push will fail until github-creds is created." >&2
fi

if [[ -n "${DOCKERHUB_USERNAME:-}" && -n "${DOCKERHUB_PASSWORD:-}" ]]; then
  kubectl create secret generic dockerhub-creds \
    --namespace=jenkins \
    --from-literal=username="$DOCKERHUB_USERNAME" \
    --from-literal=password="$DOCKERHUB_PASSWORD" \
    --dry-run=client -o yaml | kubectl apply -f -
else
  echo "DOCKERHUB_USERNAME/DOCKERHUB_PASSWORD not set. Jenkins Docker Hub push is not configured." >&2
fi

kubectl apply -f k8s/jenkins/service.yaml
kubectl apply -f k8s/jenkins/deployment.yaml

kubectl rollout status deployment/jenkins -n jenkins --timeout=240s

kubectl apply -f argocd/application.yaml

echo "ArgoCD is installed and the Application is registered."
echo "Access Jenkins UI with: kubectl port-forward svc/jenkins -n jenkins 8080:8080"
echo "Access ArgoCD UI with: kubectl port-forward svc/argocd-server -n argocd 8080:443"

auth_secret=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' 2>/dev/null || true)
if [[ -n "$auth_secret" ]]; then
  echo "ArgoCD admin password: $(echo "$auth_secret" | base64 -d)"
fi

jenkins_admin=$(kubectl logs -n jenkins deployment/jenkins 2>/dev/null | grep -Eo 'Please use the following password to proceed to installation: [^ ]+' | tail -n 1 || true)
if [[ -n "$jenkins_admin" ]]; then
  echo "$jenkins_admin"
else
  echo "Jenkins admin password will appear in logs after the first startup. Run: kubectl logs -n jenkins deployment/jenkins | grep -i 'password'"
fi
