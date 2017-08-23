#!/bin/bash
set -e

function logInToPaas() {
    local cfUsername="${CF_USERNAME}"
    local cfPassword="${CF_PASSWORD}"
    local cfOrg="${CF_ORG}"
    local cfSpace="${CF_SPACE}"
    local apiUrl="${CF_API:-api.run.pivotal.io}"
    local CF_INSTALLED="$( cf --version || echo "false" )"
    local CF_DOWNLOADED="$( test -r cf && echo "true" || echo "false" )"
    echo "CF Installed? [${CF_INSTALLED}], CF Downloaded? [${CF_DOWNLOADED}]"
    if [[ ${CF_INSTALLED} == "false" && ${CF_DOWNLOADED} == "false" ]]; then
        echo "Downloading Cloud Foundry"
        curl -L "https://cli.run.pivotal.io/stable?release=linux64-binary&source=github" --fail | tar -zx
        CF_DOWNLOADED="true"
    else
        echo "CF is already installed"
    fi

    if [[ ${CF_DOWNLOADED} == "true" ]]; then
        echo "Adding CF to PATH"
        PATH=${PATH}:`pwd`
        chmod +x cf
    fi

    echo "Cloud foundry version"
    cf --version

    echo "Logging in to CF to org [${cfOrg}], space [${cfSpace}]"
    if [[ "${cfUsername}" != "" ]]; then
        cf api --skip-ssl-validation "${apiUrl}"
        cf login -u "${cfUsername}" -p "${cfPassword}" -o "${cfOrg}" -s "${cfSpace}"
    else
        cf target -o "${cfOrg}" -s "${cfSpace}"
    fi

}

function whichAppIsServingProduction() {
    local blueName=${1}
    local greenName=${2}
    local route=${3}
    local green="$( cf app "${greenName}" | grep routes | grep "${route}" && echo "green" || echo "" )"
    local blue="$( cf app "${blueName}" | grep routes | grep "${route}" && echo "blue" || echo "" )"
    local tailedGreen="$( echo "${green}" | tail -1 )"
    local tailedBlue="$( echo "${blue}" | tail -1 )"
    if [[ "${tailedGreen}" == "green" ]]; then
        echo "green"
    elif [[ "${tailedBlue}" == "blue" ]]; then
        echo "blue"
    else
        echo "none"
    fi
}

function pushApp() {
    local appName=${1}
    local hostname=${2}
    local memory=${3:-}
    local jarLocation=${JAR_LOCATION}
    echo "Pushing app [${appName}] with jar location [${jarLocation}], memory [${memory}] and hostname [${hostname}]"
    if [[ "${memory}" != "" ]]; then
        cf push "${appName}" -p "${jarLocation}" -m "${memory}" -n "${hostname}"
    else
        cf push "${appName}" -p "${jarLocation}" -n "${hostname}"
    fi
}

function scaleApp() {
    local appName=${1}
    local instances=${2}
    local memory=${3:-}
    echo "Scaling app [${appName}] with instances [${instances}] and memory [${memory}]"
    if [[ "${memory}" != "" ]]; then
        yes | cf scale "${appName}" -i "${instances}" -m "${memory}" || echo "Failed to scale the app. Continuing with the script"
    else
        yes | cf scale "${appName}" -i "${instances}" || echo "Failed to scale the app. Continuing with the script"
    fi
}

function startApp() {
    local appName=${1}
    echo "Starting application with name [${appName}]"
    cf start "${appName}"
}

function stopApp() {
    local appName=${1}
    echo "Stopping application with name [${appName}]"
    cf stop "${appName}"
}

function mapRoute() {
    local appName=${1}
    local hostname=${2}
    local domain=${3}
    yes | cf map-route "${appName}" "${domain}" --hostname ${hostname}
}


function unMapRoute() {
    local appName=${1}
    local hostname=${2}
    local domain=${3}
    yes | cf unmap-route "${appName}" "${domain}" --hostname ${hostname}
}

function deploy() {
    local oldAppName=${1}
    local newAppName=${2}
    local newHostname=${3}
    local domain="${DOMAIN_NAME}"
    local routedHostname="${ROUTED_HOSTNAME}"
    local oldAppInstances="${OLD_APP_INSTANCES}"
    local newAppInstances="${NEW_APP_INSTANCES}"
    local oldAppMemory="${OLD_APP_MEMORY}"
    local newAppMemory="${NEW_APP_MEMORY}"
    echo "Will deploy the app. Old app is [${oldAppName}], new app is [${newAppName}] with url [${newHostname}.${domain}]"
    pushApp "${newAppName}" "${newHostname}" "${newAppMemory}"
    scaleApp "${newAppName}" "${newAppInstances}" "${newAppMemory}"
    mapRoute "${newAppName}" "${routedHostname}" "${domain}"
    unMapRoute "${oldAppName}" "${routedHostname}" "${domain}"
    if [[ "${oldAppInstances}" == "0" ]]; then
        echo "[0] instances passed - will stop the old app with name [${oldAppName}]"
        stopApp "${oldAppName}"
    else
        scaleApp "${oldAppName}" "${oldAppInstances}" "${oldAppMemory}"
    fi
}

function rollback() {
    local brokenApp=${1}
    local rolledBackToAppName=${2}
    local newHostname=${3}
    local domain="${DOMAIN_NAME}"
    local routedHostname="${ROUTED_HOSTNAME}"
    local oldAppInstances="${OLD_APP_INSTANCES}"
    local newAppInstances="${NEW_APP_INSTANCES}"
    local oldAppMemory="${OLD_APP_MEMORY}"
    local newAppMemory="${NEW_APP_MEMORY}"
    echo "Will rollback the app. Current app is [${brokenApp}], the app to which we revert is [${rolledBackToAppName}] with url [${newHostname}.${domain}]"
    startApp "${rolledBackToAppName}"
    scaleApp "${rolledBackToAppName}" "${newAppInstances}" "${newAppMemory}"
    mapRoute "${rolledBackToAppName}" "${routedHostname}" "${domain}"
    unMapRoute "${brokenApp}" "${routedHostname}" "${domain}"
    scaleApp "${brokenApp}" "${oldAppInstances}" "${oldAppMemory}"
}

function print_usage() {
cat <<EOF

Performs blue / green deployment of an application to production.

>> ENVIRONMENTAL VARIABLES <<

[BLUE_APP_NAME]: The name of the blue instance. Defaults to (start-blue)
[GREEN_APP_NAME]: The name of the green instance. Defaults to (start-green)
[ROUTED_HOSTNAME]: The hostname to which the "production" traffic gets routed. Defaults to (start-staging)
[DOMAIN_NAME]: Domain of the deployed application. Defaults to (cfapps.io)
[JAR_LOCATION]: Location of the JAR to be deployed. Defaults to (initializr-service/target/initializr-service.jar)
[OLD_APP_INSTANCES]: Number of instances of the old instance. If you pass [0] then the old instance will get stopped. Defaults to (1)
[NEW_APP_INSTANCES]: Number of instances of the new instance. Defaults to (2)
[OLD_APP_MEMORY]: Memory to be used by the old instance. (OPTIONAL)
[NEW_APP_MEMORY]: Memory to be used by the new instance. (OPTIONAL)
[CF_USERNAME]: Will reuse your current logged in user if not provided. (OPTIONAL)
[CF_PASSWORD]: Will reuse your current logged in user if not provided. (OPTIONAL)
[CF_ORG]: Cloud Foundry organization to which you would like to deploy the application. (REQUIRED)
[CF_SPACE]: Cloud Foundry space to which you would like to deploy the application. (REQUIRED)
[CF_API]: Cloud Foundry API of the installation to which you would like to deploy the application. Defaults to (initializr-service/target/initializr-service.jar)

>> EXAMPLE OF USAGE (running locally on a logged in CF client) <<

$ BLUE_APP_NAME=marcin-blue GREEN_APP_NAME=marcin-green ROUTED_HOSTNAME=marcin-sample DOMAIN_NAME=cfapps.io \
JAR_LOCATION=target/marcin-sample-0.0.1-SNAPSHOT.jar OLD_APP_INSTANCES=1 NEW_APP_INSTANCES=2 OLD_APP_MEMORY=1024m \
NEW_APP_MEMORY=1024m CF_ORG=SomeOrg CF_SPACE=SomeSpace ./blueGreen.sh

>> AVAILABLE SWITCHES

-h | --help         - prints this help
-r | --rollback     - doesn't deploy but performs a rollback step instead

EOF
}

export BLUE_APP_NAME="${BLUE_APP_NAME:-start-blue}"
export BLUE_APP_ROUTE="${BLUE_APP_ROUTE:-${BLUE_APP_NAME:-start-blue}}"
export GREEN_APP_NAME="${GREEN_APP_NAME:-start-green}"
export ROUTED_HOSTNAME="${ROUTED_HOSTNAME:-start-staging}"
export DOMAIN_NAME="${DOMAIN_NAME:-cfapps.io}"
export JAR_LOCATION="${JAR_LOCATION:-initializr-service/target/initializr-service.jar}"
export OLD_APP_INSTANCES=${OLD_APP_INSTANCES:-1}
export NEW_APP_INSTANCES=${NEW_APP_INSTANCES:-2}
export OLD_APP_MEMORY=${OLD_APP_MEMORY:-}
export NEW_APP_MEMORY=${NEW_APP_MEMORY:-}
export CF_USERNAME=${CF_USERNAME:-}
export CF_PASSWORD=${CF_PASSWORD:-}
export CF_ORG=${CF_ORG:-}
export CF_SPACE=${CF_SPACE:-}
export CF_API=${CF_API:-api.run.pivotal.io}
export ROLLBACK=${ROLLBACK:-false}

if [[ "${CF_ORG}" == "" ]]; then
    echo "REQUIRED ENV VAR NOT FOUND!!"
    echo "[CF_ORG] env var not passed!"
    print_usage
    exit 1
fi

if [[ "${CF_SPACE}" == "" ]]; then
    echo "REQUIRED ENV VAR NOT FOUND!!"
    echo "[CF_SPACE] env var not passed!"
    print_usage
    exit 1
fi

while [[ $# > 0 ]]
do
key="$1"
case ${key} in
    -r|--rollback)
    ROLLBACK="true"
    ;;
    -h|--help)
    print_usage
    exit 0
    ;;
esac
shift # past argument or value
done

if [[ "${ROLLBACK}" == "true" ]]; then

    cat <<'EOF'
  ___  ___  _    _    ___   _   ___ _  __
 | _ \/ _ \| |  | |  | _ ) /_\ / __| |/ /
 |   | (_) | |__| |__| _ \/ _ | (__| ' <
 |_|_\\___/|____|____|___/_/ \_\___|_|\_\

EOF

else

    cat <<'EOF'
  ___  ___ ___ _    _____   __
 |   \| __| _ | |  / _ \ \ / /
 | |) | _||  _| |_| (_) \ V /
 |___/|___|_| |____\___/ |_|

EOF

fi

logInToPaas
runningApp=$( whichAppIsServingProduction "${BLUE_APP_NAME}" "${GREEN_APP_NAME}" "${ROUTED_HOSTNAME}.${DOMAIN_NAME}" )
echo "Found the following application running on production [${runningApp}]"
case ${runningApp} in
    blue)
        if [[ "${ROLLBACK}" == "true" ]]; then
            rollback "${BLUE_APP_NAME}" "${GREEN_APP_NAME}" "${GREEN_APP_NAME}"
        else
            deploy "${BLUE_APP_NAME}" "${GREEN_APP_NAME}" "${GREEN_APP_NAME}"
        fi
    ;;
    *)
        if [[ "${ROLLBACK}" == "true" ]]; then
            rollback "${GREEN_APP_NAME}" "${BLUE_APP_NAME}" "${BLUE_APP_NAME}"
        else
            deploy "${GREEN_APP_NAME}" "${BLUE_APP_NAME}" "${BLUE_APP_NAME}"
        fi
    ;;
esac
