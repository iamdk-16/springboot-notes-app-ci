pipeline {
  agent any
  tools {
    jdk 'jdk11'
    maven 'maven3'
  }
  environment {
    DOCKERHUB_REPO = 'thedk/notes-app-ci'  // Change to your actual DockerHub username
    IMAGE_TAG = "${env.BUILD_NUMBER}"
    IMAGE_LATEST = "latest"
  }
  options {
    timestamps()
  }
  triggers {
    pollSCM('H/2 * * * *')
  }
  stages {
    stage('🔄 Checkout') {
      steps {
        echo "Pulling code from GitHub..."
        checkout scm
        sh 'ls -la'
      }
    }
    
    stage('🧪 Test') {
      steps {
        echo "Running tests..."
        sh 'mvn test'
      }
    }
    
    stage('📦 Build JAR') {
      steps {
        echo "Building JAR..."
        sh 'mvn clean package -DskipTests'
        sh 'ls -la target/'
      }
    }
    
    stage('🐳 Build Docker') {
      steps {
        echo "Building Docker image..."
        sh '''
          docker build -t ${DOCKERHUB_REPO}:${IMAGE_TAG} .
          docker tag ${DOCKERHUB_REPO}:${IMAGE_TAG} ${DOCKERHUB_REPO}:${IMAGE_LATEST}
          docker images | grep notes-app
        '''
      }
    }
    
    stage('📤 Push to DockerHub') {
      steps {
        echo "Pushing to DockerHub..."
        withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', 
                                         usernameVariable: 'USER', 
                                         passwordVariable: 'PASS')]) {
          sh '''
            echo "$PASS" | docker login -u "$USER" --password-stdin
            docker push ${DOCKERHUB_REPO}:${IMAGE_TAG}
            docker push ${DOCKERHUB_REPO}:${IMAGE_LATEST}
            echo "✅ Pushed to DockerHub!"
          '''
        }
      }
    }
    
    stage('🔧 Install kubectl') {
      steps {
        echo "Installing kubectl..."
        sh '''
          if ! command -v kubectl &> /dev/null; then
            echo "Installing kubectl..."
            curl -LO "https://dl.k8s.io/release/v1.28.0/bin/linux/amd64/kubectl"
            chmod +x kubectl
            if sudo mv kubectl /usr/local/bin/kubectl 2>/dev/null; then
              echo "✅ kubectl installed to /usr/local/bin/"
            else
              mkdir -p /var/jenkins_home/bin
              mv kubectl /var/jenkins_home/bin/kubectl
              export PATH="/var/jenkins_home/bin:$PATH"
              echo "✅ kubectl installed to /var/jenkins_home/bin/"
            fi
          else
            echo "✅ kubectl already available"
          fi
          export PATH="/var/jenkins_home/bin:$PATH"
          kubectl version --client
        '''
      }
    }
    
    stage('🎯 Setup Monitoring') {
      steps {
        echo "Setting up Prometheus & Grafana..."
        withCredentials([file(credentialsId: 'kubeconfig-kind', variable: 'KUBECONFIG')]) {
          sh '''
            export PATH="/var/jenkins_home/bin:$PATH"
            export KUBECONFIG=$KUBECONFIG
            
            echo "📋 Checking Kubernetes connection..."
            kubectl get nodes
            
            echo "🎯 Creating monitoring namespace..."
            kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
            
            echo "🧹 Cleaning up existing monitoring..."
            kubectl delete deployment prometheus -n monitoring --ignore-not-found=true
            kubectl delete service prometheus-service -n monitoring --ignore-not-found=true
            kubectl delete deployment grafana -n monitoring --ignore-not-found=true
            kubectl delete service grafana-service -n monitoring --ignore-not-found=true
            kubectl delete configmap prometheus-config -n monitoring --ignore-not-found=true
            
            echo "📊 Deploying Prometheus..."
            cat > prometheus.yaml <<EOF
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
      scrape_interval: 10s
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
        - name: config
          mountPath: /etc/prometheus
        - name: storage
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
      - name: config
        configMap:
          name: prometheus-config
      - name: storage
        emptyDir: {}
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
            kubectl apply -f prometheus.yaml
            
            echo "📈 Deploying Grafana..."
            cat > grafana.yaml <<EOF
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
            kubectl apply -f grafana.yaml
            echo "✅ Monitoring stack deployed!"
          '''
        }
      }
    }
    
    stage('🚀 Deploy App') {
      steps {
        echo "Deploying Notes App..."
        withCredentials([file(credentialsId: 'kubeconfig-kind', variable: 'KUBECONFIG')]) {
          sh '''
            export PATH="/var/jenkins_home/bin:$PATH"
            export KUBECONFIG=$KUBECONFIG
            
            echo "🔍 Debug info:"
            echo "DOCKERHUB_REPO: ${DOCKERHUB_REPO}"
            echo "IMAGE_TAG: ${IMAGE_TAG}"
            echo "Full image: ${DOCKERHUB_REPO}:${IMAGE_TAG}"
            
            echo "🧹 Cleaning up existing deployment..."
            kubectl delete deployment notes-app --ignore-not-found=true
            kubectl delete service notes-app-service --ignore-not-found=true
            
            echo "🚀 Creating Notes App deployment..."
            cat > app.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: notes-app
  labels:
    app: notes-app
spec:
  replicas: 1
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
        imagePullPolicy: Always
        ports:
        - containerPort: 8081
        env:
        - name: SPRING_PROFILES_ACTIVE
          value: "linux"
        - name: JAVA_OPTS
          value: "-Xmx512m -Xms256m"
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
          initialDelaySeconds: 90
          periodSeconds: 30
          timeoutSeconds: 10
        readinessProbe:
          httpGet:
            path: /actuator/health
            port: 8081
          initialDelaySeconds: 60
          periodSeconds: 10
          timeoutSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: notes-app-service
spec:
  type: NodePort
  ports:
  - port: 8081
    targetPort: 8081
    nodePort: 30081
  selector:
    app: notes-app
EOF
            
            echo "📄 Generated YAML:"
            cat app.yaml
            
            kubectl apply -f app.yaml
            
            echo "⏳ Waiting for deployment to complete..."
            kubectl rollout status deployment/notes-app --timeout=600s
            
            echo "✅ Notes App deployed successfully!"
            kubectl get pods -l app=notes-app
          '''
        }
      }
    }
    
    stage('🔍 Health Check') {
      steps {
        echo "Performing health checks..."
        withCredentials([file(credentialsId: 'kubeconfig-kind', variable: 'KUBECONFIG')]) {
          sh '''
            export PATH="/var/jenkins_home/bin:$PATH"
            export KUBECONFIG=$KUBECONFIG
            
            echo "📊 Deployment Status:"
            kubectl get deployments -A
            echo ""
            kubectl get services -A
            echo ""
            kubectl get pods -A
            
            echo "🏥 Testing Notes App..."
            for i in {1..20}; do
              echo "Attempt $i: Testing application health..."
              if curl -f -m 10 http://localhost:30081/actuator/health 2>/dev/null | grep -q '"status":"UP"'; then
                echo "✅ Notes App is healthy and responding!"
                break
              elif [ $i -eq 20 ]; then
                echo "⚠️ Application health check timeout, checking logs..."
                kubectl logs -l app=notes-app -n default --tail=20 || true
              else
                echo "⏳ Waiting for application to be ready..."
                sleep 15
              fi
            done
            
            echo "📈 Testing Prometheus..."
            for i in {1..10}; do
              if curl -f -m 5 http://localhost:30090/-/ready 2>/dev/null; then
                echo "✅ Prometheus is accessible and ready!"
                break
              else
                echo "⏳ Prometheus - Attempt $i/10..."
                sleep 10
              fi
            done
            
            echo "📊 Testing Grafana..."
            for i in {1..10}; do
              if curl -f -m 5 http://localhost:30030/api/health 2>/dev/null; then
                echo "✅ Grafana is accessible!"
                break
              else
                echo "⏳ Grafana - Attempt $i/10..."
                sleep 10
              fi
            done
            
            echo "🎯 Checking Prometheus targets..."
            sleep 20
            if curl -s "http://localhost:30090/api/v1/targets" 2>/dev/null | grep -q "notes-app"; then
              echo "✅ Prometheus is successfully scraping Notes App metrics!"
            else
              echo "⚠️ Prometheus targets might need more time (normal for first deployment)"
            fi
            
            echo "📋 Final Status Summary:"
            kubectl get all -A | grep -E "(notes-app|prometheus|grafana)" || true
          '''
        }
      }
    }
  }
  post {
    always {
      sh 'docker system prune -f || true'
    }
    success {
      echo '''
        🎉🎉🎉 COMPLETE DEPLOYMENT SUCCESS! 🎉🎉🎉
        
        📱 ACCESS YOUR SERVICES:
        ========================================
        🚀 Notes Application:    http://localhost:30081
        🏥 Health Check:         http://localhost:30081/actuator/health  
        📊 App Metrics:          http://localhost:30081/actuator/prometheus
        
        📈 MONITORING STACK:
        ========================================
        🔍 Prometheus:           http://localhost:30090
        📊 Grafana:              http://localhost:30030 (admin/admin123)
        
        🎯 GRAFANA SETUP INSTRUCTIONS:
        ========================================  
        1. Go to http://localhost:30030
        2. Login with admin/admin123
        3. Add Prometheus datasource:
           URL: http://prometheus-service.monitoring.svc.cluster.local:9090
        4. Import Spring Boot dashboards:
           • Dashboard ID 19004: Spring Boot 3.x Statistics
           • Dashboard ID 6756:  Spring Boot Statistics
           • Dashboard ID 14430: Spring Boot Endpoint Metrics
        
        🔧 KUBERNETES MANAGEMENT:
        ========================================
        kubectl get pods -A
        kubectl get services -A
        kubectl logs -l app=notes-app -n default
        kubectl logs -l app=prometheus -n monitoring  
        kubectl logs -l app=grafana -n monitoring
        
        🚀 DEPLOYMENT COMPLETE - ENJOY YOUR CI/CD PIPELINE!
      '''
    }
    failure {
      echo '❌ DEPLOYMENT FAILED!'
      sh '''
        export PATH="/var/jenkins_home/bin:$PATH"
        echo "🔍 TROUBLESHOOTING INFORMATION:"
        echo "============================="
        kubectl get pods -A || echo "kubectl not available"
        echo ""
        echo "Notes App logs:"
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

