#!/usr/bin/env bash
set -euo pipefail

# Deletes the entire kind cluster - the fastest possible teardown since there
# is nothing outside the cluster to clean up (no cloud resources, no billing
# implications, unlike terraform destroy in later phases).
kind delete cluster --name kubeforge
