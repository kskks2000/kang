# 주식 거래 대시보드 작업 상태

이 문서는 주식 거래 대시보드를 다시 수정할 때 이전 완료 항목과 주의할 점을 빠르게 확인하기 위한 에이전트용 메모입니다. 사용자-facing 기능 설명은 README가 아니라 실제 화면과 코드 기준으로 확인합니다.

## 작업 전 확인

- 주식 거래 대시보드 작업을 시작하기 전 `AGENTS.md`와 이 파일을 함께 읽습니다.
- 기존에 적용 완료된 항목을 되돌리거나 중복 구현하지 않습니다.
- 토스증권 Open API 주문 관련 비밀값, 계좌, 허용 이메일, 토큰은 로그, 문서, diff에 노출하지 않습니다.
- 실제 주문 전송 기능은 Firebase 인증, `TOSSINVEST_TRADING_ENABLED=true`, 허용 이메일, 프론트엔드 최종 확인 UI 조건을 모두 지켜야 합니다.
- 완료 보고 전에는 `https://www.kang.ai.kr` 배포 및 운영 도메인 확인을 끝냅니다.

## 적용 완료 항목

1. 종목 앞에 회사 로고 이미지가 표시되도록 적용했습니다.
2. 빨간색은 양봉, 플러스, 매수로 쓰고 파란색은 음봉, 마이너스, 매도로 쓰도록 주식 화면 색상 체계를 맞췄습니다.
3. 종목 검색이 동작하지 않던 문제를 수정했습니다.
4. 종목 아이콘이 표시되지 않던 원인을 확인하고 표시되도록 수정했습니다.
5. 매수/매도 버튼이 실제 토스증권 주문 API로 연결되도록 수정했습니다.
6. 차트 시간 선택 UI를 요청한 형태로 변경했습니다.
7. 주문가격 입력과 금액/가격 표시 전반에 콤마 포맷을 적용했습니다.
8. 체결, 미체결, 잔고 영역이 실제 데이터와 연결되도록 수정했습니다.
9. 삼성전자 등 watchlist 주가가 최신 가격과 일봉 등락률 기준으로 보이도록 수정했습니다. 클릭 시 잠시 보였다가 사라지는 문제를 막기 위해 quote cache와 watchlist daily change fallback을 함께 사용합니다.
10. 종목 아이콘이 흐릿해 보이는 문제를 줄이기 위해 주요 종목은 선명한 브랜드 컬러 기반 심볼 마크로 렌더링하도록 변경했습니다.
11. 주식 거래 대시보드의 주요 패널 구분선을 드래그해서 너비와 높이를 조정할 수 있도록 변경했습니다. 좌측 메인 영역과 우측 주문 영역 사이의 너비, 관심종목/차트 사이의 높이, 주문/체결·잔고 사이의 높이를 조정할 수 있으며, 구분선을 더블클릭하면 기본 비율로 되돌립니다.

## 관련 코드

- `frontend/lib/screens/home_screen.dart`
  - 주식 거래 전체 화면, watchlist, 차트, 주문 패널, 체결/잔고 패널, 종목 아이콘 렌더링이 포함되어 있습니다.
  - `_StockTradingSymbolAvatar`, `_StockTradingPremiumSymbolAvatar`, `_stockBrandMarkSpecs`는 종목 아이콘 표시를 담당합니다.
  - `_StockTradingResizableVerticalSplit`, `_StockTradingResizeHandle`은 주식 대시보드 패널 크기 조절 구분선을 담당합니다.
  - `_StockTradingWatchlistPanelState`는 검색 결과와 daily change fallback을 관리합니다.
  - `_quoteCache`, `_currentMarketQuotes`, `_activeQuote`는 종목 선택 시 가격이 사라지지 않게 유지하는 데 중요합니다.
- `frontend/lib/services/toss_stock_api.dart`
  - 토스 주식 대시보드, 캔들, 주문, 체결/잔고 응답 모델과 API 클라이언트가 있습니다.
- `backend/app/tossinvest_service.py`
  - 토스증권 Open API 호출, dashboard 응답 조립, 주문 생성/정정/취소, watchlist 일봉 등락률 fallback이 있습니다.
- `backend/app/schemas.py`
  - 토스 주식 API 요청/응답 스키마가 있습니다.

## 검증 기준

- 프론트엔드 변경 후:
  - `cd D:\kcastle\kang\frontend`
  - `C:\src\flutter\bin\flutter.bat analyze`
  - `C:\src\flutter\bin\flutter.bat test`
- 운영 웹 빌드:
  - `C:\src\flutter\bin\flutter.bat build web --release --dart-define=API_BASE_URL=https://www.kang.ai.kr`
- 운영 배포 후:
  - `Invoke-WebRequest -Uri https://www.kang.ai.kr/health -UseBasicParsing`
  - 운영 도메인에서 변경 화면 또는 관련 API를 확인합니다.

## 운영 확인 메모

- `www.kang.ai.kr`은 Firebase Hosting이 아니라 SFTP 서버의 `/web/public` 정적 파일과 `/web/backend` 백엔드를 통해 서비스됩니다.
- SFTP 접속정보는 루트 `.env`의 `SFTP_*` 값에 있으며, 실제 값은 출력하거나 문서화하지 않습니다.
- 원격 서버는 `/web/server.py`에서 FastAPI 앱과 Flutter 정적 파일을 함께 제공합니다.
- 운영 API는 Firebase bearer token이 필요한 엔드포인트가 있으므로, 브라우저 로그인 세션이 없으면 화면/API 일부를 직접 확인하지 못할 수 있습니다.
