import 'package:flutter/widgets.dart';
import '../services/azure_hetzner_failure.dart';

String localizedAzureHetznerError(BuildContext context, AzureHetznerFailure error) =>
    localizedAzureHetznerErrorForLanguage(Localizations.maybeLocaleOf(context)?.languageCode ?? 'en', error);

String localizedAzureHetznerErrorForLanguage(String language, AzureHetznerFailure error) {
  final template = (_messages[language] ?? _messages['en']!)[error.code.name]!;
  return template.replaceAllMapped(RegExp(r'\{([A-Za-z]+)\}'), (match) {
    final value = error.arguments[match.group(1)];
    return value == null ? match.group(0)! : value.toString();
  });
}

const Map<String, Map<String, String>> _messages = {
  "en": {
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
    "hetznerDisconnected": "Not connected to Hetzner Storage Box."
  },
  "de": {
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
    "hetznerDisconnected": "Keine Verbindung zur Hetzner Storage Box."
  },
  "fr": {
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
    "hetznerDisconnected": "Non connecté à Hetzner Storage Box."
  },
  "es": {
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
    "hetznerDisconnected": "Sin conexión a Hetzner Storage Box."
  },
  "pt": {
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
    "hetznerDisconnected": "Sem ligação à Hetzner Storage Box."
  },
  "zh": {
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
    "hetznerDisconnected": "未连接到 Hetzner Storage Box。"
  },
  "ja": {
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
    "hetznerDisconnected": "Hetzner Storage Box に接続されていません。"
  },
  "ko": {
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
    "hetznerDisconnected": "Hetzner Storage Box에 연결되지 않았습니다."
  },
  "ar": {
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
    "hetznerDisconnected": "لا يوجد اتصال بـ Hetzner Storage Box."
  }
};
