pipeline {
    agent any

    environment {
        // ─── Docker Hub ───────────────────────────────────────────────
        DOCKERHUB_USER  = 'seu-usuario-dockerhub'         // troque aqui
        IMAGE_NAME      = "${DOCKERHUB_USER}/minha-app"
        IMAGE_TAG       = "${BUILD_NUMBER}-${GIT_COMMIT[0..6]}"

        // ─── Credencial Docker Hub (cadastrada no Jenkins) ────────────
        DOCKERHUB_CREDS = credentials('dockerhub-credentials')
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 20, unit: 'MINUTES')
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
                    pip install pytest
                    pytest tests/ -v
                '''
            }
        }

        // ── 3. BUILD DA IMAGEM ────────────────────────────────────────
        stage('Build Docker Image') {
            steps {
                echo "🐳 Buildando imagem..."
                sh """
                    docker build \
                        -t ${IMAGE_NAME}:${IMAGE_TAG} \
                        -t ${IMAGE_NAME}:latest \
                        .
                """
            }
        }

        // ── 4. PUSH PARA O DOCKER HUB ─────────────────────────────────
        stage('Push to Docker Hub') {
            steps {
                echo "☁️ Enviando imagem para o Docker Hub..."
                sh """
                    echo \$DOCKERHUB_CREDS_PSW | docker login -u \$DOCKERHUB_CREDS_USR --password-stdin
                    docker push ${IMAGE_NAME}:${IMAGE_TAG}
                    docker push ${IMAGE_NAME}:latest
                """
            }
        }

        // ── 5. DEPLOY LOCAL (docker compose) ──────────────────────────
        stage('Deploy') {
            steps {
                echo "🚀 Fazendo deploy com docker compose..."
                sh """
                    IMAGE_TAG=${IMAGE_TAG} IMAGE_NAME=${IMAGE_NAME} \
                        docker compose -f docker-compose.deploy.yml up -d --pull always

                    sleep 10
                    docker compose -f docker-compose.deploy.yml ps
                """
            }
        }

        // ── 6. SMOKE TEST ─────────────────────────────────────────────
        stage('Smoke Test') {
            steps {
                echo "✅ Verificando aplicação..."
                sh "curl -f http://localhost:8000/health || exit 1"
            }
        }
    }

    post {
        success {
            echo "✅ Deploy concluído! Imagem: ${IMAGE_NAME}:${IMAGE_TAG}"
        }
        failure {
            echo "❌ Pipeline falhou. Verifique os logs acima."
        }
        always {
            sh "docker rmi ${IMAGE_NAME}:${IMAGE_TAG} || true"
            sh "docker logout || true"
            cleanWs()
        }
    }
}