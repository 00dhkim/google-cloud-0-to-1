#!/bin/bash

# This script tests the endpoints of the FAISS server.


# run faiss server
# 호스트에서 실행하면 config/faiss/.env를 인식하지 못하므로, 직접 환경변수를 주입함.
:<<'COMMENT'
cd faiss/
gunicorn app.main:app \
  -k uvicorn.workers.UvicornWorker \
  --bind 0.0.0.0:8000 \
  --env BASE_INDEX_DIR="../model_data/faiss_index" \
  --env MODEL_DIR="../model_data/llm/dragonkue-BGE-m3-ko-local" \
  --env RERANKER_MODEL_DIR="../model_data/llm/dragonkue-bge-reranker-v2-m3-ko-local" \
  --env AVAILABLE_INDEXES='["faiss_index_by_sentence_100_bmk","faiss_index_by_size_1000_bmk"]'
COMMENT

HOST="http://34.64.248.99"
INDEX_NAME="faiss_index_by_sentence_100"
# INDEX_NAME="faiss_index_by_size_1000"
# INDEX_NAME="faiss_index_by_sentence_100_bmk"
# INDEX_NAME="faiss_index_by_size_1000_bmk"
# QUERY="감사요령에 따른 감사자문위원회와 관련하여 외부위원의 비율은?" # 과반 (50%)
# QUERY="감사처분 처리기한과 관련하여, 신분상 징계 처분의 처리기한은?" # 1개월
# QUERY="공무국외출장의 귀국보고서를 생략할 수 있는 경우는?" # 10일 미만의 국제학술대회에 논문 발표자로 참석한 경우
# QUERY="공무국외출장의 출장자 중 임원이 포함되어 있는 경우, 무관동의가 필요한가?" # yes
# QUERY="여비규정에 따르면, 국외출장자가 숙박비를 할인정액으로 신청할 때 지급받는 숙박비는?" # 실비 상한액의 85% 지급
# QUERY="같은 지역 장기출장 중 일비가 감액되는 시점은 출장일로부터 며칠부터인가?" # 15일을 초과한 때에는 그 초과일수에 대하여 정액의 10분의 1을 감하여 지급한다.
# QUERY="연구개발망 전용 단말기에 프로그램 설치를 심의하는 대상은 누구인가?" # 연구개발망 보안심사위원회
QUERY="연구개발망의 인터넷 접속 로그의 보관 기한은?" # 3년 이상
# QUERY="핵심기술 사업에서 8천만원 규모의 신규장비 획득을 위한 집행계획 변경 시 전결자는?" # 사책/과책
# QUERY="4억원 규모의 구매 계약요구 시 전결권자는?" # 사업기구장
# QUERY="연구소 재직 중 연구소의 추천으로 공무원 신분을 취득한 후, 공무원을 퇴직한 경우 3개월 이내에 특별채용의 기회가 있나요?" # yes
# QUERY="부서장의 직무대행기간은 최대 몇개월까지 가능한가요?" # 6개월
# QUERY="근속 3년 이상 ~ 5년 미만인 직원에게 부여되는 기본 연차휴가와 가산 연차는 각각 몇 일인가요?" # 기본연차 15일과 가산연차 1일
# QUERY="쌍둥이를 임신한 경우에 부여되는 출산휴가의 일수는?" # 120일


# 1. Vector Search
echo "--- Testing Vector Search ---"
curl -X POST "$HOST/$INDEX_NAME/vector_search" \
  -H "Content-Type: application/json" \
  -d "{
     \"query\": \"$QUERY\",
     \"k\": 10,
     \"threshold\": 0.5,
     \"diversity\": false,
     \"diversity_k\": 2
      }"
echo -e "\n"

# 2. Keyword Search
echo "--- Testing Keyword Search ---"
curl -X POST "$HOST/$INDEX_NAME/keyword_search" \
  -H "Content-Type: application/json" \
  -d "{
     \"query\": \"$QUERY\",
     \"k\": 10
      }"
echo -e "\n"

# 3. Rerank
echo "--- Testing Rerank ---"
DOCUMENTS='[
    {
        "title": "연구개발용 인터넷 운용 및 관리 요령(2025년도 4월 10일 제정)",
        "content": "연구ㆍ개발용 인터넷망(이하 ‘연구개발망’이라 한다)이라 함은 인공지능 학습 및 데이터 활용 등 연구 여건을 보장하기 위한 상용 인터넷으로서 인트라넷(이하 ‘소내망’이라 한다), 업무용 인터넷(이하 ‘인터넷망’이라 한다) 및 국방망과 물리적으로 분리되는 인터넷을 말한다",
        "hash": "700b1cf4108149a6718c19e911fd1215c0ae95ed47c12c038437299f572ccb20",
        "score": 0.7426729798316956,
        "_score_vector": 0.7426729798316956,
        "_rank_vector": 10
    },
    {
        "title": "연구개발용 인터넷 운용 및 관리 요령(2025년도 4월 10일 제정)",
        "content": "② 연구개발망운용부서장은 연구개발망을 보호하기 위해 연구소 보안정책에 따라 접속 가능한 사이트 및 설치 가능한 프로그램 목록을 관리한다.",
        "hash": "700b1cf4108149a6718c19e911fd1215c0ae95ed47c12c038437299f572ccb20",
        "score": 0.741437703371048,
        "_score_vector": 0.741437703371048,
        "_rank_vector": 9
    },
    {
        "title": "연구개발용 인터넷 운용 및 관리 요령(2025년도 4월 10일 제정)",
        "content": "연구개발망 접속 사이트 차단해제 및 프로그램 설치 신청(00원 00부)",
        "hash": "700b1cf4108149a6718c19e911fd1215c0ae95ed47c12c038437299f572ccb20",
        "score": 0.7384727597236633,
        "_score_vector": 0.7384727597236633,
        "_rank_vector": 8
    },
    {
        "title": "연구개발용 인터넷 운용 및 관리 요령(2025년도 4월 10일 제정)",
        "content": "나. 연구개발망 보안 및 유해사이트 통제 정책 수립, 정책 적용 및 관리",
        "hash": "700b1cf4108149a6718c19e911fd1215c0ae95ed47c12c038437299f572ccb20",
        "score": 0.7328095138072968,
        "_score_vector": 0.7328095138072968,
        "_rank_vector": 7
    },
    {
        "title": "연구개발용 인터넷 운용 및 관리 요령(2025년도 4월 10일 제정)",
        "content": "5. 연구개발망 운용부서장은 심의ㆍ승인 사항에 대하여 익월 14일까지 보안 담당부서로 통보하여야 한다.",
        "hash": "700b1cf4108149a6718c19e911fd1215c0ae95ed47c12c038437299f572ccb20",
        "score": 0.731753408908844,
        "_score_vector": 0.731753408908844,
        "_rank_vector": 6
    },
    {
        "title": "연구개발용 인터넷 운용 및 관리 요령(2025년도 4월 10일 제정)",
        "content": "연구개발망 설치장소에 출입증 태깅 시스템이 갖추어진 곳은 전자기록으로 사용자 현황을 관리·유지할 수 있으며, 그렇지 아니한 경우에는 수기 출입대장[별지 제1호 서식]을 유지하여야 한다.",
        "hash": "700b1cf4108149a6718c19e911fd1215c0ae95ed47c12c038437299f572ccb20",
        "score": 0.7243528068065643,
        "_score_vector": 0.7243528068065643,
        "_rank_vector": 5
    },
    {
        "title": "연구개발용 인터넷 운용 및 관리 요령(2025년도 4월 10일 제정)",
        "content": "⑤ 연구개발망 운영부서는 위원회의 의사록 등 기록을 유지하여야 한다.",
        "hash": "700b1cf4108149a6718c19e911fd1215c0ae95ed47c12c038437299f572ccb20",
        "score": 0.7155337035655975,
        "_score_vector": 0.7155337035655975,
        "_rank_vector": 4
    },
    {
        "title": "연구개발용 인터넷 운용 및 관리 요령(2025년도 4월 10일 제정)",
        "content": "마. 연구개발망 네트워크 및 정보보호체계 보안 관리",
        "hash": "700b1cf4108149a6718c19e911fd1215c0ae95ed47c12c038437299f572ccb20",
        "score": 0.7116822600364685,
        "_score_vector": 0.7116822600364685,
        "_rank_vector": 3
    },
    {
        "title": "연구개발용 인터넷 운용 및 관리 요령(2025년도 4월 10일 제정)",
        "content": "연구ㆍ개발용 인터넷 운용 및 관리 요령",
        "hash": "700b1cf4108149a6718c19e911fd1215c0ae95ed47c12c038437299f572ccb20",
        "score": 0.6894233524799347,
        "_score_vector": 0.6894233524799347,
        "_rank_vector": 2
    },
    {
        "title": "연구개발용 인터넷 운용 및 관리 요령(2025년도 4월 10일 제정)",
        "content": "9. 인터넷 접속 로그를 3년 이상 보관해야 하며, 파일 업로드/다운로드 내역을 분기 1회로 주기적으로 검토해야 한다.",
        "hash": "700b1cf4108149a6718c19e911fd1215c0ae95ed47c12c038437299f572ccb20",
        "score": 0.6797858774662018,
        "_score_vector": 0.6797858774662018,
        "_rank_vector": 1
    }
]'

curl -X POST "$HOST/$INDEX_NAME/rerank" \
     -H "Content-Type: application/json" \
     -d "{
           \"query\": \"$QUERY\",
           \"documents\": $DOCUMENTS
         }"
echo -e "\n"