package org.springframework.jenkins.springio.ci

import javaposse.jobdsl.dsl.DslFactory

import org.springframework.jenkins.common.job.BashCloudFoundry
import org.springframework.jenkins.common.job.Cron
import org.springframework.jenkins.common.job.JdkConfig
import org.springframework.jenkins.common.job.Maven
import org.springframework.jenkins.common.job.Pipeline
import org.springframework.jenkins.common.job.SlackPlugin
import org.springframework.jenkins.common.job.TestPublisher
import org.springframework.jenkins.springio.common.AllSpringIoJobs
import org.springframework.jenkins.springio.common.SpringIoJobs
import org.springframework.jenkins.springio.common.SpringIoNotification

/**
 * @author Marcin Grzejszczak
 */
class SpringStarterRollbackBuildMaker implements SpringIoNotification, JdkConfig, TestPublisher,
		Cron, SpringIoJobs, Pipeline, Maven, BashCloudFoundry {
	private final DslFactory dsl
	private final String scriptsDir
	private final String organization
	private final String branchName
	private final Map<String, String> variables

    SpringStarterRollbackBuildMaker(DslFactory dsl, String scriptsDir, Map<String, String> variables) {
		this.dsl = dsl
		this.organization = 'spring-io'
		this.branchName = 'master'
		this.scriptsDir = scriptsDir
		this.variables = variables
	}

	void deploy() {
		dsl.job(jobName()) {
			deliveryPipelineConfiguration('Rollback', 'Rollback to previous instance')
			wrappers {
				defaultDeliveryPipelineVersion()
				credentialsBinding {
					usernamePassword('CF_USERNAME', 'CF_PASSWORD', cfCredentialsId())
				}
				environmentVariables(PipelineDefaults.envVars(variables)) {
					env("ROLLBACK", "true")
				}
				colorizeOutput()
			}
			jdk jdk8()
			scm {
				git {
					remote {
						url "https://github.com/${organization}/initializr"
						branch branchName
					}
				}
			}
			steps {
				shell("""#!/bin/bash
				set -e
				
				${dsl.readFileFromWorkspace(scriptsDir + '/blueGreen.sh')}
				""")
			}
			configure {
				SlackPlugin.slackNotification(it as Node) {
					room(springRoom())
					notifySuccess(true)
				}
			}
		}
	}

	static String jobName() {
		return "${AllSpringIoJobs.getInitializrName()}-rollback"
	}
}
