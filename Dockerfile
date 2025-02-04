# For building forgerock/secret-agent:tagname

# Global build arguments
ARG GO_VERSION="1.14.4"
ARG GO_PACKAGE_SHA256="aed845e4185a0b2a3c3d5e1d0a35491702c55889192bb9c30e67a3de6849c067"
ARG KUBEBUILDER_VERSION="2.3.1"

FROM openjdk:11-jre-slim as tester

ARG GO_VERSION
ARG GO_PACKAGE_SHA256
ARG KUBEBUILDER_VERSION

ENV CGO_ENABLED=0 GOOS=linux GOARCH=amd64 DEBIAN_FRONTEND=noninteractive 
RUN apt-get update && \
    apt-get install --no-install-recommends -y curl git-core make && \
    apt-get clean all

RUN curl -LO https://dl.google.com/go/go${GO_VERSION}.linux-amd64.tar.gz && \
    SUM=$(sha256sum go${GO_VERSION}.linux-amd64.tar.gz | awk '{print $1}') && \
    if [ "${SUM}" != "${GO_PACKAGE_SHA256}" ]; then echo "Failed checksum"; exit 1; fi && \
    tar xf go${GO_VERSION}.linux-amd64.tar.gz && \
    chown -R root:root ./go && \
    mv go /usr/local && \
    rm go${GO_VERSION}.linux-amd64.tar.gz

RUN curl -L https://go.kubebuilder.io/dl/${KUBEBUILDER_VERSION}/${GOOS}/${GOARCH} | tar -xz -C /tmp/ && \
    mv /tmp/kubebuilder_${KUBEBUILDER_VERSION}_${GOOS}_${GOARCH} /usr/local/kubebuilder

ENV PATH="/usr/local/go/bin:${PATH}:/usr/local/kubebuilder/bin" GOPATH="/root/go"
WORKDIR /root/go/src/github.com/ForgeRock/secret-agent

CMD ["bash"]


# Build the manager binary
FROM golang:${GO_VERSION}-alpine as builder

WORKDIR /workspace
# Copy the Go Modules manifests
COPY go.mod go.sum ./
# cache deps before building and copying source so that we don't need to re-download as much
# and so that source changes don't invalidate our downloaded layer
RUN go mod download
# Copy the go source
COPY . .
# Build with "-s -w" linker flags to omit the symbol table, debug information and the DWARF table
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 GO111MODULE=on go build -ldflags "-s -w" -a -o manager main.go

# Use distroless as minimal base image to package the manager binary
# Refer to https://github.com/GoogleContainerTools/distroless for more details

# FROM gcr.io/distroless/static:nonroot
# WORKDIR /
# COPY --from=builder /workspace/manager .
# USER nonroot:nonroot

# ENTRYPOINT ["/manager"]



FROM openjdk:11-jre-slim as release

RUN apt-get update && \                                                                               
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y curl lsof net-tools && \ 
    apt-get clean all                                                                                 
RUN addgroup --gid 11111 secret-agent && \
    adduser --shell /bin/bash --home /home/secret-agent --uid 11111 --disabled-password --ingroup root --gecos secret-agent secret-agent && \
    chown -R secret-agent:root /home/secret-agent

WORKDIR /opt/gen
COPY --from=builder --chown=secret-agent:root /workspace/manager /

USER secret-agent

CMD ["bash"]

