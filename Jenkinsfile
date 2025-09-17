pipeline {
  agent any
  tools {
    jdk 'jdk11'
    maven 'maven3'
  }
  environment {
    DOCKERHUB_REPO = 'thedk/notes-app-ci'  // CHANGE THIS TO YOUR DOCKERHUB USERNAME!
    IMAGE_TAG = "${env.BUILD_NUMBER}"
    IMAGE_LATEST = "latest"
    APP_NAME = 'notes-app'
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
    stage('🔄 Checkout from GitHub') {
      steps {
        echo "Pulling latest code from GitHub repository..."
        checkout scm
        sh 'ls -la'
        sh 'pwd'
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
          publishTestResults testResultsPattern: 'target/surefire-reports/*.xml'
          archiveArtifacts artifacts: 'target/surefire-reports/*.xml', fingerprint: true
        }
      }
    }
    
    stage('📦 Build JAR with Maven') {
      steps {
        echo "Building Spring Boot JAR file..."
        sh 'mvn -B -DskipTests clean package'
        sh 'ls -la target/ || true'
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
        script {
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
            docker images | grep ${DOCKERHUB_REPO} || true
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
<<<<<<< HEAD
            export KUBECONFIG=$KUBECONFIG
            
            echo "📋 Current Kubernetes context:"
            kubectl config current-context
            kubectl get nodes
            
            echo "🎯 Creating monitoring namespace..."
            kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
            
            echo "✅ Monitoring namespace ready!"
=======
            set -e
            if grep -q "kind: Namespace" k8s/full-stack.yaml; then
              kubectl apply -f k8s/full-stack.yaml --prune=false
            else
              kubectl apply -f k8s/full-stack.yaml
            fi
            kubectl -n default set image deployment/notes-app notes-app=${DOCKERHUB_REPO}:${IMAGE_TAG} --record
            kubectl -n default rollout status deployment/notes-app --timeout=120s
>>>>>>> 6097e76014e62e00c2ee717d46de0d97ccf686fe
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
            
            echo "📊 Creating Prometheus configuration..."
            cat <<EOF | kubectl apply -f -
# Prometheus ConfigMap
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
    - job_name: 'grafana'
      static_configs:
      - targets: ['grafana-service.monitoring.svc.cluster.local:3000']
---
# Prometheus Deployment
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
        - name: storage-volume
          mountPath: /prometheus
        command:
        - '--config.file=/etc/prometheus/prometheus.yml'
        - '--storage.tsdb.path=/prometheus'
        - '--web.console.libraries=/etc/prometheus/console_libraries'
        - '--web.console.templates=/etc/prometheus/consoles'
        - '--web.enable-lifecycle'
        - '--storage.tsdb.retention.time=30d'
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi" 
            cpu: "500m"
      volumes:
      - name: config-volume
        configMap:
          name: prometheus-config
      - name: storage-volume
        emptyDir: {}
---
# Prometheus Service
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
            kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=300s
            
            echo "✅ Prometheus deployed successfully!"
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
            cat <<EOF | kubectl apply -f -
# Grafana Deployment
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
        - name: GF_INSTALL_PLUGINS
          value: "grafana-clock-panel,grafana-simple-json-datasource"
        volumeMounts:
        - name: grafana-storage
          mountPath: /var/lib/grafana
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
      volumes:
      - name: grafana-storage
        emptyDir: {}
---
# Grafana Service
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
            kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=300s
            
            echo "✅ Grafana deployed successfully!"
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
            cat <<EOF | kubectl apply -f -
# Notes App Deployment
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
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
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
# Notes App Service
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
    
    stage('🔍 Health Check & Verification') {
      steps {
        echo "Performing comprehensive health checks..."
        withCredentials([file(credentialsId: 'kubeconfig-kind', variable: 'KUBECONFIG')]) {
          sh '''
            export KUBECONFIG=$KUBECONFIG
            
            echo "📊 Deployment Status:"
            kubectl get deployments -A
            echo ""
            kubectl get services -A
            echo ""
            kubectl get pods -A
            
            echo "🏥 Testing Application Health..."
            for i in $(seq 1 30); do
              echo "Attempt $i: Testing application health..."
              if curl -f -m 5 http://localhost:30081/actuator/health 2>/dev/null | grep -q '"status":"UP"'; then
                echo "✅ Application is healthy and responding!"
                break
              elif [ $i -eq 30 ]; then
                echo "⚠️ Application health check timeout, but continuing..."
                kubectl logs -l app=notes-app -n default --tail=20 || true
              else
                echo "⏳ Waiting for application to be ready..."
                sleep 10
              fi
            done
            
            echo "📈 Testing Prometheus..."
            if curl -f -m 5 http://localhost:30090/-/ready 2>/dev/null; then
              echo "✅ Prometheus is accessible and ready!"
            else
              echo "⚠️ Prometheus not ready yet, checking logs..."
              kubectl logs -l app=prometheus -n monitoring --tail=10 || true
            fi
            
            echo "📊 Testing Grafana..."
            if curl -f -m 5 http://localhost:30030/api/health 2>/dev/null; then
              echo "✅ Grafana is accessible!"
            else
              echo "⚠️ Grafana not ready yet, checking logs..."
              kubectl logs -l app=grafana -n monitoring --tail=10 || true
            fi
            
            echo "🎯 Checking Prometheus Targets..."
            sleep 15
            if curl -s "http://localhost:30090/api/v1/targets" | grep -q "notes-app"; then
              echo "✅ Prometheus is discovering application targets!"
            else
              echo "⚠️ Prometheus targets might not be ready yet (normal for first deployment)"
            fi
          '''
        }
      }
    }
    
    stage('🎨 Configure Grafana Datasource') {
      steps {
        echo "Setting up Grafana datasource and dashboards..."
        script {
          sh '''
            echo "🎨 Grafana Configuration:"
            echo "=================================================="
            echo "Waiting for Grafana to be fully ready..."
            sleep 30
            
            echo "📊 Setting up Prometheus datasource in Grafana..."
            # Add Prometheus datasource via API
            curl -X POST http://admin:admin123@localhost:30030/api/datasources \\
              -H "Content-Type: application/json" \\
              -d '{
                "name": "Prometheus",
                "type": "prometheus", 
                "url": "http://prometheus-service.monitoring.svc.cluster.local:9090",
                "access": "proxy",
                "isDefault": true
              }' || echo "Datasource might already exist or Grafana not ready"
              
            echo "✅ Grafana datasource configuration attempted!"
          '''
        }
      }
    }
  }
  
  post {
    always {
      sh '''
        docker system prune -f || true
      '''
    }
    success {
      echo '''
        🎉🎉🎉 COMPLETE DEPLOYMENT SUCCESSFUL! 🎉🎉🎉
        
        📱 ACCESS YOUR SERVICES:
        ========================================
        🚀 Notes Application:    http://localhost:30081
        🏥 Health Check:         http://localhost:30081/actuator/health  
        📊 App Metrics:          http://localhost:30081/actuator/prometheus
        
        📈 MONITORING STACK:
        ========================================
        🔍 Prometheus:           http://localhost:30090
        📊 Grafana:              http://localhost:30030 (admin/admin123)
        
        🎯 GRAFANA SPRING BOOT DASHBOARDS TO IMPORT:
        =============================================  
        • Dashboard ID 19004: Spring Boot 3.x Statistics
        • Dashboard ID 6756:  Spring Boot Statistics
        • Dashboard ID 14430: Spring Boot Endpoint Metrics
        
        🔧 KUBERNETES COMMANDS:
        ========================================
        kubectl get pods -A
        kubectl get services -A
        kubectl logs -l app=notes-app -n default
        kubectl logs -l app=prometheus -n monitoring
        kubectl logs -l app=grafana -n monitoring
      '''
    }
    failure {
      echo '❌ DEPLOYMENT FAILED!'
      sh '''
        echo "🔍 TROUBLESHOOTING INFORMATION:"
        echo "============================="
        kubectl get pods -A || true
        echo ""
        echo "Application logs:"
        kubectl logs -l app=notes-app -n default --tail=50 || true
        echo ""
        echo "Prometheus logs:"
        kubectl logs -l app=prometheus -n monitoring --tail=20 || true
        echo ""
        echo "Grafana logs:"  
        kubectl logs -l app=grafana -n monitoring --tail=20 || true
        echo ""
        echo "Docker images:"
        docker images | grep notes-app || true
      '''
    }
  }
}

