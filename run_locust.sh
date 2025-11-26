#!/bin/bash

# 인자 체크
if [ -z "$1" ]; then
  echo "Usage: $0 <SERVICE_IP>"
  exit 1
fi

SERVICE_IP=$1

echo "Running locust load test against http://$SERVICE_IP ..."

locust -f locustfile.py --headless \
  --host http://$SERVICE_IP \
  --csv=faiss_load_test_result \
  --html=faiss_load_test_report.html
