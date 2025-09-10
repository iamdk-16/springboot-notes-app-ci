pipeline {
  agent any
  environment {
    DOCKERHUB_REPO = 'thedk/notes-app-ci'
    IMAGE_TAG = "${env.BUILD_NUMBER}"
    IMAGE_LATEST = "latest"
    DOCKER_CLI_EXPERIMENTAL = 'enabled'
  }
  options {
    timestamps()
    ansiColor('xterm')
  }
  triggers {
    pollSCM('H/2 * * * *')
  }
  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }
    stage('Set up JDK and Maven') {
      tools {
        jdk 'jdk11'
        maven 'maven3'
      }
      steps {
        sh 'java -version'
        sh 'mvn -v'
      }
    }
    stage('Build JAR') {
      steps {
        sh 'mvn -B -DskipTests clean package'
        sh 'ls -l target || true'
        sh 'test -f target/notes-app.jar'
      }
      post {
        success {
          archiveArtifacts artifacts: 'target/notes-app.jar', fingerprint: true
        }
      }
    }
    stage('Docker Build') {
      steps {
        script {
          sh """
            docker build \
              --build-arg BUILD_NUMBER=${BUILD_NUMBER} \
              -t ${DOCKERHUB_REPO}:${IMAGE_TAG} \
              -t ${DOCKERHUB_REPO}:${IMAGE_LATEST} \
              .
          """
        }
      }
    }
    stage('Docker Login & Push') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DH_USER', passwordVariable: 'DH_PASS')]) {
          sh 'echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin'
          sh 'docker images | grep notes-app || true'
          sh 'docker push ${DOCKERHUB_REPO}:${IMAGE_TAG}'
          sh 'docker push ${DOCKERHUB_REPO}:${IMAGE_LATEST}'
        }
      }
    }
    stage('Kubernetes Deploy (kind)') {
      steps {
        withCredentials([file(credentialsId: 'kubeconfig-kind', variable: 'KUBECONFIG')]) {
          sh 'kubectl version --client=true'
          // Patch the image in the Deployment before apply for immutability-safe deploys
          sh '''
            set -e
            # Ensure namespace objects apply first (monitoring ns)
            if grep -q "kind: Namespace" k8s/manifest.yaml; then
              kubectl apply -f k8s/manifest.yaml --prune=false
            else
              kubectl apply -f k8s/manifest.yaml
            fi
            # Force image to the new build tag
            kubectl -n default set image deployment/notes-app notes-app=${DOCKERHUB_REPO}:${IMAGE_TAG} --record
            # Wait for rollout
            kubectl -n default rollout status deployment/notes-app --timeout=120s
          '''
        }
      }
    }
    stage('Smoke Check') {
      steps {
        script {
          // kind exposes NodePort on the host network; curl localhost:30081/actuator/health
          sh '''
            set -e
            for i in $(seq 1 30); do
              if curl -fsS http://localhost:30081/actuator/health | grep -q '"status":"UP"'; then
                echo "Health is UP"
                exit 0
              fi
              echo "Waiting for service..."
              sleep 3
            done
            echo "Service did not become healthy in time"
            exit 1
          '''
        }
      }
    }
  }
  post {
    always {
      sh 'docker logout || true'
    }
  }
}

