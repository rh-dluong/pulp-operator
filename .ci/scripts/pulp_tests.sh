#!/usr/bin/env bash
# coding=utf-8
set -euo pipefail

KUBE="k3s"
SERVER=$(hostname)
WEB_PORT="24817"
if [[ "$INGRESS_TYPE" == "ingress" ]]; then
  SERVER=ingress.local
  echo $(minikube ip) ingress.local | sudo tee -a /etc/hosts
elif [[ "${1-}" == "--minikube" ]] || [[ "${1-}" == "-m" ]]; then
  KUBE="minikube"
  SERVER="localhost"
  if [[ "$CI_TEST" == "true" ]]; then
    SVC_NAME="example-pulp-web-svc"
    WEB_PORT="24880"
    API_SVC="example-pulp-api-svc"
    API_PORT="24817"
    kubectl port-forward service/$SVC_NAME $WEB_PORT:$WEB_PORT &
    kubectl port-forward service/$API_SVC $API_PORT:$API_PORT &
    echo 127.0.0.1   example-pulp-web-svc.pulp-operator-system.svc.cluster.local example-pulp-api-svc.pulp-operator-system.svc.cluster.local| sudo tee -a /etc/hosts
  fi
fi

# From the pulp-server/pulp-api config-map
echo "machine $SERVER
login admin
password password\
" > ~/.netrc

if [[ "$INGRESS_TYPE" == "ingress" ]]; then
    export BASE_ADDR="http://$SERVER"
else
    export BASE_ADDR="http://$SERVER:$WEB_PORT"
fi
echo $BASE_ADDR


# Use latest release of pulp-cli to avoid issues with non-released dependencies
# https://github.com/pulp/pulp-operator/actions/runs/4238998943/jobs/7366637198#step:15:37
pip install pulp-cli

if [ ! -f ~/.config/pulp/settings.toml ]; then
  echo "Configuring pulp-cli"
  mkdir -p ~/.config/pulp
  cat > ~/.config/pulp/cli.toml << EOF
[cli]
base_url = "$BASE_ADDR"
verify_ssl = false
format = "json"
EOF
fi

cat ~/.config/pulp/cli.toml | tee ~/.config/pulp/settings.toml

pulp status | jq

pushd pulp_ansible/docs/_scripts
timeout 5m bash -x quickstart.sh || {
  YLATEST=$(git ls-remote --heads https://github.com/pulp/pulp_ansible.git | grep -o "[[:digit:]]\.[[:digit:]]*" | sort -V | tail -1)
  git fetch --depth=1 origin heads/$YLATEST:$YLATEST
  git checkout $YLATEST
  timeout 5m bash -x quickstart.sh
}
popd

pushd pulp_container/docs/_scripts
timeout 5m bash -x docs_check.sh || {
  YLATEST=$(git ls-remote --heads https://github.com/pulp/pulp_container.git | grep -o "[[:digit:]]\.[[:digit:]]*" | sort -V | tail -1)
  git fetch --depth=1 origin heads/$YLATEST:$YLATEST
  git checkout $YLATEST
  timeout 5m bash -x docs_check.sh
}
popd
