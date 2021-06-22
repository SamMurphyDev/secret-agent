
# Image URL to use all building/pushing image targets
IMG ?= controller:latest
VERSION=$(shell echo $(IMG) | awk -F ':' '{print $$2}')
# Produce CRDs that work back to Kubernetes 1.11 (no version conversion)
#CRD_OPTIONS ?= "crd:trivialVersions=false"
# This will work on kube versions 1.16+. We want the CRD OpenAPI validation features in v1
CRD_OPTIONS ?= "crd:crdVersions=v1"


# if GOBIN isn't set find the path, otherwise use GOBIN
ifeq ($(GOBIN),)
GOBIN=$(shell go env GOROOT)/bin
endif

GO=$(shell go env GOROOT)/bin/go

all: manager

# Run unit and integration tests (backwards compatability)
citest: int-test
	git status --untracked-files=no --porcelain
	if [ -n "$(shell git status --untracked-files=no --porcelain)" ]; then echo "There are uncommitted changes"; false; fi
	echo "Test successful"

# Run unit and integration tests (backwards compatability)
test tests: int-test

# Run unit tests
unit-test: generate fmt vet manifests
	$(GO) test ./... -coverprofile cover.html

# Run unit and integration tests
int-test: generate fmt vet manifests
	$(GO) test ./... -tags=integration -coverprofile cover.html

# Run unit and integration and cloudprovider tests
cloud-test: generate fmt vet manifests
	$(GO) test ./... -tags=integration,cloudprovider -coverprofile cover.html

# Build manager binary
manager: generate fmt vet
	$(GO) build -o bin/manager main.go

# debug
debug: generate fmt vet manifests
	dlv debug -- ./main.$(GO) --debug
# Run against the configured Kubernetes cluster in ~/.kube/config
run: generate fmt vet manifests
	$(GO) run ./main.go

# Install CRDs into a cluster
install: manifests
	kustomize build config/crd | kubectl apply -f -

# Uninstall CRDs from a cluster
uninstall: manifests
	kustomize build config/crd | kubectl delete -f -

# Deploy controller in the configured Kubernetes cluster in ~/.kube/config
deploy: manifests
	cd config/manager && kustomize edit set image controller=${IMG}
	kustomize build config/default | kubectl apply -f -

# Delete controller from the configured Kubernetes cluster in ~/.kube/config
clean: manifests
	kustomize build config/default | kubectl delete -f -

# Generate manifests e.g. CRD, RBAC etc.
manifests: controller-gen
	$(CONTROLLER_GEN) $(CRD_OPTIONS) rbac:roleName=manager-role webhook paths="./..." output:crd:artifacts:config=config/crd/bases
	# Remove "caBuncle: Cg==" from the webhook config. controller-gen generates the manifests with a placeholder
	awk '!/caBundle:/' config/webhook/manifests.yaml > t && mv t config/webhook/manifests.yaml

# Run $(GO) fmt against code
fmt:
	$(GO) fmt ./...

# Run $(GO) vet against code
vet:
	$(GO) version
	$(GO) vet ./...

# Generate code
generate: controller-gen
	$(CONTROLLER_GEN) object:headerFile="hack/boilerplate.go.txt" paths="./..."

# Build the docker image
docker-build: int-test
	docker build . -t ${IMG}

# Push the docker image
docker-push:
	docker push ${IMG}

# find or download controller-gen
# download controller-gen if necessary
controller-gen:
ifeq (, $(shell which controller-gen))
	@{ \
	set -e ;\
	CONTROLLER_GEN_TMP_DIR=$$(mktemp -d) ;\
	cd $$CONTROLLER_GEN_TMP_DIR ;\
	$(GO) mod init tmp ;\
	$(GO) get sigs.k8s.io/controller-tools/cmd/controller-gen@v0.6.1 ;\
	rm -rf $$CONTROLLER_GEN_TMP_DIR ;\
	}
CONTROLLER_GEN=$(GO)/controller-gen
else
CONTROLLER_GEN=$(shell which controller-gen)
endif
