pipeline {
  agent any

  environment {
    DOCKER_REGISTRY = 'docker.io'
    IMAGE_NAME      = 'yourdockerhubusername/devops-demo'
    IMAGE_TAG       = "${BUILD_NUMBER}"
    GIT_REPO        = 'https://github.com/yourusername/your-devops-project.git'
    GIT_CREDENTIALS = 'github-creds'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        echo "Building image: ${IMAGE_NAME}:${IMAGE_TAG}"
      }
    }

    stage('Trivy Filesystem Scan') {
      steps {
        echo 'Scanning source code and dependencies for vulnerabilities...'
        sh '''
          trivy fs \
            --severity CRITICAL,HIGH \
            --exit-code 1 \
            --format table \
            --ignorefile .trivyignore \
            ./backend
        '''
      }
    }

    stage('Build Docker Image') {
      steps {
        sh "docker build -t ${IMAGE_NAME}:${IMAGE_TAG} ./backend"
        sh "docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${IMAGE_NAME}:latest"
      }
    }

    stage('Trivy Image Scan') {
      steps {
        echo 'Scanning Docker image for OS and package vulnerabilities...'
        sh '''
          trivy image \
            --severity CRITICAL \
            --exit-code 1 \
            --format table \
            --timeout 10m \
            ${IMAGE_NAME}:${IMAGE_TAG}
        '''
      }
      post {
        always {
          sh '''
            trivy image \
              --format json \
              --output trivy-report.json \
              ${IMAGE_NAME}:${IMAGE_TAG} || true
          '''
          archiveArtifacts artifacts: 'trivy-report.json', allowEmptyArchive: true
        }
      }
    }

    stage('Push to Docker Hub') {
      steps {
        withCredentials([usernamePassword(
          credentialsId: 'dockerhub-creds',
          usernameVariable: 'DOCKER_USER',
          passwordVariable: 'DOCKER_PASS'
        )]) {
          sh 'echo $DOCKER_PASS | docker login -u $DOCKER_USER --password-stdin'
          sh "docker push ${IMAGE_NAME}:${IMAGE_TAG}"
          sh "docker push ${IMAGE_NAME}:latest"
        }
      }
    }

    stage('Update Kubernetes Manifest') {
      steps {
        withCredentials([usernamePassword(
          credentialsId: env.GIT_CREDENTIALS,
          usernameVariable: 'GIT_USER',
          passwordVariable: 'GIT_PASS'
        )]) {
          sh '''
            git config user.email 'jenkins@pipeline.local'
            git config user.name 'Jenkins'
            sed -i "s|image: .*devops-demo.*|image: ${IMAGE_NAME}:${IMAGE_TAG}|" k8s/deployment.yaml
            git add k8s/deployment.yaml
            git commit -m "ci: update image to ${IMAGE_TAG} [skip ci]" || echo 'No changes'
            git push https://${GIT_USER}:${GIT_PASS}@github.com/yourusername/your-devops-project.git main
          '''
        }
      }
    }
  }

  post {
    success {
      echo "Pipeline complete. Image ${IMAGE_NAME}:${IMAGE_TAG} deployed via ArgoCD."
    }
    failure {
      echo 'Pipeline failed. Check Trivy scan results in trivy-report.json'
    }
    always {
      sh 'docker rmi ${IMAGE_NAME}:${IMAGE_TAG} || true'
      sh 'docker logout'
    }
  }
}
