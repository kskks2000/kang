// Data summarized from the public data.go.kr AcademyInfo basic-information API.
const academyInfoBasicSourceUrl =
    'https://www.data.go.kr/data/15037507/openapi.do';
const academyInfoBasicSourceTitle = '한국대학교육협의회_대학알리미 대학 기본 정보';
const academyInfoBasicProvider = '한국대학교육협의회';
const academyInfoBasicFormat = 'XML';
const academyInfoBasicUpdatedAt = '2021-11-23';
const academyInfoBasicOperationCount = 10;
const academyInfoBasicCodeCategoryCount = 7;
const academyInfoBasicBaseUrl =
    'http://openapi.academyinfo.go.kr/openapi/service/rest/BasicInformationService';

class AcademyInfoBasicOperation {
  const AcademyInfoBasicOperation({
    required this.group,
    required this.title,
    required this.endpoint,
    required this.description,
    required this.requiredParams,
    required this.optionalParams,
    required this.responseFields,
  });

  final String group;
  final String title;
  final String endpoint;
  final String description;
  final List<String> requiredParams;
  final List<String> optionalParams;
  final List<String> responseFields;

  String get serviceUrl => '$academyInfoBasicBaseUrl/$endpoint';

  bool matches(String query) {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) {
      return true;
    }
    return group.toLowerCase().contains(trimmed) ||
        title.toLowerCase().contains(trimmed) ||
        endpoint.toLowerCase().contains(trimmed) ||
        description.toLowerCase().contains(trimmed) ||
        requiredParams.any((value) => value.toLowerCase().contains(trimmed)) ||
        optionalParams.any((value) => value.toLowerCase().contains(trimmed)) ||
        responseFields.any((value) => value.toLowerCase().contains(trimmed));
  }
}

class AcademyInfoCodeCategory {
  const AcademyInfoCodeCategory({
    required this.title,
    required this.endpoint,
    required this.description,
    required this.totalCount,
    required this.values,
    this.sampleOnly = false,
  });

  final String title;
  final String endpoint;
  final String description;
  final int totalCount;
  final bool sampleOnly;
  final List<AcademyInfoCodeValue> values;

  bool matches(String query) {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) {
      return true;
    }
    return title.toLowerCase().contains(trimmed) ||
        endpoint.toLowerCase().contains(trimmed) ||
        description.toLowerCase().contains(trimmed) ||
        values.any((value) => value.matches(trimmed));
  }
}

class AcademyInfoCodeValue {
  const AcademyInfoCodeValue(this.code, this.name, [this.remark = '']);

  final String code;
  final String name;
  final String remark;

  bool matches(String query) {
    return code.toLowerCase().contains(query) ||
        name.toLowerCase().contains(query) ||
        remark.toLowerCase().contains(query);
  }
}

const academyInfoBasicOperations = <AcademyInfoBasicOperation>[
  AcademyInfoBasicOperation(
    group: '연도·지표',
    title: '공시년도 조회_대학비교통계',
    endpoint: 'getComparisonPubYear',
    description: '대학비교통계에서 사용할 수 있는 공시년도를 조회합니다.',
    requiredParams: ['serviceKey'],
    optionalParams: [],
    responseFields: ['yearVal'],
  ),
  AcademyInfoBasicOperation(
    group: '대학 검색',
    title: '대학 검색목록_대학비교통계',
    endpoint: 'getComparisonUniversitySearchList',
    description: '공시년도와 대학 조건으로 대학비교통계용 대학 목록을 조회합니다.',
    requiredParams: ['serviceKey', 'svyYr'],
    optionalParams: [
      'schlId',
      'schlKrnNm',
      'clgcpDivCd',
      'schlDivCd',
      'schlKndCd',
      'znCd',
      'estbDivCd',
      'numOfRows',
      'pageNo',
    ],
    responseFields: [
      'schlId',
      'schlKrnNm',
      'schlFullNm',
      'clgcpDivNm',
      'schlDivNm',
      'schlKndNm',
      'estbDivNm',
      'znNm',
    ],
  ),
  AcademyInfoBasicOperation(
    group: '대학 검색',
    title: '대학 검색목록_우리대학경쟁력',
    endpoint: 'getNoticeUniversitySearchList',
    description: '우리대학경쟁력 지표에서 사용할 대학 검색 목록을 조회합니다.',
    requiredParams: ['serviceKey', 'svyYr'],
    optionalParams: [
      'schlId',
      'schlKrnNm',
      'clgcpDivCd',
      'schlDivCd',
      'schlKndCd',
      'znCd',
      'estbDivCd',
      'numOfRows',
      'pageNo',
    ],
    responseFields: [
      'schlId',
      'schlKrnNm',
      'schlFullNm',
      'clgcpDivNm',
      'schlDivNm',
      'schlKndNm',
      'estbDivNm',
      'znNm',
    ],
  ),
  AcademyInfoBasicOperation(
    group: '대학 검색',
    title: '대학 코드조회',
    endpoint: 'getUniversityCode',
    description: '학교아이디, 대학명, 지역, 설립구분 등 대학 기본 코드를 조회합니다.',
    requiredParams: ['serviceKey', 'svyYr'],
    optionalParams: [
      'schlId',
      'schlKrnNm',
      'clgcpDivCd',
      'schlDivCd',
      'znCd',
      'estbDivCd',
      'numOfRows',
      'pageNo',
    ],
    responseFields: [
      'schlId',
      'schlKrnNm',
      'schlFullNm',
      'clgcpDivNm',
      'schlDivNm',
      'schlKndNm',
      'estbDivNm',
      'znNm',
    ],
  ),
  AcademyInfoBasicOperation(
    group: '코드표',
    title: '설립유형별 코드조회',
    endpoint: 'getCodeByFound',
    description: '국립, 공립, 사립 등 대학 설립유형 코드를 조회합니다.',
    requiredParams: ['serviceKey'],
    optionalParams: ['cdid', 'cdnm', 'numOfRows', 'pageNo'],
    responseFields: ['cdid', 'cdnm'],
  ),
  AcademyInfoBasicOperation(
    group: '연도·지표',
    title: '조사년도 조회_우리대학경쟁력',
    endpoint: 'getNoticeSvyYear',
    description: '우리대학경쟁력에서 사용할 수 있는 조사년도를 조회합니다.',
    requiredParams: ['serviceKey'],
    optionalParams: [],
    responseFields: ['yearVal'],
  ),
  AcademyInfoBasicOperation(
    group: '연도·지표',
    title: '주요지표 코드조회',
    endpoint: 'getKeyIndicatorCode',
    description: '재적학생, 취업률, 회계 현황 등 주요지표 코드를 조회합니다.',
    requiredParams: ['serviceKey'],
    optionalParams: ['cdid', 'cdnm', 'rmk', 'numOfRows', 'pageNo'],
    responseFields: ['cdid', 'cdnm', 'rmk'],
  ),
  AcademyInfoBasicOperation(
    group: '코드표',
    title: '지역별 코드조회',
    endpoint: 'getCodeByRegion',
    description: '대학 소재 지역 코드를 조회합니다.',
    requiredParams: ['serviceKey'],
    optionalParams: ['cdid', 'cdnm', 'numOfRows', 'pageNo'],
    responseFields: ['cdid', 'cdnm'],
  ),
  AcademyInfoBasicOperation(
    group: '코드표',
    title: '학교유형별 코드조회',
    endpoint: 'getCodeByType',
    description: '일반대학원, 전문대학, 사이버대학 등 학교유형 코드를 조회합니다.',
    requiredParams: ['serviceKey'],
    optionalParams: ['cdid', 'cdnm', 'numOfRows', 'pageNo'],
    responseFields: ['cdid', 'cdnm'],
  ),
  AcademyInfoBasicOperation(
    group: '코드표',
    title: '학교종류별 코드조회',
    endpoint: 'getCodeByKind',
    description: '전문대학, 대학, 대학원, 대학원대학 구분 코드를 조회합니다.',
    requiredParams: ['serviceKey'],
    optionalParams: ['cdid', 'cdnm', 'numOfRows', 'pageNo'],
    responseFields: ['cdid', 'cdnm'],
  ),
];

const academyInfoCodeCategories = <AcademyInfoCodeCategory>[
  AcademyInfoCodeCategory(
    title: '지역 코드',
    endpoint: 'getCodeByRegion',
    description: '대학 소재지를 지역 단위로 분류하는 코드입니다.',
    totalCount: 17,
    values: [
      AcademyInfoCodeValue('11', '서울'),
      AcademyInfoCodeValue('21', '부산'),
      AcademyInfoCodeValue('22', '대구'),
      AcademyInfoCodeValue('23', '인천'),
      AcademyInfoCodeValue('24', '광주'),
      AcademyInfoCodeValue('25', '대전'),
      AcademyInfoCodeValue('26', '울산'),
      AcademyInfoCodeValue('41', '경기'),
      AcademyInfoCodeValue('42', '강원'),
      AcademyInfoCodeValue('43', '충북'),
      AcademyInfoCodeValue('44', '충남'),
      AcademyInfoCodeValue('45', '전북'),
      AcademyInfoCodeValue('46', '전남'),
      AcademyInfoCodeValue('47', '경북'),
      AcademyInfoCodeValue('48', '경남'),
      AcademyInfoCodeValue('49', '제주'),
      AcademyInfoCodeValue('50', '세종'),
    ],
  ),
  AcademyInfoCodeCategory(
    title: '설립유형 코드',
    endpoint: 'getCodeByFound',
    description: '대학의 설립 주체를 구분하는 코드입니다.',
    totalCount: 7,
    values: [
      AcademyInfoCodeValue('1', '국립'),
      AcademyInfoCodeValue('2', '공립'),
      AcademyInfoCodeValue('3', '사립'),
      AcademyInfoCodeValue('5', '특별법국립'),
      AcademyInfoCodeValue('6', '특별법법인'),
      AcademyInfoCodeValue('7', '국립대법인'),
      AcademyInfoCodeValue('9', '기타'),
    ],
  ),
  AcademyInfoCodeCategory(
    title: '학교종류 코드',
    endpoint: 'getCodeByKind',
    description: '대학을 큰 종류 단위로 구분하는 코드입니다.',
    totalCount: 4,
    values: [
      AcademyInfoCodeValue('01', '전문대학'),
      AcademyInfoCodeValue('02', '대학'),
      AcademyInfoCodeValue('03', '대학원'),
      AcademyInfoCodeValue('04', '대학원대학'),
    ],
  ),
  AcademyInfoCodeCategory(
    title: '학교유형 코드',
    endpoint: 'getCodeByType',
    description: '대학·대학원 유형을 세부적으로 구분하는 코드입니다.',
    totalCount: 18,
    sampleOnly: true,
    values: [
      AcademyInfoCodeValue('XX', '코드 없음'),
      AcademyInfoCodeValue('19', '전문대학(4년제)'),
      AcademyInfoCodeValue('18', '전문대학(2년제)'),
      AcademyInfoCodeValue('17', '기타대학원'),
      AcademyInfoCodeValue('14', '기능대학'),
      AcademyInfoCodeValue('13', '사이버대학(대학)'),
      AcademyInfoCodeValue('12', '사이버대학(전문대학)'),
      AcademyInfoCodeValue('11', '특수대학원'),
      AcademyInfoCodeValue('10', '전문대학원'),
      AcademyInfoCodeValue('09', '일반대학원'),
    ],
  ),
  AcademyInfoCodeCategory(
    title: '본분교구분 코드',
    endpoint: '메시지 코드 정의',
    description: '본교와 분교를 구분하는 기본 메시지 코드입니다.',
    totalCount: 9,
    values: [
      AcademyInfoCodeValue('1', '본교'),
      AcademyInfoCodeValue('2', '분교'),
      AcademyInfoCodeValue('3', '분교2'),
      AcademyInfoCodeValue('4', '분교3'),
      AcademyInfoCodeValue('5', '분교4'),
      AcademyInfoCodeValue('6', '분교5'),
      AcademyInfoCodeValue('7', '분교6'),
      AcademyInfoCodeValue('8', '분교7'),
      AcademyInfoCodeValue('9', '분교8'),
    ],
  ),
  AcademyInfoCodeCategory(
    title: '조사년도',
    endpoint: 'getNoticeSvyYear',
    description: '우리대학경쟁력 조회에 쓰이는 조사년도 예시입니다.',
    totalCount: 3,
    values: [
      AcademyInfoCodeValue('2019', '조사년도'),
      AcademyInfoCodeValue('2018', '조사년도'),
      AcademyInfoCodeValue('2017', '조사년도'),
    ],
  ),
  AcademyInfoCodeCategory(
    title: '주요지표 코드',
    endpoint: 'getKeyIndicatorCode',
    description: '주요지표 코드 예시입니다. 전체 명세는 254건으로 안내됩니다.',
    totalCount: 254,
    sampleOnly: true,
    values: [
      AcademyInfoCodeValue('9', '재적학생', '명'),
      AcademyInfoCodeValue('82', '학자금대출 이용학생비율(등록금(학비))', '%'),
      AcademyInfoCodeValue('80', '산학협력단 회계 현황', '천원'),
    ],
  ),
];
