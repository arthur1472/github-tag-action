FROM node:18-alpine
LABEL "repository"="https://github.com/anothrNick/github-tag-action"
LABEL "homepage"="https://github.com/anothrNick/github-tag-action"
LABEL "maintainer"="Nick Sjostrom"

RUN apk --no-cache add bash git curl jq openssh && npm install -g semver

COPY entrypoint.sh /entrypoint.sh
COPY ssh/ssh_config /etc/ssh/ssh_config
COPY ssh/ssh_config.d /etc/ssh/ssh_config.d

ENTRYPOINT ["/entrypoint.sh"]
