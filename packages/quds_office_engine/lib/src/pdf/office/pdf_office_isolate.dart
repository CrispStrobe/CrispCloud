import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../file/cos/pdf_open_error.dart';
import '../file/model/pdf_file.dart';
import 'pdf_office_model.dart';
import 'pdf_to_office.dart';

/// A limit hit while exporting, safe to send out of the worker isolate.
class PdfOfficeExportNote {
  /// PdfOfficeExportNote API.
  const PdfOfficeExportNote({
    required this.page,
    required this.kind,
    required this.message,
  });

  /// Zero-based page, when the note is about one page.
  final int? page;

  /// [PdfOfficeNoticeKind] name, or `jpegOnSlide`.
  final String kind;

  /// Engine message. The host may translate [kind] instead.
  final String message;
}

/// Progress of [pdfOfficeExportJob]. [stage] is `open`, `page`, or `write`.
class PdfOfficeExportProgress {
  /// PdfOfficeExportProgress API.
  const PdfOfficeExportProgress({
    required this.stage,
    required this.current,
    required this.total,
  });

  /// `open`, `page`, or `write`.
  final String stage;

  /// Finished steps. For `page`, the page now being read, starting at 1.
  final int current;

  /// Page count once the file is open. Zero during `open`.
  final int total;
}

/// Office bytes, or [error] as a [PdfOpenError] name or `cancelled`.
class PdfOfficeExportResult {
  /// PdfOfficeExportResult API.
  const PdfOfficeExportResult({
    this.bytes,
    this.notes = const <PdfOfficeExportNote>[],
    this.error,
  });

  /// DOCX, XLSX, or PPTX bytes.
  final Uint8List? bytes;

  /// notes API.
  final List<PdfOfficeExportNote> notes;

  /// Null when [bytes] is set.
  final String? error;
}

/// Message for [pdfOfficeExportJob].
class PdfOfficeExportJob {
  /// PdfOfficeExportJob API.
  const PdfOfficeExportJob({
    required this.bytes,
    required this.extension,
    required this.port,
    this.password,
  });

  /// PDF bytes.
  final Uint8List bytes;

  /// Password when the file is encrypted.
  final String? password;

  /// `docx`, `xlsx`, or `pptx`.
  final String extension;

  /// Receives [PdfOfficeExportProgress] then one [PdfOfficeExportResult].
  final SendPort port;
}

/// A running export. [cancel] stops the worker isolate.
class PdfOfficeExportRun {
  /// PdfOfficeExportRun API.
  PdfOfficeExportRun(this.done, this._cancel);

  /// Completes with the Office bytes or an [PdfOfficeExportResult.error].
  final Future<PdfOfficeExportResult> done;

  final void Function() _cancel;

  /// Stops the worker. [done] then completes with error `cancelled`.
  void cancel() => _cancel();
}

/// Reads [job] on this isolate and sends progress, then one result.
void pdfOfficeExportJob(PdfOfficeExportJob job) {
  try {
    job.port.send(
      const PdfOfficeExportProgress(stage: 'open', current: 0, total: 0),
    );
    final PdfFile file = PdfFile.open(job.bytes, password: job.password);
    final PdfOfficeRecovery recovery = PdfToOffice.recover(
      file,
      onPage: (int index, int count) {
        job.port.send(
          PdfOfficeExportProgress(
            stage: 'page',
            current: index + 1,
            total: count,
          ),
        );
      },
    );
    final int count = recovery.pages.length;
    job.port.send(
      PdfOfficeExportProgress(
        stage: 'write',
        current: count,
        total: count == 0 ? 1 : count,
      ),
    );
    final Uint8List out = switch (job.extension) {
      'docx' => PdfToOffice.docxFrom(recovery),
      'xlsx' => PdfToOffice.xlsxFrom(recovery),
      'pptx' => PdfToOffice.pptxFrom(recovery),
      _ => throw ArgumentError(job.extension),
    };
    job.port.send(
      PdfOfficeExportResult(
        bytes: out,
        notes: <PdfOfficeExportNote>[
          for (final PdfOfficeNotice notice in recovery.notices)
            PdfOfficeExportNote(
              page: notice.pageIndex,
              kind: notice.kind.name,
              message: notice.message,
            ),
          if (job.extension == 'pptx')
            for (final PdfOfficePage page in recovery.pages)
              if (page.images.any(
                (PdfOfficeImage image) => image.mime == 'image/jpeg',
              ))
                PdfOfficeExportNote(
                  page: page.index,
                  kind: 'jpegOnSlide',
                  message: '',
                ),
        ],
      ),
    );
  } on PdfOpenException catch (error) {
    job.port.send(PdfOfficeExportResult(error: error.error.name));
  } on Object catch (error) {
    job.port.send(PdfOfficeExportResult(error: '$error'));
  }
}

/// Starts [pdfOfficeExportJob] and forwards its progress to [onProgress].
Future<PdfOfficeExportRun> startPdfOfficeExport({
  required Uint8List bytes,
  required String extension,
  String? password,
  required void Function(PdfOfficeExportProgress progress) onProgress,
}) async {
  final ReceivePort receive = ReceivePort();
  final ReceivePort errors = ReceivePort();
  final ReceivePort exits = ReceivePort();
  final Completer<PdfOfficeExportResult> done =
      Completer<PdfOfficeExportResult>();

  void finish(PdfOfficeExportResult result) {
    if (done.isCompleted) {
      return;
    }
    done.complete(result);
    receive.close();
    errors.close();
    exits.close();
  }

  var cancelRequested = false;
  receive.listen((Object? message) {
    if (message is PdfOfficeExportProgress) {
      onProgress(message);
    } else if (message is PdfOfficeExportResult) {
      finish(message);
    }
  });
  errors.listen((Object? message) {
    finish(PdfOfficeExportResult(error: '$message'));
  });
  exits.listen((Object? message) {
    if (cancelRequested) {
      finish(const PdfOfficeExportResult(error: 'cancelled'));
    }
  });
  final Isolate isolate;
  try {
    isolate = await Isolate.spawn(
      pdfOfficeExportJob,
      PdfOfficeExportJob(
        bytes: bytes,
        password: password,
        extension: extension,
        port: receive.sendPort,
      ),
      onError: errors.sendPort,
      onExit: exits.sendPort,
    );
  } on Object catch (error) {
    finish(PdfOfficeExportResult(error: '$error'));
    return PdfOfficeExportRun(done.future, () {});
  }
  return PdfOfficeExportRun(done.future, () {
    cancelRequested = true;
    isolate.kill(priority: Isolate.immediate);
  });
}
