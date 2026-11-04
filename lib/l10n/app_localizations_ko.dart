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
  String get ok => '확인';

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
  String get oledTheme => 'OLED 블랙';

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

  @override
  String get singlePanel => '단일 패널';

  @override
  String get dualPanel => '이중 패널';

  @override
  String get showTreeSidebar => '트리 사이드바 표시';

  @override
  String get hideTreeSidebar => '트리 사이드바 숨기기';

  @override
  String get detailsList => '상세 목록';

  @override
  String get largeItems => '큰 항목';

  @override
  String get compactItems => '간결한 항목';

  @override
  String get showPreview => '미리 보기 표시';

  @override
  String get hidePreview => '미리 보기 숨기기';

  @override
  String get showTerminal => '터미널 표시';

  @override
  String get hideTerminal => '터미널 숨기기';

  @override
  String get moreActions => '추가 작업';

  @override
  String get mountAsDrive => '드라이브로 마운트';

  @override
  String get auditLog => '감사 로그';

  @override
  String get systemLog => '시스템 로그';

  @override
  String get cacheSettings => '캐시 설정';

  @override
  String get keyboardShortcuts => '키보드 단축키';

  @override
  String get swapPanels => '패널 교환';

  @override
  String get connectToCloud => '클라우드에 연결';

  @override
  String browseProvider(String provider) {
    return '$provider 탐색';
  }

  @override
  String get pleaseConnectRemote => '원격 파일에 액세스하려면 연결하세요';

  @override
  String get notConnected => '연결되지 않음';

  @override
  String get connectToCloudShort => '클라우드에 연결';

  @override
  String get loggedIn => '로그인됨';

  @override
  String get localFiles => '로컬 파일';

  @override
  String get remoteFiles => '원격 파일';

  @override
  String get bookmarkFolder => '현재 폴더 북마크';

  @override
  String get noFolders => '폴더가 없습니다';

  @override
  String get selectFileToPreview => '미리 볼 파일 선택';

  @override
  String fileTooLarge(String size) {
    return '파일이 너무 커서 미리 볼 수 없습니다 ($size)';
  }

  @override
  String previewFailed(String error) {
    return '미리 보기 실패: $error';
  }

  @override
  String get firstPage => '첫 페이지';

  @override
  String get previousPage => '이전 페이지';

  @override
  String get nextPage => '다음 페이지';

  @override
  String get lastPage => '마지막 페이지';

  @override
  String get playAudio => '오디오 재생';

  @override
  String get playVideo => '동영상 재생';

  @override
  String get emptyFile => '빈 파일';

  @override
  String systemLogTitle(int count) {
    return '시스템 로그 ($count개 항목)';
  }

  @override
  String get minimumLevel => '최소 수준';

  @override
  String get pauseAutoScroll => '자동 스크롤 일시 정지';

  @override
  String get resumeAutoScroll => '자동 스크롤 재개';

  @override
  String get copyVisible => '표시된 내용 복사';

  @override
  String get copyAll => '모두 복사';

  @override
  String get filterLogs => '로그 필터링...';

  @override
  String get visibleLinesCopied => '표시된 줄을 복사했습니다';

  @override
  String get allLogsCopied => '모든 로그를 복사했습니다';

  @override
  String get open => '열기';

  @override
  String get editSystemEditor => '편집 (시스템 편집기)';

  @override
  String get editBuiltIn => '편집 (내장 편집기)';

  @override
  String get openWithSystemApp => '시스템 앱으로 열기';

  @override
  String get verifyAgainstRemote => '원격 파일과 비교';

  @override
  String get browseArchive => '압축 파일 탐색';

  @override
  String get archiveExtracted => '압축 파일을 추출했습니다';

  @override
  String get revealInFinder => 'Finder에서 보기';

  @override
  String get showInExplorer => '탐색기에서 보기';

  @override
  String get openContainingFolder => '포함된 폴더 열기';

  @override
  String get properties => '속성';

  @override
  String get copyNames => '이름 복사';

  @override
  String get copyPaths => '경로 복사';

  @override
  String get createMd5 => '.md5 파일 만들기';

  @override
  String get verifyChecksumFile => '체크섬 파일 확인';

  @override
  String get splitFile => '파일 분할';

  @override
  String get combineParts => '분할 파일 합치기';

  @override
  String get createLink => '링크 만들기...';

  @override
  String get secureWipe => '안전하게 지우기';

  @override
  String confirmDeleteBody(int count) {
    return '항목 $count개를 삭제하시겠습니까?';
  }

  @override
  String totalSize(String size) {
    return '전체 크기: $size';
  }

  @override
  String get cannotBeUndone => '이 작업은 취소할 수 없습니다.';

  @override
  String nItems(int count) {
    return '항목 $count개';
  }

  @override
  String nTransfers(int count) {
    return '전송 $count개';
  }

  @override
  String get syncing => '동기화 중';

  @override
  String lastSyncChanges(int count) {
    return '마지막 동기화: 변경 $count건';
  }

  @override
  String nPairs(int count) {
    return '쌍 $count개';
  }

  @override
  String get hidden => '숨김';

  @override
  String free(String size) {
    return '여유 공간: $size';
  }

  @override
  String get aboutLegal => '정보 / 법적 고지';

  @override
  String get appDescription => 'Filen.io, SFTP 및 WebDAV용 비공식 오픈 소스 클라이언트입니다.';

  @override
  String get serviceProvider => '서비스 공급자';

  @override
  String get contact => '연락처';

  @override
  String get disclaimer => '면책 조항';

  @override
  String get disclaimerText =>
      '이 소프트웨어는 어떠한 보증 없이 있는 그대로 제공됩니다. 이 앱은 Filen.io 또는 다른 클라우드 공급자와 제휴하지 않았습니다.';

  @override
  String get sourceCode => '소스 코드 (GitHub)';

  @override
  String get website => '웹사이트';

  @override
  String get viewLicenses => '오픈 소스 라이선스 보기';

  @override
  String get flatView => '평면 보기 (모든 하위 폴더)';

  @override
  String get exitFlatView => '평면 보기 종료';

  @override
  String get showHiddenFiles => '숨김 파일 표시';

  @override
  String get hideHiddenFiles => '숨김 파일 숨기기';

  @override
  String get touchFriendlyView => '터치 친화적 보기로 전환';

  @override
  String get compactView => '간결한 보기로 전환';

  @override
  String get sort => '정렬';

  @override
  String get secondarySort => '보조 정렬';

  @override
  String get none => '없음';

  @override
  String get byName => '이름순';

  @override
  String get bySize => '크기순';

  @override
  String get byDate => '날짜순';

  @override
  String get enterPath => '경로 입력...';

  @override
  String get editPath => '경로 편집';

  @override
  String get searchResults => '검색 결과';

  @override
  String nFiles(int count) {
    return '파일 $count개';
  }

  @override
  String copyNItems(int count) {
    return '항목 $count개 복사';
  }

  @override
  String moveNItems(int count) {
    return '항목 $count개 이동';
  }

  @override
  String get targetPath => '대상 경로';

  @override
  String saved(String name) {
    return '$name 저장됨';
  }

  @override
  String saveFailed(String error) {
    return '저장 실패: $error';
  }

  @override
  String get unsavedChanges => '저장되지 않은 변경 사항';

  @override
  String get discardChanges => '저장되지 않은 변경 사항이 있습니다. 버리시겠습니까?';

  @override
  String get discard => '버리기';

  @override
  String get saveShortcut => '저장 (Ctrl+S)';

  @override
  String get fileModifiedOnServer => '파일을 연 후 서버에서 수정되었습니다.';

  @override
  String get saveAnyway => '그래도 저장';

  @override
  String get reload => '다시 불러오기';

  @override
  String get saveProfile => '프로필 저장';

  @override
  String get profileName => '프로필 이름';

  @override
  String get profileNameHint => '예: 업무용 S3, 개인용 SFTP';

  @override
  String profileSaved(String name) {
    return '프로필 \"$name\" 저장됨';
  }

  @override
  String get connectToCloudStorage => '클라우드 저장소에 연결';

  @override
  String get savedProfiles => '저장된 프로필';

  @override
  String get loadProfile => '저장된 프로필 불러오기...';

  @override
  String get deleteProfile => '프로필 삭제';

  @override
  String get saveAsProfile => '프로필로 저장';

  @override
  String get enableEncryption => '클라이언트 측 암호화 활성화';

  @override
  String get encryptBeforeUpload => '업로드 전에 파일 암호화 (AES-256-GCM)';

  @override
  String get encryptionPassphrase => '암호화 암호문구';

  @override
  String get appLocked => 'CrispCloud가 잠겨 있습니다';

  @override
  String get enterPinToContinue => '계속하려면 PIN 또는 비밀번호를 입력하세요';

  @override
  String get pinPassword => 'PIN / 비밀번호';

  @override
  String get incorrectPin => 'PIN 또는 비밀번호가 올바르지 않습니다';

  @override
  String get tooManyAttempts => '실패 횟수가 너무 많습니다. 다시 시도하려면 앱을 다시 시작하세요.';

  @override
  String attemptsRemaining(int count) {
    return '남은 시도 횟수: $count회';
  }

  @override
  String get appLockSetup => '앱 잠금 설정';

  @override
  String get changeAppLockCode => '앱 잠금 변경';

  @override
  String get currentPin => '현재 PIN / 비밀번호';

  @override
  String get newPin => '새 PIN / 비밀번호';

  @override
  String get confirmPin => 'PIN / 비밀번호 확인';

  @override
  String get minFourChars => '최소 4자';

  @override
  String get codesDoNotMatch => '코드가 일치하지 않습니다';

  @override
  String get autoLockAfter => '자동 잠금 시간';

  @override
  String get immediately => '즉시';

  @override
  String get oneMinute => '1분';

  @override
  String get fiveMinutes => '5분';

  @override
  String get fifteenMinutes => '15분';

  @override
  String get thirtyMinutes => '30분';

  @override
  String get oneHour => '1시간';

  @override
  String get connectToHetzner => 'Hetzner Storage Box에 연결';

  @override
  String get sftpPort23 => 'SFTP (포트 23)';

  @override
  String get webdavHttps => 'WebDAV (HTTPS)';

  @override
  String get testConnection => '연결 테스트';

  @override
  String get connectionSuccessful => '연결 성공';

  @override
  String testFailed(String error) {
    return '테스트 실패: $error';
  }

  @override
  String get connectToAzure => 'Azure Blob Storage에 연결';

  @override
  String get authenticationMode => '인증 방식';

  @override
  String get accountName => '계정 이름';

  @override
  String get container => '컨테이너';

  @override
  String get sasUrl => 'SAS URL';

  @override
  String get sasToken => 'SAS 토큰';

  @override
  String get connectToB2 => 'Backblaze B2에 연결';

  @override
  String get applicationKeyId => '애플리케이션 키 ID';

  @override
  String get applicationKey => '애플리케이션 키';

  @override
  String get bucketNameOptional => '버킷 이름 (선택 사항)';

  @override
  String get mount => '마운트';

  @override
  String get unmount => '마운트 해제';

  @override
  String get displayName => '표시 이름';

  @override
  String get localMountPoint => '로컬 마운트 지점';

  @override
  String get newMount => '새 마운트';

  @override
  String get noMountsConfigured => '설정된 마운트가 없습니다';

  @override
  String get fuseDesktopOnly =>
      'FUSE 마운트는 macOS, Linux 및 Windows 데스크톱에서만 사용할 수 있습니다.';

  @override
  String get multiCloud => '멀티 클라우드';

  @override
  String get connections => '연결';

  @override
  String get transfer => '전송';

  @override
  String get compareAndSearch => '비교 및 검색';

  @override
  String get noConnectionsYet => '등록된 연결이 없습니다.';

  @override
  String get startTransfer => '전송 시작';

  @override
  String get syncPairs => '동기화 쌍';

  @override
  String get enableAutoSync => '자동 동기화 켜기';

  @override
  String get disableAutoSync => '자동 동기화 끄기';

  @override
  String get noSyncPairs => '설정된 동기화 쌍이 없습니다';

  @override
  String get replayOffline => '오프라인 작업 재실행';

  @override
  String get newSyncPair => '새 동기화 쌍';

  @override
  String get cacheUsage => '캐시 사용량';

  @override
  String get maximumCacheSize => '최대 캐시 크기';

  @override
  String get clearCacheConfirm => '캐시된 파일을 모두 삭제하시겠습니까? 필요할 때 다시 다운로드됩니다.';

  @override
  String batchRenameTitle(int count) {
    return '일괄 이름 변경 (파일 $count개)';
  }

  @override
  String get findReplace => '찾기/바꾸기';

  @override
  String get number => '번호 매기기';

  @override
  String get prefixSuffix => '접두사/접미사';

  @override
  String get extension => '확장자';

  @override
  String get duplicateFinder => '중복 파일 찾기';

  @override
  String get noDuplicatesFound => '중복 파일이 없습니다!';

  @override
  String get chooseTheme => '테마 선택';

  @override
  String get checkForUpdates => '업데이트 확인';

  @override
  String get youAreUpToDate => '최신 버전입니다';

  @override
  String get updateAvailable => '업데이트가 있습니다';

  @override
  String get releaseNotes => '릴리스 정보';

  @override
  String get checkNow => '지금 확인';

  @override
  String get general => '일반';

  @override
  String get accessibility => '접근성';

  @override
  String get privacy => '개인정보 보호';

  @override
  String get advanced => '고급';

  @override
  String get showFKeyButtons => '화면 하단에 F3-F8 단축 버튼 표시';

  @override
  String get exportKeys => '암호화 키 내보내기/가져오기';

  @override
  String get backupRecovery => 'BIP39 복구 문구 백업 및 복구';

  @override
  String get noActiveOperations => '진행 중인 작업 없음';

  @override
  String get refreshAll => '모두 새로고침';

  @override
  String get newName => '새 이름';

  @override
  String get items => '항목:';

  @override
  String andMore(int count) {
    return '... 외 $count개';
  }

  @override
  String get searchPattern => '검색 패턴';

  @override
  String get findPattern => '찾기 패턴';

  @override
  String get searchHint => '파일 검색...';

  @override
  String get findHint => '예: *.pdf, report*';

  @override
  String get noResultsFound => '결과가 없습니다';

  @override
  String get size => '크기';

  @override
  String get date => '날짜';

  @override
  String get name => '이름';

  @override
  String get type => '유형';

  @override
  String get created => '생성됨';

  @override
  String get accessed => '접근함';

  @override
  String get computeMd5 => 'MD5 계산';

  @override
  String get protocol => '프로토콜';
}
