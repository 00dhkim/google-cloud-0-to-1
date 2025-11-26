#!/bin/bash

# HPA 상태와 Pod 상태를 2초마다 갱신하며 관찰
watch -n 2 "kubectl get hpa faiss-server; echo '---'; kubectl get pods -l app=faiss-server -o wide"
