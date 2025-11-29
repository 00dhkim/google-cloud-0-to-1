import json
import random
from locust import HttpUser, task, between, events, LoadTestShape

# === 테스트 데이터 설정 ===
# INDEX_NAME = "faiss_index_by_sentence_100"
INDEX_NAME = "faiss_index_by_size_1000"

# 쉘 스크립트에 있던 쿼리 목록
QUERIES = [
    "감사요령에 따른 감사자문위원회와 관련하여 외부위원의 비율은?",
    "감사처분 처리기한과 관련하여, 신분상 징계 처분의 처리기한은?",
    "공무국외출장의 귀국보고서를 생략할 수 있는 경우는?",
    "공무국외출장의 출장자 중 임원이 포함되어 있는 경우, 무관동의가 필요한가?",
    "여비규정에 따르면, 국외출장자가 숙박비를 할인정액으로 신청할 때 지급받는 숙박비는?",
    "같은 지역 장기출장 중 일비가 감액되는 시점은 출장일로부터 며칠부터인가?",
    "연구개발망 전용 단말기에 프로그램 설치를 심의하는 대상은 누구인가?",
    "연구개발망의 인터넷 접속 로그의 보관 기한은?",
    "핵심기술 사업에서 8천만원 규모의 신규장비 획득을 위한 집행계획 변경 시 전결자는?",
    "4억원 규모의 구매 계약요구 시 전결권자는?",
]

# Rerank용 문서 데이터 (쉘 스크립트 내용 복사)
RERANK_DOCS = [
    {
        "title": "연구개발용 인터넷 운용 및 관리 요령(2025년도 4월 10일 제정)",
        "content": "연구ㆍ개발용 인터넷망(이하 ‘연구개발망’이라 한다)이라 함은 인공지능 학습 및 데이터 활용 등 연구 여건을 보장하기 위한 상용 인터넷으로서 인트라넷(이하 ‘소내망’이라 한다), 업무용 인터넷(이하 ‘인터넷망’이라 한다) 및 국방망과 물리적으로 분리되는 인터넷을 말한다",
        "hash": "700b1cf4108149a6718c19e911fd1215c0ae95ed47c12c038437299f572ccb20",
        "score": 0.7426729798316956,
        "_score_vector": 0.7426729798316956,
        "_rank_vector": 10,
    },
    {
        "title": "연구개발용 인터넷 운용 및 관리 요령(2025년도 4월 10일 제정)",
        "content": "② 연구개발망운용부서장은 연구개발망을 보호하기 위해 연구소 보안정책에 따라 접속 가능한 사이트 및 설치 가능한 프로그램 목록을 관리한다.",
        "hash": "700b1cf4108149a6718c19e911fd1215c0ae95ed47c12c038437299f572ccb20",
        "score": 0.741437703371048,
        "_score_vector": 0.741437703371048,
        "_rank_vector": 9,
    },
    {
        "title": "연구개발용 인터넷 운용 및 관리 요령(2025년도 4월 10일 제정)",
        "content": "연구개발망 접속 사이트 차단해제 및 프로그램 설치 신청(00원 00부)",
        "hash": "700b1cf4108149a6718c19e911fd1215c0ae95ed47c12c038437299f572ccb20",
        "score": 0.7384727597236633,
        "_score_vector": 0.7384727597236633,
        "_rank_vector": 8,
    },
    {
        "title": "연구개발용 인터넷 운용 및 관리 요령(2025년도 4월 10일 제정)",
        "content": "나. 연구개발망 보안 및 유해사이트 통제 정책 수립, 정책 적용 및 관리",
        "hash": "700b1cf4108149a6718c19e911fd1215c0ae95ed47c12c038437299f572ccb20",
        "score": 0.7328095138072968,
        "_score_vector": 0.7328095138072968,
        "_rank_vector": 7,
    },
    {
        "title": "연구개발용 인터넷 운용 및 관리 요령(2025년도 4월 10일 제정)",
        "content": "5. 연구개발망 운용부서장은 심의ㆍ승인 사항에 대하여 익월 14일까지 보안 담당부서로 통보하여야 한다.",
        "hash": "700b1cf4108149a6718c19e911fd1215c0ae95ed47c12c038437299f572ccb20",
        "score": 0.731753408908844,
        "_score_vector": 0.731753408908844,
        "_rank_vector": 6,
    },
    {
        "title": "연구개발용 인터넷 운용 및 관리 요령(2025년도 4월 10일 제정)",
        "content": "연구개발망 설치장소에 출입증 태깅 시스템이 갖추어진 곳은 전자기록으로 사용자 현황을 관리·유지할 수 있으며, 그렇지 아니한 경우에는 수기 출입대장[별지 제1호 서식]을 유지하여야 한다.",
        "hash": "700b1cf4108149a6718c19e911fd1215c0ae95ed47c12c038437299f572ccb20",
        "score": 0.7243528068065643,
        "_score_vector": 0.7243528068065643,
        "_rank_vector": 5,
    },
    {
        "title": "연구개발용 인터넷 운용 및 관리 요령(2025년도 4월 10일 제정)",
        "content": "⑤ 연구개발망 운영부서는 위원회의 의사록 등 기록을 유지하여야 한다.",
        "hash": "700b1cf4108149a6718c19e911fd1215c0ae95ed47c12c038437299f572ccb20",
        "score": 0.7155337035655975,
        "_score_vector": 0.7155337035655975,
        "_rank_vector": 4,
    },
    {
        "title": "연구개발용 인터넷 운용 및 관리 요령(2025년도 4월 10일 제정)",
        "content": "마. 연구개발망 네트워크 및 정보보호체계 보안 관리",
        "hash": "700b1cf4108149a6718c19e911fd1215c0ae95ed47c12c038437299f572ccb20",
        "score": 0.7116822600364685,
        "_score_vector": 0.7116822600364685,
        "_rank_vector": 3,
    },
    {
        "title": "연구개발용 인터넷 운용 및 관리 요령(2025년도 4월 10일 제정)",
        "content": "연구ㆍ개발용 인터넷 운용 및 관리 요령",
        "hash": "700b1cf4108149a6718c19e911fd1215c0ae95ed47c12c038437299f572ccb20",
        "score": 0.6894233524799347,
        "_score_vector": 0.6894233524799347,
        "_rank_vector": 2,
    },
    {
        "title": "연구개발용 인터넷 운용 및 관리 요령(2025년도 4월 10일 제정)",
        "content": "9. 인터넷 접속 로그를 3년 이상 보관해야 하며, 파일 업로드/다운로드 내역을 분기 1회로 주기적으로 검토해야 한다.",
        "hash": "700b1cf4108149a6718c19e911fd1215c0ae95ed47c12c038437299f572ccb20",
        "score": 0.6797858774662018,
        "_score_vector": 0.6797858774662018,
        "_rank_vector": 1,
    },
]


class FaissUser(HttpUser):
    # 각 사용자(User)는 요청 사이에 1~3초 대기 (사람과 유사한 패턴)
    wait_time = between(1, 3)

    @task(3)  # 가중치 3: 가장 자주 호출됨 (CPU 부하 유발 핵심)
    def vector_search(self):
        query = random.choice(QUERIES)
        payload = {
            "query": query,
            "k": 10,
            "threshold": 0.5,
            "diversity": False,
            "diversity_k": 2,
        }
        self.client.post(
            f"/{INDEX_NAME}/vector_search",
            json=payload,
            name="Vector Search",  # 리포트용 이름
        )

    @task(1)  # 가중치 1
    def keyword_search(self):
        query = random.choice(QUERIES)
        payload = {"query": query, "k": 10}
        self.client.post(
            f"/{INDEX_NAME}/keyword_search", json=payload, name="Keyword Search"
        )

    @task(1)  # 가중치 1 (데이터 페이로드가 커서 네트워크/메모리 부하 유발)
    def rerank(self):
        query = random.choice(QUERIES)
        # Rerank는 문서 목록이 필요함
        payload = {"query": query, "documents": RERANK_DOCS}
        self.client.post(f"/{INDEX_NAME}/rerank", json=payload, name="Rerank")


# === 커스텀 부하 패턴 (Step Load) ===
class StepLoadShape(LoadTestShape):
    """
    파드 생성 시간(8분)을 고려하여 10분 단위로 부하를 증가시키는 시나리오
    """

    # 시간(초), 사용자 수, 초당 생성 속도
    # stages = [
    #     {"duration": 300, "users": 5, "spawn_rate": 1},  # 0~5분: 5명 (Baseline)
    #     {
    #         "duration": 900,
    #         "users": 20,
    #         "spawn_rate": 1,
    #     },  # 5~15분: 20명 (HPA Trigger & Wait)
    #     {"duration": 1500, "users": 40, "spawn_rate": 2},  # 15~25분: 40명 (Max Load)
    # ]
    stages = [
        # 0~5분: 저부하, HPA OFF/ON 비교용 기준선
        {"duration": 60*5, "users": 5, "spawn_rate": 1},
        # 5~20분: 파드 생성 8분 + 안정화 시간 포함
        {"duration": 60*20, "users": 20, "spawn_rate": 2},
        # 20~35분: 더 높은 부하에서 HPA 효과 관찰
        {"duration": 60*35, "users": 40, "spawn_rate": 4},
    ]

    def tick(self):
        run_time = self.get_run_time()

        for stage in self.stages:
            if run_time < stage["duration"]:
                tick_data = (stage["users"], stage["spawn_rate"])
                return tick_data

        return None  # 테스트 종료
