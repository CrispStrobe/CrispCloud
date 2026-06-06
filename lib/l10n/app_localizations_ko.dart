// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appTitle => 'CrispCloud';

  @override
  String get local => '로컬';

  @override
  String get remote => '원격';

  @override
  String get connect => '연결';

  @override
  String get disconnect => '연결 해제';

  @override
  String get login => '로그인';

  @override
  String get logout => '로그아웃';

  @override
  String get upload => '업로드';

  @override
  String get download => '다운로드';

  @override
  String get delete => '삭제';

  @override
  String get rename => '이름 변경';

  @override
  String get move => '이동';

  @override
  String get copy => '복사';

  @override
  String get cancel => '취소';

  @override
  String get save => '저장';

  @override
  String get create => '만들기';

  @override
  String get close => '닫기';

  @override
  String get done => '완료';

  @override
  String get clear => '지우기';

  @override
  String get ok => 'OK';

  @override
  String get yes => '예';

  @override
  String get no => '아니요';

  @override
  String get retry => '다시 시도';

  @override
  String get refresh => '새로 고침';

  @override
  String get search => '검색';

  @override
  String get filter => '필터';

  @override
  String get settings => '설정';

  @override
  String get about => '앱 정보';

  @override
  String get help => '도움말';

  @override
  String get newFolder => '새 폴더';

  @override
  String get folderName => '폴더 이름';

  @override
  String get emptyFolder => '빈 폴더';

  @override
  String get noFolderSelected => '선택된 폴더 없음';

  @override
  String get openLocalFolder => '로컬 폴더 열기';

  @override
  String get sortByName => '이름순 정렬';

  @override
  String get sortBySize => '크기순 정렬';

  @override
  String get sortByDate => '날짜순 정렬';

  @override
  String get sortByExtension => '확장자순 정렬';

  @override
  String get ascending => '오름차순';

  @override
  String get descending => '내림차순';

  @override
  String get selectAll => '모두 선택';

  @override
  String get clearSelection => '선택 해제';

  @override
  String nSelected(int count) {
    return '$count개 선택됨';
  }

  @override
  String get filterFiles => '파일 필터';

  @override
  String get typeToFilter => '필터 입력...';

  @override
  String get filterFilesShortcut => '파일 필터 (Ctrl+F)';

  @override
  String get clearFilter => '필터 지우기';

  @override
  String get browseTooltip => '찾아보기...';

  @override
  String get upTooltip => '위로 (Backspace)';

  @override
  String get refreshTooltip => '새로 고침 (F5)';

  @override
  String get newFolderTooltip => '새 폴더 (Ctrl+N)';

  @override
  String get searchAllFiles => '모든 파일 퍼지 검색';

  @override
  String get findByPattern => '이 폴더에서 패턴으로 파일 찾기 (예: *.pdf)';

  @override
  String get listView => '목록 보기';

  @override
  String get gridView => '격자 보기';

  @override
  String get columnView => '열 보기';

  @override
  String get copyTo => '복사 위치...';

  @override
  String get moveTo => '이동 위치...';

  @override
  String get connected => '연결됨';

  @override
  String get disconnected => '연결 해제됨';

  @override
  String get connecting => '연결 중...';

  @override
  String get connectionFailed => '연결 실패';

  @override
  String get provider => '공급자';

  @override
  String get username => '사용자 이름';

  @override
  String get password => '비밀번호';

  @override
  String get host => '호스트';

  @override
  String get port => '포트';

  @override
  String get serverUrl => '서버 URL';

  @override
  String get appKey => '앱 키';

  @override
  String get clientId => '클라이언트 ID';

  @override
  String get clientSecret => '클라이언트 시크릿';

  @override
  String get accessKey => '액세스 키';

  @override
  String get secretKey => '시크릿 키';

  @override
  String get endpoint => '엔드포인트';

  @override
  String get region => '리전';

  @override
  String get bucket => '버킷';

  @override
  String get twoFactorCode => '2FA 코드';

  @override
  String transferProgress(int percent) {
    return '$percent% 완료';
  }

  @override
  String transferSpeed(String speed) {
    return '$speed/초';
  }

  @override
  String transferEta(String time) {
    return '남은 시간 $time';
  }

  @override
  String get syncManager => '동기화 관리자';

  @override
  String get syncAll => '모두 동기화';

  @override
  String get syncNow => '지금 동기화';

  @override
  String get addPair => '쌍 추가';

  @override
  String get syncPairName => '쌍 이름';

  @override
  String get localPath => '로컬 경로';

  @override
  String get remotePath => '원격 경로';

  @override
  String get conflictPolicy => '충돌 정책';

  @override
  String get syncDirection => '방향';

  @override
  String get twoWay => '양방향';

  @override
  String get uploadOnly => '업로드만';

  @override
  String get downloadOnly => '다운로드만';

  @override
  String get newestWins => '최신 우선';

  @override
  String get localWins => '로컬 우선';

  @override
  String get remoteWins => '원격 우선';

  @override
  String get keepBoth => '둘 다 보존';

  @override
  String get manual => '수동';

  @override
  String get backgroundSync => '백그라운드 동기화';

  @override
  String get cloudOnlyFiles => '클라우드 전용 파일';

  @override
  String get includePatterns => '포함 패턴';

  @override
  String get excludePatterns => '제외 패턴';

  @override
  String get encryption => '암호화';

  @override
  String get encryptionEnabled => '암호화 활성화됨';

  @override
  String get passphrase => '암호 문구';

  @override
  String get keyManagement => '키 관리';

  @override
  String get exportKey => '키 내보내기';

  @override
  String get importKey => '키 가져오기';

  @override
  String get mnemonic => '니모닉';

  @override
  String get backupBundle => '백업 번들';

  @override
  String get appLock => '앱 잠금';

  @override
  String get setupLock => '잠금 설정';

  @override
  String get changeLock => '잠금 변경';

  @override
  String get disableLock => '잠금 비활성화';

  @override
  String get enterPin => 'PIN 또는 비밀번호 입력';

  @override
  String get biometricUnlock => '생체 인식 잠금 해제';

  @override
  String get autoLockTimeout => '자동 잠금 시간';

  @override
  String get proxySettings => '프록시 설정';

  @override
  String get noProxy => '프록시 없음';

  @override
  String get httpProxy => 'HTTP 프록시';

  @override
  String get socks5Proxy => 'SOCKS5 프록시';

  @override
  String get certificatePinning => '인증서 고정';

  @override
  String get preview => '미리 보기';

  @override
  String get edit => '편집';

  @override
  String get compare => '비교';

  @override
  String get permissions => '권한';

  @override
  String get checksum => '체크섬';

  @override
  String get calculateSize => '크기 계산';

  @override
  String get batchRename => '일괄 이름 변경';

  @override
  String get extractHere => '여기에 압축 해제';

  @override
  String get createZip => 'Zip 만들기';

  @override
  String get shareLink => '링크 공유';

  @override
  String get versionHistory => '버전 기록';

  @override
  String get findDuplicates => '중복 찾기';

  @override
  String get commandPalette => '명령 팔레트';

  @override
  String get theme => '테마';

  @override
  String get systemTheme => '시스템';

  @override
  String get lightTheme => '라이트';

  @override
  String get darkTheme => '다크';

  @override
  String get oledTheme => 'OLED Black';

  @override
  String get nordTheme => 'Nord';

  @override
  String get draculaTheme => 'Dracula';

  @override
  String get accentColor => '강조색';

  @override
  String get tabs => '탭';

  @override
  String get newTab => '새 탭';

  @override
  String get closeTab => '탭 닫기';

  @override
  String get pinTab => '탭 고정';

  @override
  String get unpinTab => '탭 고정 해제';

  @override
  String get duplicateTab => '탭 복제';

  @override
  String get closeOtherTabs => '다른 탭 닫기';

  @override
  String get bookmarks => '북마크';

  @override
  String get addBookmark => '북마크 추가';

  @override
  String get removeBookmark => '북마크 제거';

  @override
  String get recentLocations => '최근 위치';

  @override
  String get sandboxedPathWarning => '샌드박스 경로 - 찾아보기 버튼을 사용하여 실제 폴더를 선택하세요';

  @override
  String get permissionDenied => '권한이 거부되었습니다. 찾아보기 버튼을 사용하여 액세스 권한을 부여하세요.';

  @override
  String get accessCancelled => '액세스가 취소되었습니다. 대체 디렉터리를 사용합니다.';

  @override
  String deleteFailed(String error) {
    return '삭제 실패: $error';
  }

  @override
  String renameFailed(String error) {
    return '이름 변경 실패: $error';
  }

  @override
  String operationFailed(String error) {
    return '작업 실패: $error';
  }

  @override
  String get dropFilesToUpload => '파일을 여기에 드래그하여 업로드';

  @override
  String get confirmDeleteTitle => '삭제 확인';

  @override
  String confirmDeleteMessage(int count) {
    return '$count개 항목을 삭제하시겠습니까?';
  }

  @override
  String get multiCloudManager => '멀티 클라우드 관리자';

  @override
  String get addConnection => '연결 추가';

  @override
  String get cloudToCloudTransfer => '클라우드 간 전송';

  @override
  String get compareProviders => '공급자 비교';
}
