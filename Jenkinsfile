pipeline {
    agent any

    environment {
        AWS_REGION     = 'us-east-1'
        // Replace <YOUR_ACCOUNT_ID> with your AWS account ID (find it via: aws sts get-caller-identity)
        ECR_REPO       = '<YOUR_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/flask-hello-world'
        CLUSTER_NAME   = 'hello-world-cluster'
        IMAGE_TAG      = "${env.BUILD_NUMBER}"
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build Docker Image') {
            steps {
                dir('webapp') {
                    sh "docker build --platform linux/amd64 -t ${ECR_REPO}:${IMAGE_TAG} ."
                    sh "docker tag ${ECR_REPO}:${IMAGE_TAG} ${ECR_REPO}:latest"
                }
            }
        }

        stage('Push to ECR') {
            steps {
                sh "aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_REPO}"
                sh "docker push ${ECR_REPO}:${IMAGE_TAG}"
                sh "docker push ${ECR_REPO}:latest"
            }
        }

        stage('Deploy to EKS') {
            steps {
                sh "aws eks update-kubeconfig --region ${AWS_REGION} --name ${CLUSTER_NAME}"
                dir('flask-app') {
                    sh """
                        helm upgrade --install flask-app . \
                          --set image.repository=${ECR_REPO} \
                          --set image.tag=${IMAGE_TAG}
                    """
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                sh 'kubectl rollout status deployment/flask-app'
                sh 'kubectl get ingress'
            }
        }
    }

    post {
        success {
            echo 'Deployment successful!'
        }
        failure {
            echo 'Pipeline failed — check logs above.'
        }
    }
}