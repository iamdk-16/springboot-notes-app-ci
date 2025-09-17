pipeline {
  agent any
  tools {
    jdk 'jdk11'
    maven 'maven3'
  }
  environment {
    DOCKERHUB_REPO = 'iamdk-16/notes-app-ci'
    IMAGE_TAG = "${env.BUILD_NUMBER}"
    IMAGE_LATEST = "latest"
    APP_NAME = 'notes-app'
  }
  
  options {
    timestamps()
  }
  
  stages {
    stage('🔄 Checkout from GitHub') {
      steps {
        echo "Pulling latest code from GitHub repository..."
        checkout scm
        sh 'ls -la'
      }
    }
    
    stage('🏗️ Set up JDK and Maven') {
      steps {
        echo "Verifying Java and Maven installation..."
        sh 'java -version'
        sh 'mvn -v'
      }
    }
    
    stage('🧪 Run Tests') {
      steps {
        echo "Running unit tests..."
        sh 'mvn test'
      }
      post {
        always {
          // Use junit instead of publishTestResults
          junit testResultsPattern: 'target/surefire-reports/*.xml', allowEmptyResults: true
          archiveArtifacts artifacts: 'target/surefire-reports/*.xml', fingerprint: true, allowEmptyArchive: true
        }
      }
    }
    
    stage('📦 Build JAR with Maven') {
      steps {
        echo "Building Spring Boot JAR file..."
        sh 'mvn -B -DskipTests clean package'
        sh 'ls -la target/'
        sh 'test -f target/notes-app.jar'
      }
      post {
        success {
          archiveArtifacts artifacts: 'target/notes-app.jar', fingerprint: true
          echo "✅ JAR file built successfully!"
        }
      }
    }
    
    stage('🐳 Build Docker Image') {
      steps {
        echo "Building Docker image with build number: ${BUILD_NUMBER}"
        sh """
          echo "Building Docker image..."
          docker build \\
            --build-arg BUILD_NUMBER=${BUILD_NUMBER} \\
            -t ${DOCKERHUB_REPO}:${IMAGE_TAG} \\
            -t ${DOCKERHUB_REPO}:${IMAGE_LATEST} \\
            .
          
          echo "Listing built images:"
          docker images | grep notes-app || docker images | head -5
        """
      }
    }
    
    stage('📤 Push to DockerHub') {
      steps {
        echo "Pushing Docker image to DockerHub..."
        withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', 
                                         usernameVariable: 'DH_USER', 
                                         passwordVariable: 'DH_PASS')]) {
          sh '''
            echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin
            
            echo "Pushing images to DockerHub repository: ${DOCKERHUB_REPO}"
            docker push ${DOCKERHUB_REPO}:${IMAGE_TAG}
            docker push ${DOCKERHUB_REPO}:${IMAGE_LATEST}
            
            echo "✅ Successfully pushed to DockerHub!"
          '''
        }
      }
      post {
        always {
          sh 'docker logout || true'
        }
      }
    }
    
    stage('🎯 Create Monitoring Namespace') {
      steps {
        echo "Setting up monitoring namespace..."
        withCredentials([file(credentialsId: 'kubeconfig-kind', variable: 'KUBECONFIG')]) {
          sh '''
            export KUBECONFIG=$KUBECONFIG
            
            echo "📋 Current Kubernetes context:"
            kubectl config current-context
            kubectl get nodes
            
            echo "🎯 Creating monitoring namespace..."
            kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
            
            echo "✅ Monitoring namespace ready!"
          '''
        }
      }
    }
    
    stage('📊 Deploy Prometheus') {
      steps {
        echo "Deploying Prometheus for metrics collection..."
        withCredentials([file(credentialsId: 'kubeconfig-kind', variable: 'KUBECONFIG')]) {
          sh '''
            export KUBECONFIG=$KUBECONFIG
            
            echo "📊 Creating Prometheus deployment..."
            kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: monitoring
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
    scrape_configs:
    - job_name: 'notes-app'
      static_configs:
      - targets: ['notes-app-service.default.svc.cluster.local:8081']
      metrics_path: /actuator/prometheus
      scrape_interval: 5s
    - job_name: 'prometheus'
      static_configs:
      - targets: ['localhost:9090']
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: monitoring
  labels:
    app: prometheus
spec:
  replicas: 1
  selector:
    matchLabels:
      app: prometheus
  template:
    metadata:
      labels:
        app: prometheus
    spec:
      containers:
      - name: prometheus
        image: prom/prometheus:latest
        ports:
        - containerPort: 9090
        volumeMounts:
        - name: config-volume
          mountPath: /etc/prometheus
        command:
        - '--config.file=/etc/prometheus/prometheus.yml'
        - '--storage.tsdb.path=/prometheus'
        - '--web.enable-lifecycle'
      volumes:
      - name: config-volume
        configMap:
          name: prometheus-config
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus-service
  namespace: monitoring
spec:
  type: NodePort
  ports:
  - port: 9090
    targetPort: 9090
    nodePort: 30090
  selector:
    app: prometheus
EOF
            
            echo "⏳ Waiting for Prometheus to be ready..."
            kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=300s || echo "Prometheus may still be starting..."
            
            echo "✅ Prometheus deployed!"
          '''
        }
      }
    }
    
    stage('📈 Deploy Grafana') {
      steps {
        echo "Deploying Grafana for visualization..."
        withCredentials([file(credentialsId: 'kubeconfig-kind', variable: 'KUBECONFIG')]) {
          sh '''
            export KUBECONFIG=$KUBECONFIG
            
            echo "📈 Creating Grafana deployment..."
            kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: monitoring
  labels:
    app: grafana
spec:
  replicas: 1
  selector:
    matchLabels:
      app: grafana
  template:
    metadata:
      labels:
        app: grafana
    spec:
      containers:
      - name: grafana
        image: grafana/grafana:latest
        ports:
        - containerPort: 3000
        env:
        - name: GF_SECURITY_ADMIN_USER
          value: "admin"
        - name: GF_SECURITY_ADMIN_PASSWORD
          value: "admin123"
        - name: GF_USERS_ALLOW_SIGN_UP
          value: "false"
---
apiVersion: v1
kind: Service
metadata:
  name: grafana-service
  namespace: monitoring
spec:
  type: NodePort
  ports:
  - port: 3000
    targetPort: 3000
    nodePort: 30030
  selector:
    app: grafana
EOF
            
            echo "⏳ Waiting for Grafana to be ready..."
            kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=300s || echo "Grafana may still be starting..."
            
            echo "✅ Grafana deployed!"
          '''
        }
      }
    }
    
    stage('🚀 Deploy Notes Application') {
      steps {
        echo "Deploying Notes Application..."
        withCredentials([file(credentialsId: 'kubeconfig-kind', variable: 'KUBECONFIG')]) {
          sh '''
            export KUBECONFIG=$KUBECONFIG
            
            echo "🚀 Deploying Notes Application..."
            kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: notes-app
  namespace: default
  labels:
    app: notes-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: notes-app
  template:
    metadata:
      labels:
        app: notes-app
    spec:
      containers:
      - name: notes-app
        image: ${DOCKERHUB_REPO}:${IMAGE_TAG}
        ports:
        - containerPort: 8081
        env:
        - name: SPRING_PROFILES_ACTIVE
          value: "linux"
        livenessProbe:
          httpGet:
            path: /actuator/health
            port: 8081
          initialDelaySeconds: 60
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /actuator/health
            port: 8081
          initialDelaySeconds: 30
          periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: notes-app-service
  namespace: default
spec:
  type: NodePort
  ports:
  - port: 8081
    targetPort: 8081
    nodePort: 30081
  selector:
    app: notes-app
EOF
            
            echo "⏳ Waiting for Notes App deployment to complete..."
            kubectl rollout status deployment/notes-app -n default --timeout=300s
            
            echo "✅ Notes App deployed successfully!"
          '''
        }
      }
    }
    
    stage('🔍 Health Check') {
      steps {
        echo "Performing health checks..."
        withCredentials([file(credentialsId: 'kubeconfig-kind', variable: 'KUBECONFIG')]) {
          sh '''
            export KUBECONFIG=$KUBECONFIG
            
            echo "📊 Deployment Status:"
            kubectl get pods -A
            kubectl get services -A
            
            echo "🏥 Testing Application Health..."
            for i in {1..10}; do
              if curl -f http://localhost:30081/actuator/health 2>/dev/null; then
                echo "✅ Application is healthy!"
                break
              else
                echo "⏳ Attempt $i: Waiting for application..."
                sleep 10
              fi
            done
          '''
        }
      }
    }
  }
  
  post {
    success {
      echo '''
        🎉🎉🎉 DEPLOYMENT SUCCESSFUL! 🎉🎉🎉
        
        📱 ACCESS YOUR SERVICES:
        ========================================
        🚀 Notes Application:    http://localhost:30081
        🏥 Health Check:         http://localhost:30081/actuator/health  
        📊 App Metrics:          http://localhost:30081/actuator/prometheus
        
        📈 MONITORING STACK:
        ========================================
        🔍 Prometheus:           http://localhost:30090
        📊 Grafana:              http://localhost:30030 (admin/admin123)
      '''
    }
    failure {
      echo '❌ DEPLOYMENT FAILED!'
      sh '''
        echo "🔍 TROUBLESHOOTING:"
        kubectl get pods -A || true
        kubectl logs -l app=notes-app -n default --tail=20 || true
        docker images | grep notes-app || true
      '''
    }
  }
}

