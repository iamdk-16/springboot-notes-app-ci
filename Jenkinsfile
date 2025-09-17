pipeline {
  agent any
  
  tools {
    jdk 'jdk11'
    maven 'maven3'
  }
  
  environment {
    DOCKERHUB_REPO = 'thedk/notes-app-ci'
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
    
    stage('🎯 Setup Monitoring') {
      steps {
        echo "Setting up Prometheus & Grafana..."
        withCredentials([file(credentialsId: 'kubeconfig-kind', variable: 'KUBECONFIG')]) {
          sh '''
            export KUBECONFIG=$KUBECONFIG
            
            # Create monitoring namespace
            kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
            
            # Deploy Prometheus
            cat > prometheus.yaml << 'EOF'
apiVersion: v3
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
    - job_name: 'prometheus'
      static_configs:
      - targets: ['localhost:9090']
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: monitoring
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
        command:
        - '--config.file=/etc/prometheus/prometheus.yml'
        - '--storage.tsdb.path=/prometheus'
        - '--web.enable-lifecycle'
      volumes:
      - name: config
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
            kubectl apply -f prometheus.yaml
            
            # Deploy Grafana
            cat > grafana.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: monitoring
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
            export KUBECONFIG=$KUBECONFIG
            
            cat > app.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: notes-app
  namespace: default
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
        readinessProbe:
          httpGet:
            path: /actuator/health
            port: 8081
          initialDelaySeconds: 30
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
            kubectl apply -f app.yaml
            kubectl rollout status deployment/notes-app --timeout=300s
            
            echo "✅ App deployed!"
          '''
        }
      }
    }
    
    stage('🔍 Health Check') {
      steps {
        echo "Checking health..."
        sh '''
          echo "Waiting for services..."
          sleep 60
          
          echo "Testing app..."
          for i in {1..10}; do
            if curl -f http://localhost:30081/actuator/health 2>/dev/null; then
              echo "✅ App is healthy!"
              break
            else
              echo "⏳ Waiting... ($i/10)"
              sleep 10
            fi
          done
          
          echo "📊 Status:"
          kubectl get pods -A | head -20
        '''
      }
    }
  }
  
  post {
    always {
      sh 'docker system prune -f || true'
    }
    success {
      echo '''
        🎉 SUCCESS! 🎉
        
        📱 Your Services:
        • App: http://localhost:30081
        • Health: http://localhost:30081/actuator/health  
        • Metrics: http://localhost:30081/actuator/prometheus
        • Prometheus: http://localhost:30090
        • Grafana: http://localhost:30030 (admin/admin123)
      '''
    }
    failure {
      echo '❌ Pipeline failed!'
      sh '''
        kubectl get pods -A || true
        docker images | grep notes-app || true
      '''
    }
  }
}

