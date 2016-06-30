package io.springframework.cloud.e2e

import io.springframework.cloud.common.SpringCloudJobs
import io.springframework.cloud.common.SpringCloudNotification
import io.springframework.common.*
import javaposse.jobdsl.dsl.DslFactory

/**
 * @author Marcin Grzejszczak
 */
class CloudFoundryBreweryTestExecutor implements SpringCloudNotification, TestPublisher, JdkConfig, BreweryDefaults,
		CloudFoundry, Cron, SpringCloudJobs {

	private final DslFactory dsl

	CloudFoundryBreweryTestExecutor(DslFactory dsl) {
		this.dsl = dsl
	}

	void buildBreweryForDocsTests() {
		// Run acceptance tests - skip building, deploying to CF, add docsbrewing prefix to CF
		build('spring-cloud-brewery-for-docs-tests', 'spring-cloud-samples',
				'brewery', "runAcceptanceTests.sh -t SLEUTH_STREAM -c -p docsbrewing -s -d", everyThreeHours())
	}

	protected void build(String description, String githubOrg, String projectName, String script, String cronExpr) {
		dsl.job("${description}-on-cf-e2e") {
			triggers {
				cron cronExpr
			}
			jdk jdk8()
			wrappers {
				environmentVariables([
						TEST_ZIPKIN_DEPENDENCIES: 'false',
				])
			}
			scm {
				git {
					remote {
						url "https://github.com/$githubOrg/$projectName"
						branch 'master'
					}
					extensions {
						wipeOutWorkspace()
					}
				}
			}
			wrappers {
				maskPasswords()
			}
			steps {
				shell(cleanup())
				shell(cfScriptToExecute(script))
			}
			configure {
				appendSlackNotificationForSpringCloud(it as Node)
			}
			publishers {
				archiveArtifacts acceptanceTestReports()
				archiveArtifacts {
					pattern acceptanceTestSpockReports()
					allowEmpty()
				}
			}
		}
	}

}
