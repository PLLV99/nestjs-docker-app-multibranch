// =================================================================
// HELPER FUNCTION: Create a function to send notifications to n8n
// Using a helper function reduces duplicate code (DRY Principle)
// =================================================================

def sendNotificationToN8n(String status, String stageName, String imageTag, String containerName, String hostPort) {
    // Uses the Jenkins HTTP Request Plugin (must be installed beforehand)
    // n8n-webhook is a Jenkins Secret Text Credential that stores the n8n webhook URL
    // You must create this Credential in Jenkins with the ID 'n8n-webhook' before using it
    script {
        withCredentials([string(credentialsId: 'n8n-webhook', variable: 'N8N_WEBHOOK_URL')]) {
            def payload = [
                project  : env.JOB_NAME,
                stage    : stageName,
                status   : status,
                build    : env.BUILD_NUMBER,
                image    : "${env.DOCKER_REPO}:${imageTag}",
                container: containerName,
                url      : "http://localhost:${hostPort}/",
                timestamp: new Date().format("yyyy-MM-dd'T'HH:mm:ssXXX")
            ]
            def body = groovy.json.JsonOutput.toJson(payload)
            try {
                httpRequest acceptType: 'APPLICATION_JSON',
                            contentType: 'APPLICATION_JSON',
                            httpMode: 'POST',
                            requestBody: body,
                            url: N8N_WEBHOOK_URL,
                            validResponseCodes: '200:299'
                echo "n8n webhook (${status}) sent successfully."
            } catch (err) {
                echo "Failed to send n8n webhook (${status}): ${err}"
            }
        }
    }
}


pipeline {
    // Use agent any because the build will already run on the Jenkins controller (Linux container)
    agent any

    // Prevent duplicate checkouts
    // If the job is Pipeline from SCM / Multibranch, it's recommended to add options { skipDefaultCheckout(true) }
    // This disables the automatic checkout before stages (since we already have checkout scm below)
    options {
        skipDefaultCheckout(true)   // For Pipeline from SCM / Multibranch
    }

    // Define environment variables
    environment {

        // Docker Hub credentials ID configured in Jenkins
        DOCKER_HUB_CREDENTIALS_ID = 'dockerhub-cred'
        DOCKER_REPO               = "sakamotolv99/nestjs-docker-app"

        // Settings for simulating a DEV environment on local
        DEV_APP_NAME              = "nestjs-app-dev"
        DEV_HOST_PORT             = "7001"

        // Settings for simulating a PROD environment on local
        PROD_APP_NAME             = "nestjs-app-prod"
        PROD_HOST_PORT            = "7000"
    }

    // Define input parameters for selecting the action (Build & Deploy or Rollback)
    // And define ROLLBACK_TAG and ROLLBACK_TARGET when choosing Rollback
    parameters {
        choice(name: 'ACTION', choices: ['Build & Deploy', 'Rollback'], description: 'Select the action you want to perform')
        string(name: 'ROLLBACK_TAG', defaultValue: '', description: 'For Rollback: enter the image tag to use (e.g., Git hash or dev-123)')
        choice(name: 'ROLLBACK_TARGET', choices: ['dev', 'prod'], description: 'For Rollback: choose which environment to rollback')
    }

    // Define Pipeline stages
    stages {

        // =================================================================
        // BUILD STAGES: Executed when ACTION is 'Build & Deploy'
        // =================================================================

        // Stage 1: Pull latest code from Git
        // Uses checkout scm when using Pipeline from SCM
        stage('Checkout') {
            // Condition: only when ACTION is 'Build & Deploy'
            when { expression { params.ACTION == 'Build & Deploy' } }
            steps {
                echo "Checking out code..."
                checkout scm
            }
        }

        // Stage 2: Install dependencies and run tests
        // Uses a Node.js Docker image for consistency
        // If package-lock.json exists, use npm ci instead of npm install for faster, reproducible installs
        stage('Install & Test') {
            // Condition: only when ACTION is 'Build & Deploy'
            when { expression { params.ACTION == 'Build & Deploy' } }
            steps {
                echo "Running tests inside a consistent Docker environment..."
                script {
                    docker.image('node:22-alpine').inside {
                        sh '''
                            if [ -f package-lock.json ]; then npm ci; else npm install; fi
                            npm test
                        '''
                    }
                }
            }
        }

        // Stage 3: Build Docker image
        // Uses Docker installed on the Jenkins agent (Docker plugin required)
        stage('Build & Push Docker Image') {
            when { expression { params.ACTION == 'Build & Deploy' } }
            steps {
                script {
                    def imageTag = (env.BRANCH_NAME == 'main') ? sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim() : "dev-${env.BUILD_NUMBER}"
                    env.IMAGE_TAG = imageTag

                    // Use docker.withRegistry() for secure and simple registry handling
                    docker.withRegistry('https://index.docker.io/v1/', DOCKER_HUB_CREDENTIALS_ID) {
                        echo "Building image: ${DOCKER_REPO}:${env.IMAGE_TAG}"
                        def customImage = docker.build("${DOCKER_REPO}:${env.IMAGE_TAG}", "--target production .")

                        echo "Pushing images to Docker Hub..."
                        customImage.push()
                        // Push 'latest' tag only when on main branch
                        if (env.BRANCH_NAME == 'main') {
                            customImage.push('latest')
                        }
                    }
                }
            }
        }

        // =================================================================
        // DEPLOY STAGES: Executed when ACTION is 'Build & Deploy', per branch
        // =================================================================

        // Stage 4: Deploy to local machine (Development)
        // Pull the latest image from Docker Hub
        // Stop and remove any existing container named ${DEV_APP_NAME}
        // Create and run a new container from the latest image
        stage('Deploy to DEV (Local Docker)') {
            when {
                expression { params.ACTION == 'Build & Deploy' }
                branch 'develop'
            }
            steps {
                script {
                    def deployCmd = """
                            echo "Deploying container ${DEV_APP_NAME} from latest image..."
                            docker pull ${DOCKER_REPO}:${env.IMAGE_TAG}
                            docker stop ${DEV_APP_NAME} || true
                            docker rm ${DEV_APP_NAME} || true
                            docker run -d --name ${DEV_APP_NAME} -p ${DEV_HOST_PORT}:3000 ${DOCKER_REPO}:${env.IMAGE_TAG}
                            docker ps --filter name=${DEV_APP_NAME} --format "table {{.Names}}\\t{{.Image}}\\t{{.Status}}"
                        """
                    sh deployCmd
                }
            }
            // Send data to n8n webhook when deploy to DEV succeeds
            post {
                success {
                    sendNotificationToN8n('success', 'Deploy to DEV (Local Docker)', env.IMAGE_TAG, env.DEV_APP_NAME, env.DEV_HOST_PORT)
                }
            }
        }

        // Stage 5: Wait for approval before deploying to Production
        // Condition: ACTION is 'Build & Deploy' and branch is 'main'
        stage('Approval for Production') {
            when {
                expression { params.ACTION == 'Build & Deploy' }
                branch 'main'
            }
            steps {
                timeout(time: 1, unit: 'HOURS') {
                    input message: "Deploy image tag '${env.IMAGE_TAG}' to PRODUCTION (Local Docker on port ${PROD_HOST_PORT})?"
                }
            }
        }

        // Stage 6: Deploy to local machine (Production)
        // Pull the latest image from Docker Hub
        stage('Deploy to PRODUCTION (Local Docker)') {
            when {
                expression { params.ACTION == 'Build & Deploy' }
                branch 'main'
            }
            steps {
                script {
                    def deployCmd = """
                            echo "Deploying container ${PROD_APP_NAME} from latest image..."
                            docker pull ${DOCKER_REPO}:${env.IMAGE_TAG}
                            docker stop ${PROD_APP_NAME} || true
                            docker rm ${PROD_APP_NAME} || true
                            docker run -d --name ${PROD_APP_NAME} -p ${PROD_HOST_PORT}:3000 ${DOCKER_REPO}:${env.IMAGE_TAG}
                            docker ps --filter name=${PROD_APP_NAME} --format "table {{.Names}}\\t{{.Image}}\\t{{.Status}}"
                        """
                    sh deployCmd
                }
            }
            // Send data to n8n webhook when deploy to PROD succeeds
            post {
                success {
                    sendNotificationToN8n('success', 'Deploy to PRODUCTION (Local Docker)', env.IMAGE_TAG, env.PROD_APP_NAME, env.PROD_HOST_PORT)
                }
            }
        }

        // =================================================================
        // ROLLBACK STAGE: Executed when ACTION is 'Rollback'
        // =================================================================
        stage('Execute Rollback') {
            when { expression { params.ACTION == 'Rollback' } }
            steps {
                script {
                    if (params.ROLLBACK_TAG.trim().isEmpty()) {
                        error "When choosing Rollback, please specify 'ROLLBACK_TAG'"
                    }

                    def targetAppName  = (params.ROLLBACK_TARGET == 'dev') ? DEV_APP_NAME  : PROD_APP_NAME
                    def targetHostPort = (params.ROLLBACK_TARGET == 'dev') ? DEV_HOST_PORT : PROD_HOST_PORT
                    def imageToDeploy  = "${DOCKER_REPO}:${params.ROLLBACK_TAG.trim()}"

                    echo "ROLLING BACK ${params.ROLLBACK_TARGET.toUpperCase()} to image: ${imageToDeploy}"

                    def deployCmd = """
                        docker pull ${imageToDeploy}
                        docker stop ${targetAppName} || true
                        docker rm ${targetAppName} || true
                        docker run -d --name ${targetAppName} -p ${targetHostPort}:3000 ${imageToDeploy}
                    """
                    sh(deployCmd)
                }
            }
            post {
                success {
                    script {
                        def targetAppName  = (params.ROLLBACK_TARGET == 'dev') ? DEV_APP_NAME  : PROD_APP_NAME
                        def targetHostPort = (params.ROLLBACK_TARGET == 'dev') ? DEV_HOST_PORT : PROD_HOST_PORT
                        sendNotificationToN8n('success', "Rollback ${params.ROLLBACK_TARGET.toUpperCase()}", params.ROLLBACK_TAG, targetAppName, targetHostPort)
                    }
                }
            }
        }
    }

    // Define post actions
    // For example, notifications when the pipeline finishes
    post {
        always {
            // Use a script block so we can use if conditions
            script {
                if (params.ACTION == 'Build & Deploy') {
                    echo "Cleaning up Docker images on agent..."
                    // Use try-catch so the pipeline does not fail if image removal fails
                    try {
                        sh """
                            docker image rm -f ${DOCKER_REPO}:${env.IMAGE_TAG} || true
                            docker image rm -f ${DOCKER_REPO}:latest || true
                        """
                    } catch (err) {
                        echo "Could not clean up images, but continuing..."
                    }
                }
                // Workspace cleanup
                echo "Cleaning up workspace..."
                cleanWs()
            }
        }
        failure {
            // Send data to n8n webhook when the pipeline fails
            sendNotificationToN8n('failed', "Pipeline Failed", 'N/A', 'N/A', 'N/A')
        }
    }
}