// ─────────────────────────────────────────────────────────────────────────────
// Jamii Integration – Declarative Jenkins Pipeline
//
// Stages (all three APIs handled as one unit; any failure fails the pipeline):
//   1. Checkout
//   2. Build MI artifacts          (mvn clean install, produces .car)
//   3. Package APIM projects       (sync OpenAPI defs into apictl project dirs)
//   4. Run Synapse unit tests      (mvn test via synapse-unit-test-maven-plugin)
// ── DEV environment ──────────────────────────────────────────────────────────
//   5. Start dev environment       (docker-compose up)
//   6. Deploy MI composite app     (scripts/deploy-mi.sh)
//   7. Deploy APIM APIs            (scripts/deploy-apim.sh – all three)
//   8. Smoke tests                 (scripts/smoke-test.sh)
//   9. Stop dev environment        (always, even on failure)
// ── PROD promotion ───────────────────────────────────────────────────────────
//  10. Promote to prod             (manual gate + deploy to prod APIM/MI)
// ─────────────────────────────────────────────────────────────────────────────

pipeline {

  agent { label 'docker' }   // requires: docker, docker compose, java 17+, mvn, apictl, curl

  // ── Environment defaults (override via Jenkins Credentials / Manage Jenkins) ──
  environment {
    // Artifact metadata
    ARTIFACT_ID   = 'jamii-integration'
    ARTIFACT_VER  = '1.0.0'
    CAR_FILE      = "target/${ARTIFACT_ID}_${ARTIFACT_VER}.car"

    // ── Dev environment ───────────────────────────────────────────────────────
    DEV_MI_HOST       = 'localhost'
    DEV_MI_MGMT_PORT  = '9164'
    DEV_MI_HTTP_PORT  = '8290'
    DEV_APIM_HOST     = 'localhost'
    DEV_APIM_PORT     = '9443'
    DEV_APIM_ENV      = 'dev'

    // Credentials IDs configured in Jenkins → Manage Credentials:
    //   jamii-dev-mi-creds   → username/password  (MI admin)
    //   jamii-dev-apim-creds → username/password  (APIM admin)
    //   jamii-prod-mi-creds  → username/password  (prod MI admin)
    //   jamii-prod-apim-creds→ username/password  (prod APIM admin)
  }

  options {
    buildDiscarder(logRotator(numToKeepStr: '20'))
    timestamps()
    timeout(time: 45, unit: 'MINUTES')
    // Prevent concurrent runs that could race on the docker-compose ports
    disableConcurrentBuilds()
  }

  stages {

    // ─────────────────────────────────────────────────────────────────────────
    stage('Checkout') {
      steps {
        checkout scm
        echo "Building commit: ${env.GIT_COMMIT?.take(8) ?: 'unknown'}"
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    stage('Build MI Artifacts') {
      steps {
        sh 'mvn clean install -DskipTests -B'
        // Verify the CAR was produced
        script {
          def carExists = fileExists(env.CAR_FILE)
          if (!carExists) {
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

    // ─────────────────────────────────────────────────────────────────────────
    // Package APIM projects: copy the latest OpenAPI definitions into each
    // apictl project folder so they are in sync with what was just built.
    // ─────────────────────────────────────────────────────────────────────────
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
        // Archive the apictl project directories for traceability
        archiveArtifacts artifacts: 'apim/apis/**', allowEmptyArchive: true
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    stage('Run Synapse Unit Tests') {
      steps {
        // The synapse-unit-test-maven-plugin downloads and starts a local MI
        // server to execute unit tests defined in src/test/wso2mi/.
        // Skip if there are no test files (plugin handles maven.test.skip=true).
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
          // Publish JUnit-compatible results if the plugin produces them
          junit allowEmptyResults: true,
                testResults: 'target/surefire-reports/*.xml'
        }
      }
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  DEV ENVIRONMENT
    // ═════════════════════════════════════════════════════════════════════════

    stage('Dev – Start Environment') {
      steps {
        // Prepare deployment directory that the MI container volume-mounts
        sh 'mkdir -p deployment/car deployment/libs'
        sh "cp '${env.CAR_FILE}' deployment/car/"

        // Copy connector ZIPs from target/  (maven-dependency-plugin output)
        sh '''
          if ls deployment/libs/*.zip 1>/dev/null 2>&1; then
            echo "Connector ZIPs already in deployment/libs/"
          else
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
      // All three APIs are deployed in a single script invocation.
      // The script fails the stage (and the pipeline) if any one of them fails.
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

    // ═════════════════════════════════════════════════════════════════════════
    //  PROD PROMOTION  (manual input gate – only on main branch)
    // ═════════════════════════════════════════════════════════════════════════

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

  } // end stages

  // ── Post actions ───────────────────────────────────────────────────────────
  post {
    always {
      // Always tear down the dev docker-compose stack, even on failure
      sh 'bash scripts/ci-down.sh 2>/dev/null || true'

      // Clean up copied CAR from deployment dir so it isn't re-used by the
      // next build accidentally
      sh 'rm -f deployment/car/*.car'
    }
    success {
      echo "Pipeline succeeded. Artifacts archived and APIs deployed."
    }
    failure {
      echo "Pipeline FAILED. Check logs above for the failing stage."
    }
  }
}
