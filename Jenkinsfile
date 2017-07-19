pipeline {
	agent { dockerfile true }
	stages {
		stage('Build') {
			steps {
				parallel (
					"dmd": {
						ansiColor('xterm') {
							script {
								try {
									githubNotify context: "${env.JOB_NAME}-dmd", status: 'PENDING', description: "Building ${env.JOB_NAME}-dmd"
								} catch (Exception e) { }
							}

							sh '''
							dub upgrade
							dub build --compiler=dmd
							mv de de-dmd
							'''
							stash includes: 'de-dmd', name: 'dmd'
						}
					},

					"ldc": {
						ansiColor('xterm') {
							script {
								try {
									githubNotify context: "${env.JOB_NAME}-ldc", status: 'PENDING', description: "Building ${env.JOB_NAME}-ldc"
								} catch (Exception e) { }
							}

							sh '''
							dub upgrade
							dub build --compiler=ldc2
							mv de de-ldc
							'''
							stash includes: 'de-ldc', name: 'ldc'
						}
					}
				)
			}
			post {
				success {
					script {
						env.DMD_TEST_STATUS = 'SUCCESS';
						env.LDC_TEST_STATUS ='SUCCESS';
					}
				}
				failure {
					script {
						env.DMD_TEST_STATUS = 'FAILURE';
						env.LDC_TEST_STATUS ='FAILURE';
					}
				}
			}
		}

		stage('Test') {
			steps {
				parallel (
					"dmd": {
						ansiColor('xterm') {
							script {
								try {
									githubNotify context: "${env.JOB_NAME}-dmd", status: 'PENDING', description: "Testing ${env.JOB_NAME}-dmd"
								} catch (Exception e) { }
							}

							sh 'dub test --compiler=dmd'
						}

						script {
							env.DMD_TEST_STATUS = 'SUCCESS';
						}
					},

					"ldc": {
						ansiColor('xterm') {
							script {
								try {
									githubNotify context: "${env.JOB_NAME}-ldc", status: 'PENDING', description: "Testing ${env.JOB_NAME}-ldc"
								} catch (Exception e) { }
							}

							sh 'dub test --compiler=ldc2'
						}

						script {
							env.LDC_TEST_STATUS = 'SUCCESS';
						}
					}
				)
			}

			post {
				always {
					script {
						if (env.DMD_TEST_STATUS == null)
							env.DMD_TEST_STATUS = 'ERROR';

						if (env.LDC_TEST_STATUS == null)
							env.LDC_TEST_STATUS ='ERROR';
					}
				}
			}
		}

		stage('Archive') {
			steps {
				ansiColor('xterm') {
					script {
						try {
							githubNotify context: "${env.JOB_NAME}-dmd", status: 'PENDING', description: "Archiving ${env.JOB_NAME}-dmd"
							githubNotify context: "${env.JOB_NAME}-ldc", status: 'PENDING', description: "Archiving ${env.JOB_NAME}-ldc"
						} catch (Exception e) { }
					}

					unstash 'dmd'
					unstash 'ldc'
					archiveArtifacts artifacts: 'de-dmd,de-ldc', fingerprint: true
				}
			}
		}
	}

  post {
    always {
			script {
				try {
					if (env.DMD_TEST_STATUS == "SUCCESS")
						githubNotify context: "${env.JOB_NAME}-dmd", status: "${env.DMD_TEST_STATUS}", description: "${env.JOB_NAME}-dmd building successed"
					else if (env.DMD_TEST_STATUS == "ERROR")
						githubNotify context: "${env.JOB_NAME}-ldc", status: "${env.DMD_TEST_STATUS}", description: "${env.JOB_NAME}-dmd building successed BUT testing failed"
					else
						githubNotify context: "${env.JOB_NAME}-ldc", status: "${env.DMD_TEST_STATUS}", description: "${env.JOB_NAME}-dmd building failed"

					if (env.LDC_TEST_STATUS == "SUCCESS")
						githubNotify context: "${env.JOB_NAME}-ldc", status: "${env.LDC_TEST_STATUS}", description: "${env.JOB_NAME}-ldc building successed"
					else if (env.LDC_TEST_STATUS == "ERROR")
						githubNotify context: "${env.JOB_NAME}-ldc", status: "${env.LDC_TEST_STATUS}", description: "${env.JOB_NAME}-ldc building successed BUT testing failed"
					else
						githubNotify context: "${env.JOB_NAME}-ldc", status: "${env.LDC_TEST_STATUS}", description: "${env.JOB_NAME}-ldc building failed"
				} catch (Exception e) { }
			}
    }
  }
}
