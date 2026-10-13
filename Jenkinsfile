pipeline {

  agent { label 'docker' }

  environment {
    ARTIFACT_ID   = 'jamii-integration'
    ARTIFACT_VER  = '1.0.0'
    CAR_FILE      = "target/${ARTIFACT_ID}_${ARTIFACT_VER}.car"

    DEV_MI_HOST       = 'localhost'
    DEV_MI_MGMT_PORT  = '9164'
    DEV_MI_HTTP_PORT  = '8290'
    DEV_APIM_HOST     = 'localhost'
    DEV_APIM_PORT     = '9443'
    DEV_APIM_ENV      = 'dev'
  }

  options {
    buildDiscarder(logRotator(numToKeepStr: '20'))
    timestamps()
    timeout(time: 45, unit: 'MINUTES')
    disableConcurrentBuilds()
  }

  stages {

    stage('Checkout') {
      steps {
        checkout scm
        echo "Building commit: ${env.GIT_COMMIT?.take(8) ?: 'unknown'}"
      }
    }

    stage('Build MI Artifacts') {
      steps {
        sh 'mvn clean install -DskipTests -B'
        script {
          if (!fileExists(env.CAR_FILE)) {
            error "Expected CAR not found: ${env.CAR_FILE}"
          }
          echo "CAR artifact ready: ${env.CAR_FILE}"
        }
      }
      post {
        success {
          archiveArtifacts artifacts: 'target/*.car', fingerprint: true
        }
      }
    }

    stage('Package APIM Projects') {
      steps {
        script {
          def apis = ['AccountBalanceAPI', 'CustomerProxyAPI', 'LoanEligibilityAPI']
          apis.each { api ->
            def src = "src/main/wso2mi/resources/api-definitions/${api}.yaml"
            def dst = "apim/apis/${api}/Definitions/swagger.yaml"
            if (!fileExists(src)) {
              error "OpenAPI definition missing for ${api}: ${src}"
            }
            sh "cp '${src}' '${dst}'"
            echo "Packaged OpenAPI definition for ${api}"
          }
        }
        archiveArtifacts artifacts: 'apim/apis/**', allowEmptyArchive: true
      }
    }

    stage('Run Synapse Unit Tests') {
      steps {
        script {
          def hasTests = sh(
            script: 'find src/test/wso2mi -name "*.xml" 2>/dev/null | head -1',
            returnStdout: true
          ).trim()

          if (hasTests) {
            sh 'mvn test -B -Ptest'
          } else {
            echo 'No Synapse unit test files found – skipping test phase.'
          }
        }
      }
      post {
        always {
          junit allowEmptyResults: true,
                testResults: 'target/surefire-reports/*.xml'
        }
      }
    }

    stage('Dev – Start Environment') {
      steps {
        sh 'mkdir -p deployment/car deployment/libs'
        sh "cp '${env.CAR_FILE}' deployment/car/"
        sh '''
          if ! ls deployment/libs/*.zip 1>/dev/null 2>&1; then
            cp target/lib/*.zip deployment/libs/ 2>/dev/null || true
          fi
        '''
        sh 'chmod +x scripts/ci-up.sh scripts/ci-down.sh scripts/deploy-mi.sh scripts/deploy-apim.sh scripts/smoke-test.sh'
        sh 'STACK_STARTUP_TIMEOUT=300 bash scripts/ci-up.sh'
      }
    }

    stage('Dev – Deploy MI Composite Application') {
      steps {
        withCredentials([usernamePassword(
          credentialsId: 'jamii-dev-mi-creds',
          usernameVariable: 'MI_USERNAME',
          passwordVariable: 'MI_PASSWORD'
        )]) {
          sh """
            MI_HOST='${DEV_MI_HOST}' \
            MI_MGMT_PORT='${DEV_MI_MGMT_PORT}' \
            CAR_FILE='${env.CAR_FILE}' \
            bash scripts/deploy-mi.sh
          """
        }
      }
    }

    stage('Dev – Deploy APIM APIs') {
      steps {
        withCredentials([usernamePassword(
          credentialsId: 'jamii-dev-apim-creds',
          usernameVariable: 'APIM_USERNAME',
          passwordVariable: 'APIM_PASSWORD'
        )]) {
          sh """
            APIM_HOST='${DEV_APIM_HOST}' \
            APIM_HTTPS_PORT='${DEV_APIM_PORT}' \
            APIM_ENV_NAME='${DEV_APIM_ENV}' \
            PROJECT_ROOT='.' \
            bash scripts/deploy-apim.sh
          """
        }
      }
    }

    stage('Dev – Smoke Tests') {
      steps {
        sh """
          MI_HOST='${DEV_MI_HOST}' \
          MI_HTTP_PORT='${DEV_MI_HTTP_PORT}' \
          bash scripts/smoke-test.sh
        """
      }
    }

    stage('Prod – Manual Approval') {
      when {
        anyOf {
          branch 'main'
          branch 'master'
        }
      }
      steps {
        timeout(time: 60, unit: 'MINUTES') {
          input message: "Deploy jamii-integration ${env.ARTIFACT_VER} (${env.GIT_COMMIT?.take(8)}) to PRODUCTION?",
                ok: 'Deploy to Prod',
                submitter: 'release-approvers'
        }
      }
    }

    stage('Prod – Deploy MI Composite Application') {
      when {
        anyOf {
          branch 'main'
          branch 'master'
        }
      }
      steps {
        withCredentials([usernamePassword(
          credentialsId: 'jamii-prod-mi-creds',
          usernameVariable: 'MI_USERNAME',
          passwordVariable: 'MI_PASSWORD'
        )]) {
          sh """
            MI_HOST="\${PROD_MI_HOST}" \
            MI_MGMT_PORT="\${PROD_MI_MGMT_PORT:-9164}" \
            CAR_FILE='${env.CAR_FILE}' \
            bash scripts/deploy-mi.sh
          """
        }
      }
    }

    stage('Prod – Deploy APIM APIs') {
      when {
        anyOf {
          branch 'main'
          branch 'master'
        }
      }
      steps {
        withCredentials([usernamePassword(
          credentialsId: 'jamii-prod-apim-creds',
          usernameVariable: 'APIM_USERNAME',
          passwordVariable: 'APIM_PASSWORD'
        )]) {
          sh """
            APIM_HOST="\${PROD_APIM_HOST}" \
            APIM_HTTPS_PORT="\${PROD_APIM_PORT:-9443}" \
            APIM_ENV_NAME='prod' \
            PROJECT_ROOT='.' \
            bash scripts/deploy-apim.sh
          """
        }
      }
    }

  }

  post {
    always {
      sh 'bash scripts/ci-down.sh 2>/dev/null || true'
      sh 'rm -f deployment/car/*.car'
    }
    success {
      echo "Pipeline succeeded."
    }
    failure {
      echo "Pipeline FAILED. Check stage logs above."
    }
  }
}
