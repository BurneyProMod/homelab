CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.20.2}"

kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"

echo "Waiting for cert-manager to be ready..."
kubectl wait --for=condition=Available deployment/cert-manager -n cert-manager --timeout=120s
kubectl wait --for=condition=Available deployment/cert-manager-webhook -n cert-manager --timeout=120s

echo "Cert-manager installed. Now apply the ClusterIssuer:"
echo "  kubectl apply -f kubernetes/cert-manager/ca-issuer.yml"
