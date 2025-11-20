# 📘 Google Cloud 마이그레이션 실습 가이드

## 0. 환경 변수 설정 (공통)

터미널을 열 때마다 가장 먼저 실행해야 하는 필수 변수들입니다.

```bash
# [최초/재실행 공통] 프로젝트 및 리소스 설정
export PROJECT_ID="your-project-id"     # 본인의 프로젝트 ID로 변경
export REGION="asia-northeast3"         # 서울 리전
export ZONE="asia-northeast3-b"         # GPU/CPU 자원이 있는 존
export CLUSTER_NAME="llm-cluster"
export REPO_NAME="llm-repo"             # Docker 이미지 저장소 이름
export IMAGE_NAME="faiss-server"
export BUCKET_NAME="${PROJECT_ID}-model-data" # GCS 버킷 이름

# gcloud 기본 설정 적용
gcloud config set project $PROJECT_ID
gcloud config set compute/zone $ZONE

```

---

## 1. 영구 자산 준비 (최초 1회만 실행)

데이터와 이미지는 한 번 올려두면 클러스터를 삭제해도 사라지지 않습니다. **다음에 실습할 때는 이 단계를 건너뛰세요.**

### 1-1. 저장소 생성 및 데이터 업로드

```bash
# 1. Artifact Registry(이미지 저장소) 생성
gcloud artifacts repositories create $REPO_NAME \
    --repository-format=docker \
    --location=$REGION \
    --description="Docker repository for LLM project"

# 2. GCS 버킷(데이터 저장소) 생성
gcloud storage buckets create gs://${BUCKET_NAME} --location=$REGION

# 3. 데이터 업로드 (로컬 -> GCS)
# 로컬 프로젝트 루트에서 실행 가정
gcloud storage cp -r ./model_data/llm gs://${BUCKET_NAME}/
gcloud storage cp -r ./model_data/faiss_index gs://${BUCKET_NAME}/

```

### 1-2. Docker 이미지 빌드 및 푸시

```bash
# Docker 인증 설정
gcloud auth configure-docker ${REGION}-docker.pkg.dev

# 이미지 빌드 (M1/M2 맥 사용자 등을 위해 amd64 명시)
docker build --platform linux/amd64 -t ${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${IMAGE_NAME}:v1 .

# 이미지 업로드
docker push ${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${IMAGE_NAME}:v1

```

### 1-3. IAM 권한 설정 (Workload Identity 준비)

```bash
# 구글 서비스 계정(GSA) 생성
gcloud iam service-accounts create gke-faiss-sa --display-name="GKE Faiss Service Account"

# GSA에 스토리지 읽기 권한 부여
gcloud storage buckets add-iam-policy-binding gs://${BUCKET_NAME} \
    --member "serviceAccount:gke-faiss-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role "roles/storage.objectViewer"

# GSA와 K8s 계정(KSA) 연결 (Workload Identity Binding)
gcloud iam service-accounts add-iam-policy-binding gke-faiss-sa@${PROJECT_ID}.iam.gserviceaccount.com \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:${PROJECT_ID}.svc.id.goog[default/faiss-sa]"

```

---

## 2. 컴퓨팅 인프라 구축 (재실행 시 여기서부터 시작)

비용이 나가는 **GKE 클러스터**를 생성하는 단계입니다.

### 2-1. GKE 클러스터 생성 (CPU 모드)

```bash
# 1. 클러스터 생성 (가장 오래 걸림: 5~10분)
# --num-nodes 1: 최소 1대 시작
# Workload Identity 및 GCS Fuse 드라이버 활성화 필수
gcloud container clusters create $CLUSTER_NAME \
    --zone $ZONE \
    --num-nodes 1 \
    --machine-type e2-standard-4 \
    --disk-size 50 \
    --workload-pool=${PROJECT_ID}.svc.id.goog \
    --addons GcsFuseCsiDriver \
    --enable-autoscaling --min-nodes 1 --max-nodes 3

# 2. kubectl 인증 정보 가져오기
gcloud container clusters get-credentials $CLUSTER_NAME --zone $ZONE

# [확인] 노드가 정상적으로 떴는지 확인
kubectl get nodes

```

---

## 3. 애플리케이션 배포 (Deployment)

환경 변수, Probe 설정, HPA 정책이 모두 포함된 최종 YAML입니다.

### 3-1. 통합 Manifest 파일 생성 및 적용

```bash
# 아래 내용을 복사해서 실행하면 faiss-manifest.yaml 파일이 생성됩니다.
cat <<EOF > faiss-manifest.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: faiss-sa
  annotations:
    # GSA와 KSA 연결을 위한 주석
    iam.gke.io/gcp-service-account: gke-faiss-sa@${PROJECT_ID}.iam.gserviceaccount.com
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: faiss-config
data:
  # GCS가 마운트될 경로 (/data) 기준 설정
  BASE_INDEX_DIR: "/data/faiss_index"
  MODEL_DIR: "/data/llm/dragonkue-BGE-m3-ko-local"
  RERANKER_MODEL_DIR: "/data/llm/dragonkue-bge-reranker-v2-m3-ko-local"
  AVAILABLE_INDEXES: '["faiss_index_by_sentence_100","faiss_index_by_size_1000"]'
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: faiss-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: faiss-server
  template:
    metadata:
      labels:
        app: faiss-server
      annotations:
        gke-gcsfuse/volumes: "true" # GCS Fuse 활성화
    spec:
      serviceAccountName: faiss-sa
      containers:
      - name: faiss-server
        image: ${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${IMAGE_NAME}:v1
        resources:
          requests:
            memory: "2Gi"
            cpu: "1000m"
        envFrom:
        - configMapRef:
            name: faiss-config
        ports:
        - containerPort: 8000

        # [Probe 설정] 초기 로딩 20분 보호 + 트래픽 제어
        startupProbe:
          httpGet:
            path: /health
            port: 8000
          failureThreshold: 60
          periodSeconds: 20
        readinessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 10
          periodSeconds: 5
          successThreshold: 1
        livenessProbe:
          httpGet:
            path: /health
            port: 8000
          periodSeconds: 20
          failureThreshold: 5

        volumeMounts:
        - name: gcs-fuse-csi-ephemeral
          mountPath: /data
          readOnly: true
      volumes:
      - name: gcs-fuse-csi-ephemeral
        csi:
          driver: gcsfuse.csi.storage.gke.io
          volumeAttributes:
            bucketName: ${BUCKET_NAME}
            mountOptions: "implicit-dirs"
---
apiVersion: v1
kind: Service
metadata:
  name: faiss-service
spec:
  selector:
    app: faiss-server
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8000
  type: LoadBalancer
---
# [HPA 고급 설정] 초기 로딩 시 CPU 튀는 것 방지 (Damping)
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: faiss-server
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: faiss-server
  minReplicas: 1
  maxReplicas: 3
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
  behavior:
    scaleUp:
      policies:
      - type: Pods
        value: 1          # 한 번에 최대 1개만 추가
        periodSeconds: 60 # 1분 간격으로 제한
    scaleDown:
      policies:
      - type: Pods
        value: 1
        periodSeconds: 60
EOF

# 생성된 Manifest 적용
kubectl apply -f faiss-manifest.yaml

# Manifest로 생성한 deployment를 삭제하는 명령어
kubectl delete deployment faiss-server

```

---

## 4. 검증 및 모니터링 (Verification)

### 4-1. 배포 상태 확인

```bash
# Pod 생성 관련 이벤트 확인
kubectl describe pod $(kubectl get pods -l app=faiss-server -o jsonpath='{.items[0].metadata.name}')

# Pod 생성 확인 (초기엔 Init이나 ContainerCreating)
kubectl get pods -w

# [중요] 로그 확인 (인덱스 로딩 확인)
# Pod 이름 자동 추출하여 로그 보기
kubectl logs -f $(kubectl get pods -l app=faiss-server -o jsonpath='{.items[0].metadata.name}') -c faiss-server

```

- *성공 기준:* "Loading index..." 메시지 후 "Application startup complete"가 떠야 함.

### 4-2. 서비스 접속 테스트

```bash
# External IP 확인
kubectl get svc faiss-service

# IP를 변수에 저장 (직접 복사해도 됨)
export SERVICE_IP=$(kubectl get svc faiss-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Health Check
curl http://${SERVICE_IP}/health

# 실제 벡터 검색 요청
curl -X POST "http://${SERVICE_IP}/faiss_index_by_sentence_100/keyword_search" \
  -H "Content-Type: application/json" \
  -d '{"query": "장기출장", "k": 10}'

```

### 4-3. 리소스 사용량 및 HPA 확인

```bash
# 현재 파드들의 CPU 사용량 확인
kubectl top pods

# HPA 상태 확인 (TARGETS %, REPLICAS 수)
kubectl get hpa

# 클러스터(또는 네임스페이스)에서 발생한 모든 이벤트를 시간 순서대로 확인. 전체적인 흐름 확인용.
kubectl get events --sort-by='.lastTimestamp'

# HPA(오토스케일러)인 faiss-server의 이벤트를 확인하는 용도.
kubectl describe hpa faiss-server
```

---

## 5. 실습 종료 및 비용 방지 (Cleanup)

**실습이 끝나면 반드시 이 명령어를 실행하세요.** GKE 클러스터를 삭제하여 컴퓨팅 비용 발생을 막습니다.

```bash
# 1. GKE 클러스터 삭제 (가장 중요 - 과금 폭탄 방지)
gcloud container clusters delete $CLUSTER_NAME --zone $ZONE --quiet

# 2. (선택) 로컬의 YAML 파일 정리
rm faiss-manifest.yaml

```

> 참고: GCS 버킷(데이터)과 Artifact Registry(이미지)는 삭제하지 않았으므로 소량의 스토리지 비용(월 몇백 원 수준)이 발생할 수 있습니다. 완전 삭제를 원하시면 gcloud storage buckets delete gs://${BUCKET_NAME} 등을 수행하세요.
> 

---

## 🔄 재실행 시 (Resuming)

다시 실습하고 싶을 때는 이것만 수행하세요:

1. **[0. 환경 변수 설정]** 실행
2. **[2. 컴퓨팅 인프라 구축]** 실행
3. **[3. 애플리케이션 배포]** 실행