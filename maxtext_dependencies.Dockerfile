# Use Python 3.10 as the base image
FROM python:3.10-slim-bullseye

# Install system dependencies Git, and numactl
RUN apt-get update && apt-get install -y curl gnupg git numactl

# Install dependencies for adjusting network rto
RUN apt-get update && apt-get install -y iproute2 ethtool lsof

# Install the Google Cloud SDK
RUN curl -sSL https://sdk.cloud.google.com | bash

# Set the default Python version to 3.10
RUN update-alternatives --install /usr/bin/python3 python3 /usr/local/bin/python3.10 1

# Set environment variables for Google Cloud SDK and Python 3.10
ENV PATH="/usr/local/google-cloud-sdk/bin:/usr/local/bin/python3.10:${PATH}"

ARG MODE
ENV ENV_MODE=$MODE

ARG JAX_VERSION
ENV ENV_JAX_VERSION=$JAX_VERSION

ARG LIBTPU_GCS_PATH
ENV ENV_LIBTPU_GCS_PATH=$LIBTPU_GCS_PATH

ARG DEVICE
ENV ENV_DEVICE=$DEVICE

RUN mkdir -p /deps

# Set the working directory in the container
WORKDIR /deps

# Copy all files from local workspace into docker container
COPY . .
RUN ls .

RUN echo "Running command: bash setup.sh MODE=$ENV_MODE JAX_VERSION=$ENV_JAX_VERSION LIBTPU_GCS_PATH=${ENV_LIBTPU_GCS_PATH} DEVICE=${ENV_DEVICE}"
RUN bash setup.sh MODE=${ENV_MODE} JAX_VERSION=${ENV_JAX_VERSION} LIBTPU_GCS_PATH=${ENV_LIBTPU_GCS_PATH} DEVICE=${ENV_DEVICE}

WORKDIR /app