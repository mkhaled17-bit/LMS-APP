pipeline {
    agent any

    // 1. Dropdown menu to choose the action
    parameters {
        choice(name: 'ACTION', choices: ['apply', 'destroy'], description: 'Choose Action')
    }

    environment {
        AWS_DEFAULT_REGION = 'us-east-1'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Terraform Init') {
            steps {
                // We use 'awd-creds' here as requested
                withCredentials([usernamePassword(credentialsId: 'awd-creds', 
                                                  usernameVariable: 'AWS_ACCESS_KEY_ID', 
                                                  passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
                    sh 'terraform init'
                }
            }
        }

        // 2. This stage runs ONLY if you select 'apply'
        stage('Terraform Plan & Apply') {
            when {
                expression { params.ACTION == 'apply' }
            }
            steps {
                withCredentials([usernamePassword(credentialsId: 'awd-creds', 
                                                  usernameVariable: 'AWS_ACCESS_KEY_ID', 
                                                  passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
                    sh 'terraform plan'
                    sh 'terraform apply -auto-approve'
                }
            }
        }

        // 3. This stage runs ONLY if you select 'destroy'
        stage('Terraform Destroy') {
            when {
                expression { params.ACTION == 'destroy' }
            }
            steps {
                withCredentials([usernamePassword(credentialsId: 'awd-creds', 
                                                  usernameVariable: 'AWS_ACCESS_KEY_ID', 
                                                  passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
                    // The command to delete everything
                    sh 'terraform destroy -auto-approve'
                }
            }
        }
    }
}