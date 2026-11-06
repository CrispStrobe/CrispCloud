import 'package:flutter/widgets.dart';
import '../services/azure_hetzner_failure.dart';

String localizedAzureHetznerError(
  BuildContext context,
  AzureHetznerFailure error,
) => localizedAzureHetznerErrorForLanguage(
  Localizations.maybeLocaleOf(context)?.languageCode ?? 'en',
  error,
);

String localizedAzureHetznerErrorForLanguage(
  String language,
  AzureHetznerFailure error,
) {
  final template = (_messages[language] ?? _messages['en']!)[error.code.name]!;
  return template.replaceAllMapped(RegExp(r'\{([A-Za-z]+)\}'), (match) {
    final value = error.arguments[match.group(1)];
    return value == null ? match.group(0)! : value.toString();
  });
}

const Map<String, Map<String, String>> _messages = {
  "en": {
    "azureReadRange": "Invalid bounded read range.",
    "azureReadRangeIgnored": "Azure did not honor the requested read range.",
    "azureReadRangeInvalid": "Azure returned an invalid read range.",
    "azureReadRangeExceeded": "Azure exceeded the requested read range.",
    "azureReadRangeTruncated": "Azure returned a truncated read range.",

    "azureCredentials": "No saved Azure credentials found.",
    "azureConnectionString": "Invalid Azure connection string.",
    "azureContainer":
        "No container was specified and no default container is configured.",
    "azureHttp": "Azure Blob error {status}: {reason}\n{body}",
    "azureDownloadContainer": "A container cannot be downloaded as a file.",
    "azureCopyPaths":
        "Source and target must be blob paths, not container roots.",
    "azureBlobPath": "The path must point to a blob.",
    "azureTier": "Azure tier change failed (HTTP {status}): {body}",
    "azureStreamContainer": "A container cannot be streamed.",
    "azureStream": "Azure download stream failed (HTTP {status}).",
    "azureAccount": "Azure credentials do not contain an account name.",
    "hetznerCredentials": "No saved Hetzner credentials found.",
    "hetznerDisconnected": "Not connected to Hetzner Storage Box.",
  },
  "de": {
    "azureReadRange": "Ungültiger begrenzter Lesebereich.",
    "azureReadRangeIgnored":
        "Azure hat den angeforderten Lesebereich nicht eingehalten.",
    "azureReadRangeInvalid":
        "Azure hat einen ungültigen Lesebereich zurückgegeben.",
    "azureReadRangeExceeded":
        "Azure hat den angeforderten Lesebereich überschritten.",
    "azureReadRangeTruncated":
        "Azure hat einen unvollständigen Lesebereich zurückgegeben.",

    "azureCredentials": "Keine gespeicherten Azure-Zugangsdaten gefunden.",
    "azureConnectionString": "Ungültige Azure-Verbindungszeichenfolge.",
    "azureContainer":
        "Kein Container angegeben und kein Standardcontainer eingerichtet.",
    "azureHttp": "Azure-Blob-Fehler {status}: {reason}\n{body}",
    "azureDownloadContainer":
        "Ein Container kann nicht als Datei heruntergeladen werden.",
    "azureCopyPaths":
        "Quelle und Ziel müssen Blob-Pfade sein, keine Container-Stammverzeichnisse.",
    "azureBlobPath": "Der Pfad muss auf einen Blob zeigen.",
    "azureTier": "Azure-Tieränderung fehlgeschlagen (HTTP {status}): {body}",
    "azureStreamContainer": "Ein Container kann nicht gestreamt werden.",
    "azureStream": "Azure-Downloadstream fehlgeschlagen (HTTP {status}).",
    "azureAccount": "In den Azure-Zugangsdaten fehlt der Kontoname.",
    "hetznerCredentials": "Keine gespeicherten Hetzner-Zugangsdaten gefunden.",
    "hetznerDisconnected": "Keine Verbindung zur Hetzner Storage Box.",
  },
  "fr": {
    "azureReadRange": "Plage de lecture limitée invalide.",
    "azureReadRangeIgnored":
        "Azure n’a pas respecté la plage de lecture demandée.",
    "azureReadRangeInvalid": "Azure a renvoyé une plage de lecture invalide.",
    "azureReadRangeExceeded": "Azure a dépassé la plage de lecture demandée.",
    "azureReadRangeTruncated": "Azure a renvoyé une plage de lecture tronquée.",

    "azureCredentials": "Aucun identifiant Azure enregistré.",
    "azureConnectionString": "Chaîne de connexion Azure invalide.",
    "azureContainer":
        "Aucun conteneur indiqué et aucun conteneur par défaut configuré.",
    "azureHttp": "Erreur Azure Blob {status} : {reason}\n{body}",
    "azureDownloadContainer":
        "Un conteneur ne peut pas être téléchargé comme fichier.",
    "azureCopyPaths":
        "La source et la destination doivent être des chemins de blobs, pas des racines de conteneurs.",
    "azureBlobPath": "Le chemin doit désigner un blob.",
    "azureTier": "Échec du changement de niveau Azure (HTTP {status}) : {body}",
    "azureStreamContainer": "Un conteneur ne peut pas être diffusé.",
    "azureStream": "Échec du flux de téléchargement Azure (HTTP {status}).",
    "azureAccount": "Le nom du compte manque dans les identifiants Azure.",
    "hetznerCredentials": "Aucun identifiant Hetzner enregistré.",
    "hetznerDisconnected": "Non connecté à Hetzner Storage Box.",
  },
  "es": {
    "azureReadRange": "Intervalo de lectura limitado no válido.",
    "azureReadRangeIgnored":
        "Azure no respetó el intervalo de lectura solicitado.",
    "azureReadRangeInvalid":
        "Azure devolvió un intervalo de lectura no válido.",
    "azureReadRangeExceeded":
        "Azure superó el intervalo de lectura solicitado.",
    "azureReadRangeTruncated":
        "Azure devolvió un intervalo de lectura truncado.",

    "azureCredentials": "No se encontraron credenciales de Azure guardadas.",
    "azureConnectionString": "Cadena de conexión de Azure no válida.",
    "azureContainer":
        "No se indicó un contenedor ni se configuró uno predeterminado.",
    "azureHttp": "Error de Azure Blob {status}: {reason}\n{body}",
    "azureDownloadContainer":
        "Un contenedor no se puede descargar como archivo.",
    "azureCopyPaths":
        "El origen y el destino deben ser rutas de blobs, no raíces de contenedores.",
    "azureBlobPath": "La ruta debe apuntar a un blob.",
    "azureTier": "Falló el cambio de nivel de Azure (HTTP {status}): {body}",
    "azureStreamContainer": "No se puede transmitir un contenedor.",
    "azureStream": "Falló el flujo de descarga de Azure (HTTP {status}).",
    "azureAccount": "Falta el nombre de cuenta en las credenciales de Azure.",
    "hetznerCredentials":
        "No se encontraron credenciales de Hetzner guardadas.",
    "hetznerDisconnected": "Sin conexión a Hetzner Storage Box.",
  },
  "pt": {
    "azureReadRange": "Intervalo de leitura limitado inválido.",
    "azureReadRangeIgnored":
        "O Azure não respeitou o intervalo de leitura pedido.",
    "azureReadRangeInvalid":
        "O Azure devolveu um intervalo de leitura inválido.",
    "azureReadRangeExceeded": "O Azure excedeu o intervalo de leitura pedido.",
    "azureReadRangeTruncated":
        "O Azure devolveu um intervalo de leitura truncado.",

    "azureCredentials": "Não foram encontradas credenciais Azure guardadas.",
    "azureConnectionString": "Cadeia de ligação Azure inválida.",
    "azureContainer":
        "Não foi indicado um contentor nem configurado um predefinido.",
    "azureHttp": "Erro Azure Blob {status}: {reason}\n{body}",
    "azureDownloadContainer":
        "Um contentor não pode ser descarregado como ficheiro.",
    "azureCopyPaths":
        "A origem e o destino têm de ser caminhos de blobs, não raízes de contentores.",
    "azureBlobPath": "O caminho tem de apontar para um blob.",
    "azureTier": "Falha na alteração de nível Azure (HTTP {status}): {body}",
    "azureStreamContainer": "Não é possível transmitir um contentor.",
    "azureStream": "Falha no fluxo de transferência Azure (HTTP {status}).",
    "azureAccount": "Falta o nome da conta nas credenciais Azure.",
    "hetznerCredentials":
        "Não foram encontradas credenciais Hetzner guardadas.",
    "hetznerDisconnected": "Sem ligação à Hetzner Storage Box.",
  },
  "zh": {
    "azureReadRange": "受限读取范围无效。",
    "azureReadRangeIgnored": "Azure 未遵守请求的读取范围。",
    "azureReadRangeInvalid": "Azure 返回了无效的读取范围。",
    "azureReadRangeExceeded": "Azure 超出了请求的读取范围。",
    "azureReadRangeTruncated": "Azure 返回了不完整的读取范围。",

    "azureCredentials": "未找到已保存的 Azure 凭据。",
    "azureConnectionString": "Azure 连接字符串无效。",
    "azureContainer": "未指定容器，也未配置默认容器。",
    "azureHttp": "Azure Blob 错误 {status}：{reason}\n{body}",
    "azureDownloadContainer": "无法将容器作为文件下载。",
    "azureCopyPaths": "源和目标必须是 Blob 路径，而非容器根目录。",
    "azureBlobPath": "路径必须指向 Blob。",
    "azureTier": "Azure 层级更改失败（HTTP {status}）：{body}",
    "azureStreamContainer": "无法流式传输容器。",
    "azureStream": "Azure 下载流失败（HTTP {status}）。",
    "azureAccount": "Azure 凭据缺少账户名。",
    "hetznerCredentials": "未找到已保存的 Hetzner 凭据。",
    "hetznerDisconnected": "未连接到 Hetzner Storage Box。",
  },
  "ja": {
    "azureReadRange": "制限付き読み取り範囲が無効です。",
    "azureReadRangeIgnored": "Azure は要求された読み取り範囲に従いませんでした。",
    "azureReadRangeInvalid": "Azure が無効な読み取り範囲を返しました。",
    "azureReadRangeExceeded": "Azure が要求された読み取り範囲を超えました。",
    "azureReadRangeTruncated": "Azure が不完全な読み取り範囲を返しました。",

    "azureCredentials": "保存された Azure 認証情報が見つかりません。",
    "azureConnectionString": "Azure 接続文字列が無効です。",
    "azureContainer": "コンテナーが指定されておらず、既定のコンテナーも設定されていません。",
    "azureHttp": "Azure Blob エラー {status}: {reason}\n{body}",
    "azureDownloadContainer": "コンテナーをファイルとしてダウンロードできません。",
    "azureCopyPaths": "コピー元とコピー先にはコンテナーのルートではなく Blob パスを指定してください。",
    "azureBlobPath": "パスには Blob を指定してください。",
    "azureTier": "Azure 層の変更に失敗しました（HTTP {status}）: {body}",
    "azureStreamContainer": "コンテナーをストリームできません。",
    "azureStream": "Azure ダウンロードストリームに失敗しました（HTTP {status}）。",
    "azureAccount": "Azure 認証情報にアカウント名がありません。",
    "hetznerCredentials": "保存された Hetzner 認証情報が見つかりません。",
    "hetznerDisconnected": "Hetzner Storage Box に接続されていません。",
  },
  "ko": {
    "azureReadRange": "제한된 읽기 범위가 잘못되었습니다.",
    "azureReadRangeIgnored": "Azure가 요청한 읽기 범위를 준수하지 않았습니다.",
    "azureReadRangeInvalid": "Azure가 잘못된 읽기 범위를 반환했습니다.",
    "azureReadRangeExceeded": "Azure가 요청한 읽기 범위를 초과했습니다.",
    "azureReadRangeTruncated": "Azure가 불완전한 읽기 범위를 반환했습니다.",

    "azureCredentials": "저장된 Azure 자격 증명을 찾을 수 없습니다.",
    "azureConnectionString": "잘못된 Azure 연결 문자열입니다.",
    "azureContainer": "컨테이너가 지정되지 않았고 기본 컨테이너도 설정되지 않았습니다.",
    "azureHttp": "Azure Blob 오류 {status}: {reason}\n{body}",
    "azureDownloadContainer": "컨테이너를 파일로 다운로드할 수 없습니다.",
    "azureCopyPaths": "원본과 대상은 컨테이너 루트가 아닌 Blob 경로여야 합니다.",
    "azureBlobPath": "경로가 Blob을 가리켜야 합니다.",
    "azureTier": "Azure 계층 변경 실패 (HTTP {status}): {body}",
    "azureStreamContainer": "컨테이너를 스트리밍할 수 없습니다.",
    "azureStream": "Azure 다운로드 스트림 실패 (HTTP {status}).",
    "azureAccount": "Azure 자격 증명에 계정 이름이 없습니다.",
    "hetznerCredentials": "저장된 Hetzner 자격 증명을 찾을 수 없습니다.",
    "hetznerDisconnected": "Hetzner Storage Box에 연결되지 않았습니다.",
  },
  "ar": {
    "azureReadRange": "نطاق القراءة المحدود غير صالح.",
    "azureReadRangeIgnored": "لم يلتزم Azure بنطاق القراءة المطلوب.",
    "azureReadRangeInvalid": "أعاد Azure نطاق قراءة غير صالح.",
    "azureReadRangeExceeded": "تجاوز Azure نطاق القراءة المطلوب.",
    "azureReadRangeTruncated": "أعاد Azure نطاق قراءة غير مكتمل.",

    "azureCredentials": "لم يتم العثور على بيانات اعتماد Azure محفوظة.",
    "azureConnectionString": "سلسلة اتصال Azure غير صالحة.",
    "azureContainer": "لم يتم تحديد حاوية ولم يتم إعداد حاوية افتراضية.",
    "azureHttp": "خطأ Azure Blob ‏{status}: {reason}\n{body}",
    "azureDownloadContainer": "لا يمكن تنزيل الحاوية كملف.",
    "azureCopyPaths":
        "يجب أن يكون المصدر والوجهة مساري Blob وليس جذري حاويتين.",
    "azureBlobPath": "يجب أن يشير المسار إلى Blob.",
    "azureTier": "فشل تغيير مستوى Azure ‏(HTTP {status}): {body}",
    "azureStreamContainer": "لا يمكن بث حاوية.",
    "azureStream": "فشل تدفق تنزيل Azure ‏(HTTP {status}).",
    "azureAccount": "اسم الحساب مفقود من بيانات اعتماد Azure.",
    "hetznerCredentials": "لم يتم العثور على بيانات اعتماد Hetzner محفوظة.",
    "hetznerDisconnected": "لا يوجد اتصال بـ Hetzner Storage Box.",
  },
};
