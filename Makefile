REGISTRY_NAME?=docker.io/hashicorp
IMAGE_NAME=vault-k8s
VERSION?=0.0.0-dev
IMAGE_TAG?=$(REGISTRY_NAME)/$(IMAGE_NAME):$(VERSION)
PUBLISH_LOCATION?=https://releases.hashicorp.com
DOCKER_DIR=./build/docker
BUILD_DIR=dist
GOOS?=linux
GOARCH?=amd64
BIN_NAME=$(IMAGE_NAME)
GOFMT_FILES?=$$(find . -name '*.go' | grep -v vendor)
XC_PUBLISH?=
PKG=github.com/hashicorp/vault-k8s/version
LDFLAGS?="-X '$(PKG).Version=v$(VERSION)'"
TESTARGS ?= '-test.v'

HELM_CHART_VERSION ?= 0.25.0

.PHONY: all test build image clean version deploy
all: build

version:
	@echo $(VERSION)

build:
	CGO_ENABLED=0 GOOS=$(GOOS) GOARCH=$(GOARCH) go build \
		-ldflags $(LDFLAGS) \
		-o $(BUILD_DIR)/$(BIN_NAME) \
		.

image: build
	docker build --build-arg VERSION=$(VERSION) --no-cache -t $(IMAGE_TAG) .

deploy: image
	kind load docker-image hashicorp/vault-k8s:$(VERSION)
	helm upgrade --install vault vault --repo https://helm.releases.hashicorp.com --version=$(HELM_CHART_VERSION) \
		--wait --timeout=5m \
		--set 'server.dev.enabled=true' \
		--set 'server.logLevel=debug' \
		--set 'injector.image.tag=$(VERSION)' \
		--set 'injector.image.pullPolicy=Never' \
		--set 'injector.affinity=null' \
		--set 'injector.annotations.deployed=unix-$(shell date +%s)'

test-app-image:
	docker build test-app/ -t test-app
	kind load docker-image test-app

exercise:
	kubectl wait --for=condition=Ready pod/vault-0
	# insert a secret
	kubectl exec vault-0 -- vault kv put secret/test-app user=hello password=world
	# set up k8s auth
	kubectl exec vault-0 -- vault auth enable kubernetes || true
	kubectl exec vault-0 -- sh -c 'vault write auth/kubernetes/config kubernetes_host="https://$$KUBERNETES_PORT_443_TCP_ADDR:443"'
	kubectl exec vault-0 -- vault write auth/kubernetes/role/test-app \
		bound_service_account_names=test-app-sa \
		bound_service_account_namespaces=default \
		policies=test-app
	# vault policy
	echo 'path "secret/data/*" { capabilities = ["read"] }' | kubectl exec -i vault-0 -- vault policy write test-app -
	# service account
	kubectl create serviceaccount test-app-sa || true
	# clean up
	kubectl delete pod test-app --ignore-not-found
	# set up test-app with annotations to pull from 
	kubectl run test-app \
		--image="test-app" \
		--image-pull-policy="IfNotPresent" \
		--annotations="vault.hashicorp.com/role=test-app" \
		--annotations="vault.hashicorp.com/template-static-secret-render-interval=5s" \
		--annotations="vault.hashicorp.com/agent-inject=true" \
		--annotations="vault.hashicorp.com/agent-inject-direct=true" \
		--annotations="vault.hashicorp.com/agent-inject-secret-test-user=secret/data/test-app#.Data.data.user" \
		--annotations="vault.hashicorp.com/agent-inject-as-env-test-user=TEST_USER" \
		--annotations="vault.hashicorp.com/agent-inject-secret-test-password=secret/data/test-app#.Data.data.password" \
		--annotations="vault.hashicorp.com/agent-inject-as-env-test-password=TEST_PASSWORD" \
		--overrides='{ "apiVersion": "v1", "spec": { "serviceAccountName": "test-app-sa" } }'
	# port-forward to the test-app
	kubectl wait --for=condition=Ready pod/test-app
	kubectl port-forward test-app 7777:7777

clean:
	-rm -rf $(BUILD_DIR)

test: unit-test

unit-test:
	go test -race $(TESTARGS) ./...

.PHONY: mod
mod:
	go mod tidy

fmt:
	gofmt -w $(GOFMT_FILES)
