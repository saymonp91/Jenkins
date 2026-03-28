# 🚀 CI/CD Pipeline — GitHub → Jenkins → ECR → EKS

Pipeline completo para build, push de imagem Docker no Amazon ECR e deploy no Amazon EKS.

---

## 📁 Estrutura do Projeto

```
.
├── Jenkinsfile                  # Pipeline declarativa (6 stages)
├── Dockerfile                   # Multi-stage build Python
├── k8s/
│   ├── namespace.yaml           # Namespace "production"
│   ├── deployment.yaml          # Deployment com rolling update
│   └── service.yaml             # Service ClusterIP
├── scripts/
│   ├── create-ecr-repo.sh       # Cria o repo no ECR (1x)
│   └── setup-ecr-secret.sh      # Cria imagePullSecret no EKS (1x)
├── app/                         # Seu código Python aqui
│   └── main.py
├── tests/                       # Testes pytest
└── requirements.txt
```

---

## ⚙️ Pré-requisitos no servidor Jenkins

| Ferramenta | Versão mínima |
|------------|--------------|
| Docker     | 24+          |
| AWS CLI    | v2           |
| kubectl    | 1.28+        |
| Python     | 3.10+        |

```bash
# Instalar AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install

# Instalar kubectl
curl -LO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

---

## 🔑 Credenciais no Jenkins

Vá em **Manage Jenkins → Credentials → Global** e crie:

| ID (exato)               | Tipo   | Valor                          |
|--------------------------|--------|--------------------------------|
| `AWS_ACCESS_KEY_ID`      | Secret text | Sua Access Key ID         |
| `AWS_SECRET_ACCESS_KEY`  | Secret text | Sua Secret Access Key     |
| `AWS_ACCOUNT_ID`         | Secret text | ID da sua conta AWS       |

---

## 🏗️ Setup Inicial (execute uma única vez)

### 1. Criar repositório no ECR

```bash
export AWS_REGION=us-east-1
export REPO_NAME=minha-app
bash scripts/create-ecr-repo.sh
```

### 2. Configurar acesso ao EKS

```bash
aws eks update-kubeconfig --region us-east-1 --name meu-cluster-eks
kubectl apply -f k8s/namespace.yaml
```

### 3. Criar imagePullSecret no cluster

```bash
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=<seu-account-id>
export NAMESPACE=production
bash scripts/setup-ecr-secret.sh
```

---

## 🔧 Configurar o Jenkinsfile

Edite as variáveis no topo do `Jenkinsfile`:

```groovy
AWS_REGION   = 'us-east-1'          // sua região
ECR_REPO     = 'minha-app'          // nome do repo ECR
EKS_CLUSTER  = 'meu-cluster-eks'    // nome do cluster EKS
K8S_NAMESPACE = 'production'        // namespace k8s
K8S_DEPLOYMENT = 'minha-app'        // nome do Deployment
```

---

## 🔗 Configurar o Webhook no GitHub

1. No GitHub, vá em **Settings → Webhooks → Add webhook**
2. Payload URL: `http://<ip-jenkins>:8080/github-webhook/`
3. Content type: `application/json`
4. Trigger: **Just the push event**

---

## 🔄 Stages da Pipeline

```
Checkout → Test → Build Docker → Push ECR → Deploy EKS → Smoke Test
```

| Stage         | O que faz                                               |
|---------------|---------------------------------------------------------|
| Checkout      | Clona o repositório do GitHub                           |
| Test          | Roda pytest com cobertura                               |
| Build Docker  | Build multi-stage com tag `<BUILD>-<GIT_COMMIT>`        |
| Push ECR      | Login no ECR + push da imagem com 2 tags                |
| Deploy EKS    | `kubectl apply` nos manifests + aguarda rollout         |
| Smoke Test    | Verifica pods e services no cluster                     |

---

## 🐳 Dockerfile — Detalhes

- **Multi-stage build**: imagem final ~60% menor
- **Usuário sem root**: segurança por padrão
- **Healthcheck**: endpoint `/health` obrigatório
- **Labels OCI**: rastreabilidade de build e commit

---

## ☸️ Kubernetes — Detalhes

- **RollingUpdate** com `maxUnavailable: 0` → zero-downtime
- **Resources** com `requests` e `limits` definidos
- **Liveness + Readiness probes** no `/health`
- Segredos da app via `kubectl create secret generic minha-app-secrets`

```bash
kubectl create secret generic minha-app-secrets \
  --from-literal=DATABASE_URL=postgres://... \
  --from-literal=SECRET_KEY=sua-chave-secreta \
  -n production
```

---

## 🛠️ Troubleshooting

**Erro de push no ECR:**
```bash
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <account>.dkr.ecr.us-east-1.amazonaws.com
```

**Pod em ImagePullBackOff:**
```bash
# Recriar o secret do ECR
bash scripts/setup-ecr-secret.sh
```

**Rollout travado:**
```bash
kubectl rollout history deployment/minha-app -n production
kubectl rollout undo deployment/minha-app -n production   # rollback
```