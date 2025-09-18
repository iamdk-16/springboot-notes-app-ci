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
    
    stage('🧹 Clean Previous Deployment') {
      steps {
        echo "Cleaning previous deployment..."
        withCredentials([file(credentialsId: 'kubeconfig-kind', variable: 'KUBECONFIG')]) {
          sh '''
            export PATH="/var/jenkins_home/bin:$PATH"
            export KUBECONFIG=$KUBECONFIG
            
            echo "🧹 Removing old deployments..."
            kubectl delete deployment notes-app --ignore-not-found=true
            kubectl delete deployment prometheus -n monitoring --ignore-not-found=true
            kubectl delete deployment grafana -n monitoring --ignore-not-found=true
            
            kubectl delete service notes-app-service --ignore-not-found=true
            kubectl delete service prometheus-service -n monitoring --ignore-not-found=true
            kubectl delete service grafana-service -n monitoring --ignore-not-found=true
            
            kubectl delete configmap prometheus-config -n monitoring --ignore-not-found=true
            kubectl delete serviceaccount prometheus -n monitoring --ignore-not-found=true
            kubectl delete clusterrole prometheus --ignore-not-found=true
            kubectl delete clusterrolebinding prometheus --ignore-not-found=true
            
            echo "✅ Cleanup completed!"
          '''
        }
      }
    }
    
    stage('🎯 Deploy Complete Stack') {
      steps {
        echo "Deploying complete monitoring stack..."
        withCredentials([file(credentialsId: 'kubeconfig-kind', variable: 'KUBECONFIG')]) {
          sh '''
            export PATH="/var/jenkins_home/bin:$PATH"
            export KUBECONFIG=$KUBECONFIG
            
            echo "📋 Checking Kubernetes connection..."
            kubectl get nodes
            
            echo "🎯 Creating monitoring namespace..."
            kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
            
            echo "🚀 Deploying complete stack..."
            cat > complete-stack.yaml <<EOF
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
      evaluation_interval: 15s
    scrape_configs:
    - job_name: 'notes-app'
      static_configs:
      - targets: ['notes-app-service.default.svc.cluster.local:8081']
      metrics_path: /actuator/prometheus
      scrape_interval: 10s
      scrape_timeout: 10s
    - job_name: 'prometheus'
      static_configs:
      - targets: ['localhost:9090']
---
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
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/path: "/actuator/prometheus"
        prometheus.io/port: "8081"
    spec:
      containers:
      - name: notes-app
        image: ${DOCKERHUB_REPO}:${IMAGE_TAG}
        imagePullPolicy: Always
        ports:
        - containerPort: 8081
          name: http
        env:
        - name: SPRING_PROFILES_ACTIVE
          value: "linux"
        - name: JAVA_OPTS
          value: "-Xmx512m -Xms256m"
        - name: MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE
          value: "health,info,metrics,prometheus"
        resources:
          requests:
            memory: "256Mi"
            cpu: "200m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /actuator/health
            port: 8081
          initialDelaySeconds: 60
          periodSeconds: 30
          timeoutSeconds: 10
        readinessProbe:
          httpGet:
            path: /actuator/health
            port: 8081
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
---
# Notes App Service
apiVersion: v1
kind: Service
metadata:
  name: notes-app-service
  namespace: default
  labels:
    app: notes-app
spec:
  type: NodePort
  selector:
    app: notes-app
  ports:
  - port: 8081
    targetPort: 8081
    nodePort: 30081
    name: http
    protocol: TCP
---
# Prometheus ServiceAccount
apiVersion: v1
kind: ServiceAccount
metadata:
  name: prometheus
  namespace: monitoring
---
# Prometheus ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus
rules:
- apiGroups: [""]
  resources:
  - nodes
  - nodes/proxy
  - services
  - endpoints
  - pods
  verbs: ["get", "list", "watch"]
---
# Prometheus ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prometheus
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: prometheus
subjects:
- kind: ServiceAccount
  name: prometheus
  namespace: monitoring
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
      serviceAccountName: prometheus
      containers:
      - name: prometheus
        image: prom/prometheus:v2.40.0
        args:
        - --config.file=/etc/prometheus/prometheus.yml
        - --storage.tsdb.path=/prometheus
        - --web.console.libraries=/etc/prometheus/console_libraries
        - --web.console.templates=/etc/prometheus/consoles
        - --web.enable-lifecycle
        - --storage.tsdb.retention.time=30d
        ports:
        - containerPort: 9090
          name: http
        volumeMounts:
        - name: prometheus-config
          mountPath: /etc/prometheus
        - name: prometheus-storage
          mountPath: /prometheus
        resources:
          requests:
            memory: "512Mi"
            cpu: "200m"
          limits:
            memory: "1Gi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /-/healthy
            port: 9090
          initialDelaySeconds: 30
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /-/ready
            port: 9090
          initialDelaySeconds: 5
          periodSeconds: 10
      volumes:
      - name: prometheus-config
        configMap:
          name: prometheus-config
      - name: prometheus-storage
        emptyDir: {}
---
# Prometheus Service
apiVersion: v1
kind: Service
metadata:
  name: prometheus-service
  namespace: monitoring
  labels:
    app: prometheus
spec:
  type: NodePort
  selector:
    app: prometheus
  ports:
  - port: 9090
    targetPort: 9090
    nodePort: 30090
    name: prometheus
    protocol: TCP
---
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
        image: grafana/grafana:9.5.0
        ports:
        - containerPort: 3000
          name: http
        env:
        - name: GF_SECURITY_ADMIN_USER
          value: "admin"
        - name: GF_SECURITY_ADMIN_PASSWORD
          value: "admin123"
        - name: GF_USERS_ALLOW_SIGN_UP
          value: "false"
        - name: GF_SERVER_ROOT_URL
          value: "http://localhost:30030"
        volumeMounts:
        - name: grafana-storage
          mountPath: /var/lib/grafana
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "300m"
        livenessProbe:
          httpGet:
            path: /api/health
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /api/health
            port: 3000
          initialDelaySeconds: 10
          periodSeconds: 10
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
  labels:
    app: grafana
spec:
  type: NodePort
  selector:
    app: grafana
  ports:
  - port: 3000
    targetPort: 3000
    nodePort: 30030
    name: grafana
    protocol: TCP
EOF
            
            kubectl apply -f complete-stack.yaml
            echo "✅ Stack deployed!"
          '''
        }
      }
    }
    
    stage('⏳ Wait for Deployment') {
      steps {
        echo "Waiting for all services to be ready..."
        withCredentials([file(credentialsId: 'kubeconfig-kind', variable: 'KUBECONFIG')]) {
          sh '''
            export PATH="/var/jenkins_home/bin:$PATH"
            export KUBECONFIG=$KUBECONFIG
            
            echo "⏳ Waiting for Notes App..."
            kubectl wait --for=condition=ready pod -l app=notes-app --timeout=300s
            
            echo "⏳ Waiting for Prometheus..."
            kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=300s
            
            echo "⏳ Waiting for Grafana..."
            kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=300s
            
            echo "✅ All services ready!"
          '''
        }
      }
    }
    
    stage('🔍 Health Check') {
      steps {
        echo "Performing final health checks..."
        withCredentials([file(credentialsId: 'kubeconfig-kind', variable: 'KUBECONFIG')]) {
          sh '''
            export PATH="/var/jenkins_home/bin:$PATH"
            export KUBECONFIG=$KUBECONFIG
            
            echo "📊 Final Status:"
            kubectl get pods -A
            
            echo "🏥 Testing Notes App..."
            curl -f -m 10 http://localhost:30081/actuator/health && echo "✅ Notes App OK" || echo "⚠️ Notes App not ready yet"
            
            echo "📈 Testing Prometheus..."
            curl -f -m 10 http://localhost:30090/-/ready && echo "✅ Prometheus OK" || echo "⚠️ Prometheus not ready yet"
            
            echo "📊 Testing Grafana..."
            curl -f -m 10 http://localhost:30030/api/health && echo "✅ Grafana OK" || echo "⚠️ Grafana not ready yet"
            
            echo "🎯 Deployment Summary:"
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
        🎉🎉🎉 COMPLETE CI/CD PIPELINE SUCCESS! 🎉🎉🎉
        
        📱 ACCESS YOUR SERVICES:
        ========================================
        🚀 Notes Application:    http://localhost:30081
        🏥 Health Check:         http://localhost:30081/actuator/health  
        📊 App Metrics:          http://localhost:30081/actuator/prometheus
        
        📈 MONITORING STACK:
        ========================================
        🔍 Prometheus:           http://localhost:30090
        📊 Grafana:              http://localhost:30030 (admin/admin123)
        
        🎯 NEXT STEPS:
        ========================================  
        1. Open Grafana and add Prometheus datasource
        2. Import Spring Boot dashboards (ID: 6756, 12900)
        3. Generate traffic on Notes App to see metrics
        
        🚀 YOUR PROFESSIONAL CI/CD PIPELINE IS COMPLETE!
      '''
    }
    failure {
      echo '❌ PIPELINE FAILED - Check logs above'
    }
  }
}

