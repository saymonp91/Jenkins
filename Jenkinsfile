pipeline {
    agent any

    environment {
        // ─── AWS / ECR ───────────────────────────────────────────────
        AWS_REGION      = 'us-east-1'
        AWS_ACCOUNT_ID  = credentials('AWS_ACCOUNT_ID')       // Jenkins secret
        ECR_REPO        = 'minha-app'                         // nome do repo no ECR
        ECR_REGISTRY    = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        IMAGE_NAME      = "${ECR_REGISTRY}/${ECR_REPO}"
        IMAGE_TAG       = "${BUILD_NUMBER}-${GIT_COMMIT[0..6]}"

        // ─── EKS ─────────────────────────────────────────────────────
        EKS_CLUSTER     = 'meu-cluster-eks'                   // nome do cluster
        K8S_NAMESPACE   = 'production'
        K8S_DEPLOYMENT  = 'minha-app'

        // ─── Credenciais ──────────────────────────────────────────────
        AWS_CREDENTIALS = credentials('aws-credentials')      // Jenkins: AWS key/secret
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timestamps()
        timeout(time: 30, unit: 'MINUTES')
    }

    stages {

        // ── 1. CHECKOUT ───────────────────────────────────────────────
        stage('Checkout') {
            steps {
                echo "📥 Clonando repositório..."
                checkout scm
            }
        }

        // ── 2. TESTES ─────────────────────────────────────────────────
        stage('Test') {
            steps {
                echo "🧪 Rodando testes..."
                sh '''
                    python3 -m venv .venv
                    . .venv/bin/activate
                    pip install --upgrade pip
                    pip install -r requirements.txt
                    pip install pytest pytest-cov
                    pytest tests/ --cov=app --cov-report=xml --cov-report=term-missing
                '''
            }
            post {
                always {
                    junit allowEmptyResults: true, testResults: '**/test-results/*.xml'
                }
            }
        }

        // ── 3. BUILD DA IMAGEM DOCKER ─────────────────────────────────
        stage('Build Docker Image') {
            steps {
                echo "🐳 Buildando imagem Docker..."
                sh """
                    docker build \
                        --build-arg BUILD_DATE=\$(date -u +%Y-%m-%dT%H:%M:%SZ) \
                        --build-arg GIT_COMMIT=${GIT_COMMIT} \
                        -t ${IMAGE_NAME}:${IMAGE_TAG} \
                        -t ${IMAGE_NAME}:latest \
                        .
                """
            }
        }

        // ── 4. PUSH PARA O ECR ────────────────────────────────────────
        stage('Push to ECR') {
            steps {
                echo "☁️ Autenticando e enviando imagem para o ECR..."
                withCredentials([
                    string(credentialsId: 'AWS_ACCESS_KEY_ID',     variable: 'AWS_ACCESS_KEY_ID'),
                    string(credentialsId: 'AWS_SECRET_ACCESS_KEY', variable: 'AWS_SECRET_ACCESS_KEY')
                ]) {
                    sh """
                        aws configure set aws_access_key_id \$AWS_ACCESS_KEY_ID
                        aws configure set aws_secret_access_key \$AWS_SECRET_ACCESS_KEY
                        aws configure set region ${AWS_REGION}

                        aws ecr get-login-password --region ${AWS_REGION} \
                            | docker login --username AWS --password-stdin ${ECR_REGISTRY}

                        docker push ${IMAGE_NAME}:${IMAGE_TAG}
                        docker push ${IMAGE_NAME}:latest
                    """
                }
            }
        }

        // ── 5. DEPLOY NO EKS ──────────────────────────────────────────
        stage('Deploy to EKS') {
            steps {
                echo "🚀 Fazendo deploy no EKS..."
                withCredentials([
                    string(credentialsId: 'AWS_ACCESS_KEY_ID',     variable: 'AWS_ACCESS_KEY_ID'),
                    string(credentialsId: 'AWS_SECRET_ACCESS_KEY', variable: 'AWS_SECRET_ACCESS_KEY')
                ]) {
                    sh """
                        aws configure set aws_access_key_id \$AWS_ACCESS_KEY_ID
                        aws configure set aws_secret_access_key \$AWS_SECRET_ACCESS_KEY
                        aws configure set region ${AWS_REGION}

                        aws eks update-kubeconfig \
                            --region ${AWS_REGION} \
                            --name ${EKS_CLUSTER}

                        # Substitui a tag da imagem nos manifests e aplica
                        sed -i 's|IMAGE_PLACEHOLDER|${IMAGE_NAME}:${IMAGE_TAG}|g' k8s/deployment.yaml

                        kubectl apply -f k8s/ --namespace=${K8S_NAMESPACE}

                        # Aguarda o rollout completar
                        kubectl rollout status deployment/${K8S_DEPLOYMENT} \
                            --namespace=${K8S_NAMESPACE} \
                            --timeout=5m
                    """
                }
            }
        }

        // ── 6. SMOKE TEST (pós-deploy) ────────────────────────────────
        stage('Smoke Test') {
            steps {
                echo "✅ Verificando aplicação no cluster..."
                sh """
                    kubectl get pods -n ${K8S_NAMESPACE} -l app=${K8S_DEPLOYMENT}
                    kubectl get svc  -n ${K8S_NAMESPACE} -l app=${K8S_DEPLOYMENT}
                """
            }
        }
    }

    // ── PÓS-PIPELINE ──────────────────────────────────────────────────
    post {
        success {
            echo "✅ Pipeline concluído com sucesso! Imagem: ${IMAGE_NAME}:${IMAGE_TAG}"
            // Descomente para notificação Slack:
            // slackSend(color: 'good', message: "✅ Deploy OK - ${env.JOB_NAME} #${env.BUILD_NUMBER} - ${IMAGE_TAG}")
        }
        failure {
            echo "❌ Pipeline falhou. Verifique os logs acima."
            // slackSend(color: 'danger', message: "❌ Deploy FALHOU - ${env.JOB_NAME} #${env.BUILD_NUMBER}")
        }
        always {
            // Limpa imagens locais para não encher o disco do Jenkins
            sh "docker rmi ${IMAGE_NAME}:${IMAGE_TAG} ${IMAGE_NAME}:latest || true"
            cleanWs()
        }
    }
}