# Jenkins do lab: LTS + ferramentas usadas pelo Jenkinsfile (docker CLI, kubectl, kind, trivy, sonar-scanner, python).
FROM jenkins/jenkins:2.580.2-lts-jdk21
USER root
ARG DOCKER_VERSION=29.1.3
ARG KUBECTL_VERSION=v1.37.2
ARG KIND_VERSION=v0.33.0
ARG TRIVY_VERSION=0.76.1
ARG SONAR_SCANNER_VERSION=8.3.1.16491
RUN apt-get update && apt-get install -y --no-install-recommends python3 python3-venv python3-pip curl unzip ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz | tar -xz -C /usr/local/bin --strip-components=1 docker/docker \
 && curl -fsSLo /usr/local/bin/kubectl https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl \
 && curl -fsSLo /usr/local/bin/kind https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64 \
 && chmod +x /usr/local/bin/kubectl /usr/local/bin/kind \
 && curl -fsSL https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz | tar -xz -C /usr/local/bin trivy \
 && curl -fsSLo /tmp/ss.zip https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux-x64.zip \
 && unzip -q /tmp/ss.zip -d /opt && ln -s /opt/sonar-scanner-*/bin/sonar-scanner /usr/local/bin/sonar-scanner && rm /tmp/ss.zip \
 && git config --system --add safe.directory '*'
USER jenkins
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
COPY casc.yaml /usr/share/jenkins/ref/casc.yaml
ENV CASC_JENKINS_CONFIG=/usr/share/jenkins/ref/casc.yaml \
    JAVA_OPTS="-Djenkins.install.runSetupWizard=false -Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true -Xmx512m"
