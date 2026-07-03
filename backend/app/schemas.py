from __future__ import annotations

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class SessionRequest(BaseModel):
    id_token: str = Field(min_length=20)


class UserSession(BaseModel):
    id: str
    firebase_uid: str
    email: Optional[str]
    display_name: Optional[str]
    photo_url: Optional[str]
    user_no: Optional[int]
    user_name: str
    user_type: str
    role_code: str


class SessionResponse(BaseModel):
    user: UserSession


class FindLoginIdRequest(BaseModel):
    email: str = Field(min_length=3, max_length=320)


class FindLoginIdResponse(BaseModel):
    found: bool
    masked_login_id: Optional[str] = None
    message: str


class CalendarEventsRequest(BaseModel):
    id_token: str = Field(min_length=20)
    google_access_token: str = Field(min_length=20)
    time_min: datetime
    time_max: datetime
    max_results: int = Field(default=50, ge=1, le=100)


class CalendarEvent(BaseModel):
    id: str
    title: str
    start: Optional[str] = None
    end: Optional[str] = None
    location: Optional[str] = None
    all_day: bool = False


class CalendarEventsResponse(BaseModel):
    events: list[CalendarEvent]


class DriveFilesRequest(BaseModel):
    id_token: str = Field(min_length=20)
    google_access_token: str = Field(min_length=20)
    query: Optional[str] = Field(default=None, max_length=200)
    page_size: int = Field(default=50, ge=1, le=100)
    include_sheet_names: bool = False


class DriveSheetFile(BaseModel):
    id: str
    name: str
    folder_name: Optional[str] = None
    sheet_names: list[str] = Field(default_factory=list)
    modified_time: Optional[str] = None
    web_view_link: Optional[str] = None


class DriveFilesResponse(BaseModel):
    files: list[DriveSheetFile]


class DriveSheetNamesRequest(BaseModel):
    id_token: str = Field(min_length=20)
    google_access_token: str = Field(min_length=20)
    file_id: str = Field(min_length=5, max_length=300)


class DriveSheetNamesResponse(BaseModel):
    sheet_names: list[str]


class DriveImportRequest(BaseModel):
    id_token: str = Field(min_length=20)
    google_access_token: str = Field(min_length=20)
    file_id: str = Field(min_length=5, max_length=300)
    file_name: str = Field(min_length=1, max_length=500)
    sheet_name: Optional[str] = Field(default=None, min_length=1, max_length=500)
    max_rows: int = Field(default=100000, ge=1, le=100000)


class DriveImportResponse(BaseModel):
    file_id: str
    file_name: str
    sheet_name: Optional[str] = None
    imported_rows: int
    sheet_count: int


class DriveRowsRequest(BaseModel):
    id_token: str = Field(min_length=20)
    search: Optional[str] = Field(default=None, max_length=200)
    limit: int = Field(default=25000, ge=1, le=50000)


class GoogleDriveRow(BaseModel):
    id: str
    drivename: Optional[str] = None
    tabname: Optional[str] = None
    text01: Optional[str] = None
    text02: Optional[str] = None
    text03: Optional[str] = None
    text04: Optional[str] = None
    text05: Optional[str] = None
    text06: Optional[str] = None
    text07: Optional[str] = None
    text08: Optional[str] = None
    text09: Optional[str] = None
    text10: Optional[str] = None
    text11: Optional[str] = None
    text12: Optional[str] = None
    text13: Optional[str] = None
    text14: Optional[str] = None
    text15: Optional[str] = None
    text16: Optional[str] = None
    text17: Optional[str] = None
    text18: Optional[str] = None
    text19: Optional[str] = None
    text20: Optional[str] = None


class DriveRowsResponse(BaseModel):
    rows: list[GoogleDriveRow]


class AcademyInfoSource(BaseModel):
    title: str
    provider: str
    sourceUrl: str
    serviceBaseUrl: str
    format: str


class AcademyInfoSummary(BaseModel):
    operationCount: int
    successCount: int
    errorCount: int
    totalRows: int
    latestComparisonYear: Optional[str] = None
    latestNoticeYear: Optional[str] = None


class AcademyInfoOperationResult(BaseModel):
    group: str
    title: str
    endpoint: str
    description: str
    requiredParams: list[str]
    optionalParams: list[str]
    responseFields: list[str]
    serviceUrl: str
    status: str
    resultCode: str
    resultMsg: str
    totalCount: Optional[int] = None
    rowCount: int
    hasMore: bool
    requestParams: dict[str, str]
    rows: list[dict[str, str]]
    fields: list[str]


class AcademyInfoBasicResponse(BaseModel):
    status: str
    fetchedAt: str
    cached: bool
    cacheSeconds: int
    source: AcademyInfoSource
    summary: AcademyInfoSummary
    operations: list[AcademyInfoOperationResult]


class MarketCapSource(BaseModel):
    title: str
    provider: str
    sourceUrl: str
    description: str


class MarketCapSummary(BaseModel):
    requestedLimit: int
    count: int
    topCompany: Optional[str] = None
    topSymbol: Optional[str] = None
    topMarketCap: Optional[int] = None
    lastUpdated: Optional[str] = None


class MarketCapCompany(BaseModel):
    rank: int
    symbol: str
    name: str
    country: str
    countryCode: str
    sector: str
    industry: str
    marketCap: int
    price: Optional[float] = None
    dailyChangePercent: Optional[float] = None
    peRatio: Optional[float] = None
    revenue: int
    earnings: int
    lastUpdated: str


class MarketCapTopResponse(BaseModel):
    status: str
    fetchedAt: str
    cached: bool
    cacheSeconds: int
    source: MarketCapSource
    summary: MarketCapSummary
    companies: list[MarketCapCompany]


class FinancialSource(BaseModel):
    name: str
    url: str
    description: str


class FinancialSummary(BaseModel):
    treasuryDate: Optional[str] = None
    exchangeRateDate: Optional[str] = None
    treasuryCount: int
    exchangeRateCount: int
    futureCount: int
    errorCount: int


class TreasuryRate(BaseModel):
    maturity: str
    label: str
    rate: Optional[float] = None
    previousRate: Optional[float] = None
    change: Optional[float] = None
    date: str


class TreasurySpread(BaseModel):
    code: str
    label: str
    value: Optional[float] = None
    date: str


class ExchangeRate(BaseModel):
    pair: str
    label: str
    base: str
    quote: str
    rate: float
    usdBaseRate: float
    previousRate: Optional[float] = None
    change: Optional[float] = None
    changePercent: Optional[float] = None
    date: str
    marketTime: Optional[str] = None
    sourceSymbol: Optional[str] = None


class MarketFuture(BaseModel):
    symbol: str
    name: str
    displayName: str
    group: str
    price: Optional[float] = None
    change: Optional[float] = None
    changePercent: Optional[float] = None
    previousClose: Optional[float] = None
    currency: str
    marketTime: str
    exchange: str


class FinancialMarketsResponse(BaseModel):
    status: str
    fetchedAt: str
    cached: bool
    cacheSeconds: int
    sources: list[FinancialSource]
    summary: FinancialSummary
    treasuryRates: list[TreasuryRate]
    treasurySpreads: list[TreasurySpread]
    exchangeRates: list[ExchangeRate]
    futures: list[MarketFuture]
    errors: list[str]


class TossInvestSource(BaseModel):
    title: str
    provider: str
    sourceUrl: str
    specUrl: str
    description: str


class TossInvestDashboardSummary(BaseModel):
    market: str
    primarySymbol: str
    symbolCount: int
    accountCount: int
    accountConfigured: bool
    selectedAccountMasked: Optional[str] = None
    holdingCount: int
    openOrderCount: int
    executionCount: int
    buyingPowerKrw: Optional[str] = None
    buyingPowerUsd: Optional[str] = None
    tradingEnabled: bool
    tradingAllowed: bool
    tradingAvailable: bool
    tradingBlockedReason: Optional[str] = None


class TossInvestAccount(BaseModel):
    accountSeq: Optional[int] = None
    accountNoMasked: str
    accountType: str
    selected: bool


class TossInvestStockQuote(BaseModel):
    symbol: str
    name: str
    englishName: str
    displayName: str
    market: str
    currency: str
    lastPrice: str
    previousClose: str
    change: str
    changePercent: str
    sharesOutstanding: str
    marketCap: str
    timestamp: Optional[str] = None


class TossInvestStockSearchItem(BaseModel):
    symbol: str
    name: str
    market: str


class TossInvestStockSearchResponse(BaseModel):
    market: str
    query: str
    count: int
    items: list[TossInvestStockSearchItem]


class TossInvestOrderbookEntry(BaseModel):
    price: str
    volume: str


class TossInvestOrderbook(BaseModel):
    symbol: str
    timestamp: Optional[str] = None
    currency: str
    asks: list[TossInvestOrderbookEntry]
    bids: list[TossInvestOrderbookEntry]


class TossInvestCandle(BaseModel):
    timestamp: str
    openPrice: str
    highPrice: str
    lowPrice: str
    closePrice: str
    volume: str
    currency: str


class TossInvestCandlesResponse(BaseModel):
    symbol: str
    interval: str
    count: int
    nextBefore: str
    candles: list[TossInvestCandle]


class TossInvestHolding(BaseModel):
    symbol: str
    name: str
    marketCountry: str
    currency: str
    quantity: str
    lastPrice: str
    averagePurchasePrice: str
    marketValue: str
    profitLoss: str
    profitLossRate: str
    dailyProfitLoss: str
    dailyProfitLossRate: str


class TossInvestOpenOrder(BaseModel):
    orderId: str
    symbol: str
    side: str
    status: str
    orderType: str
    quantity: str
    price: str
    currency: str
    orderedAt: str


class TossInvestExecution(BaseModel):
    orderId: str
    symbol: str
    side: str
    status: str
    orderType: str
    quantity: str
    price: str
    filledQuantity: str
    averageFilledPrice: str
    filledAmount: str
    currency: str
    orderedAt: str
    filledAt: Optional[str] = None
    settlementDate: Optional[str] = None


class TossInvestBuyingPower(BaseModel):
    currency: str
    cashBuyingPower: str


class TossInvestStockDashboardResponse(BaseModel):
    status: str
    fetchedAt: str
    cached: bool
    cacheSeconds: int
    source: TossInvestSource
    summary: TossInvestDashboardSummary
    accounts: list[TossInvestAccount]
    watchlist: list[TossInvestStockQuote]
    orderbook: Optional[TossInvestOrderbook] = None
    candles: list[TossInvestCandle]
    holdings: list[TossInvestHolding]
    openOrders: list[TossInvestOpenOrder]
    executions: list[TossInvestExecution]
    buyingPower: list[TossInvestBuyingPower]
    errors: list[str]


class TossInvestOrderRequest(BaseModel):
    symbol: str = Field(min_length=1, max_length=20)
    side: str = Field(min_length=3, max_length=4)
    orderType: str = Field(min_length=5, max_length=6)
    quantity: Optional[str] = Field(default=None, min_length=1, max_length=30)
    price: Optional[str] = Field(default=None, max_length=30)
    orderAmount: Optional[str] = Field(default=None, max_length=30)
    timeInForce: str = Field(default="DAY", min_length=3, max_length=3)
    confirmHighValueOrder: bool = False


class TossInvestOrderResponse(BaseModel):
    status: str
    orderId: str
    clientOrderId: Optional[str] = None
    symbol: str
    side: str
    orderType: str
    quantity: Optional[str] = None
    price: Optional[str] = None
    orderAmount: Optional[str] = None
    timeInForce: str
    message: str


class TossInvestOrderModifyRequest(BaseModel):
    orderType: str = Field(min_length=5, max_length=6)
    quantity: Optional[str] = Field(default=None, min_length=1, max_length=30)
    price: Optional[str] = Field(default=None, max_length=30)
    confirmHighValueOrder: bool = False


class TossInvestOrderActionResponse(BaseModel):
    status: str
    orderId: str
    clientOrderId: Optional[str] = None
    message: str


class UpbitCryptoDashboardResponse(TossInvestStockDashboardResponse):
    pass


class UpbitCryptoCandlesResponse(TossInvestCandlesResponse):
    pass


class UpbitCryptoMarketSearchResponse(TossInvestStockSearchResponse):
    pass


class UpbitOrderRequest(TossInvestOrderRequest):
    pass


class UpbitOrderResponse(TossInvestOrderResponse):
    pass


class UpbitOrderActionResponse(TossInvestOrderActionResponse):
    pass


class SubwaySource(BaseModel):
    title: str
    provider: str
    arrivalUrl: str
    positionUrl: str
    description: str


class SubwayFavoriteStation(BaseModel):
    station: str
    line: str
    label: str


class SubwaySummary(BaseModel):
    station: str
    line: str
    lineColor: str
    arrivalCount: int
    trainCount: int
    keyMode: str
    favoriteStations: list[SubwayFavoriteStation]


class SubwayArrival(BaseModel):
    line: str
    lineColor: str
    station: str
    direction: str
    destination: str
    trainLine: str
    arrivalMessage: str
    arrivalDetail: str
    etaSeconds: Optional[int] = None
    status: str
    trainNo: str
    receivedAt: str
    terminalStation: str


class SubwayTrainPosition(BaseModel):
    line: str
    lineColor: str
    station: str
    trainNo: str
    destination: str
    status: str
    directionCode: str
    isExpress: bool
    isLastTrain: bool
    receivedAt: str


class SubwayOverviewResponse(BaseModel):
    status: str
    fetchedAt: str
    cached: bool
    cacheSeconds: int
    source: SubwaySource
    summary: SubwaySummary
    arrivals: list[SubwayArrival]
    trains: list[SubwayTrainPosition]
    errors: list[str]
