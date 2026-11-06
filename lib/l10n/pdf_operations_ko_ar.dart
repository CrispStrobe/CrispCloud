/// Korean and Arabic labels for host-owned PDF operations.
const pdfOperationsKoAr = <String, Map<String, String>>{
  'ko': {
    "Edit PDF": "PDF 편집",
    "Merge selected PDFs": "선택한 PDF 병합",
    "Extract these pages": "이 페이지 추출",
    "Rotate selected pages": "선택한 페이지 회전",
    "Reorder PDF pages": "PDF 페이지 순서 변경",
    "Delete PDF pages": "PDF 페이지 삭제",
    "Add a watermark": "워터마크 추가",
    "Fill known form fields": "이름이 있는 양식 필드 채우기",
    "Insert an image": "이미지 삽입",
    "Import OCR text": "OCR 텍스트 가져오기",
    "Could not start PDF operation": "PDF 작업을 시작할 수 없습니다",
    "Password required": "암호 필요",
    "Password": "암호",
    "Incorrect password. Try again.": "암호가 올바르지 않습니다. 다시 시도하세요.",
    "Open": "열기",
    "Cancel": "취소",
    "Close": "닫기",
    "Retry": "다시 시도",
    "Font size": "글꼴 크기",
    "Angle": "각도",
    "Margin (points)": "여백 (포인트)",
    "Width (%)": "너비 (%)",
    "Height (%)": "높이 (%)",
    "Left (%)": "왼쪽 (%)",
    "Top (%)": "위쪽 (%)",
    "Choose a PNG or JPEG image.": "PNG 또는 JPEG 이미지를 선택하세요.",
    "The selected file could not be read.": "선택한 파일을 읽을 수 없습니다.",
    "Choose a new PDF file name without a folder path.":
        "폴더 경로 없이 새 PDF 파일 이름을 지정하세요.",
    "Download started. Keep the downloaded file before closing.":
        "다운로드가 시작되었습니다. 닫기 전에 다운로드한 파일을 보관하세요.",
    "PDF copy saved.": "PDF 사본을 저장했습니다.",
    "Close after downloading?": "다운로드 후 닫으시겠습니까?",
    "Close without saving?": "저장하지 않고 닫으시겠습니까?",
    "Make sure the downloaded PDF is available before closing.":
        "닫기 전에 다운로드한 PDF를 사용할 수 있는지 확인하세요.",
    "The generated PDF has not been saved. You can return to the preview to save or export it.":
        "생성된 PDF가 저장되지 않았습니다. 미리 보기로 돌아가 저장하거나 내보낼 수 있습니다.",
    "Return to preview": "미리 보기로 돌아가기",
    "Pages": "페이지",
    "pages": "페이지",
    "New page order": "새 페이지 순서",
    "List every page once, for example 3,1,2 or 5-1.":
        "각 페이지를 한 번씩 나열하세요. 예: 3,1,2 또는 5-1.",
    "Use all, 1-3,7, or a descending range such as 5-1.":
        "all, 1-3,7 또는 5-1과 같은 역순 범위를 사용하세요.",
    "PDFs are merged in the order below. Choose pages from each source.":
        "아래 순서대로 PDF를 병합합니다. 각 원본에서 페이지를 선택하세요.",
    "Move up": "위로 이동",
    "Move down": "아래로 이동",
    "Choose PNG / JPEG": "PNG / JPEG 선택",
    "Font": "글꼴",
    "Choose TTF / OTF": "TTF / OTF 선택",
    "Opacity": "불투명도",
    "Bake the new marks into page content": "새 표시를 페이지 콘텐츠에 병합",
    "Turn off to keep the new marks as editable annotations. Existing annotations and form fields are preserved.":
        "새 표시를 편집 가능한 주석으로 유지하려면 끄세요. 기존 주석과 양식 필드는 유지됩니다.",
    "Text": "텍스트",
    "Logo / image": "로고 / 이미지",
    "Watermark text": "워터마크 텍스트",
    "Position": "위치",
    "Watermarks are placed over page content. Review the generated preview before saving.":
        "워터마크는 페이지 콘텐츠 위에 배치됩니다. 저장하기 전에 생성된 미리 보기를 확인하세요.",
    "Top left": "왼쪽 위",
    "Top center": "가운데 위",
    "Top right": "오른쪽 위",
    "Center left": "왼쪽 가운데",
    "Center": "가운데",
    "Center right": "오른쪽 가운데",
    "Bottom left": "왼쪽 아래",
    "Bottom center": "가운데 아래",
    "Bottom right": "오른쪽 아래",
    "Placement is measured from the visible top-left corner of each page, including rotated pages.":
        "위치는 회전된 페이지를 포함하여 각 페이지에 보이는 왼쪽 위 모서리를 기준으로 측정합니다.",
    "Blank keeps aspect ratio": "비워 두면 가로세로 비율 유지",
    "This PDF has no named AcroForm fields. Open the editor to place text or create form fields.":
        "이 PDF에는 이름이 있는 AcroForm 필드가 없습니다. 편집기를 열어 텍스트를 배치하거나 양식 필드를 만드세요.",
    "Only changed fields are written. Field names and option values must match the PDF exactly. Password, signature, and read-only fields cannot be batch-filled.":
        "변경된 필드만 기록합니다. 필드 이름과 옵션 값은 PDF와 정확히 일치해야 합니다. 암호, 서명 및 읽기 전용 필드는 일괄 입력할 수 없습니다.",
    "Fields": "필드",
    "Import JSON": "JSON 가져오기",
    "Field name → value": "필드 이름 → 값",
    "Text: string; checkbox: true/false; radio/choice: option value; multiple choice: array of values.":
        "텍스트: 문자열; 체크박스: true/false; 라디오/선택: 옵션 값; 다중 선택: 값 배열.",
    "Known field names": "알려진 필드 이름",
    "OCR data exceeds 16 MiB.": "OCR 데이터가 16 MiB를 초과합니다.",
    "OCR data must be a JSON array of pages with text spans.":
        "OCR 데이터는 텍스트 영역을 포함하는 페이지의 JSON 배열이어야 합니다.",
    "Minimum confidence (0–1)": "최소 신뢰도 (0–1)",
    "Import text already recognized by an OCR tool. This action does not recognize images or contact a recognition service.":
        "OCR 도구가 이미 인식한 텍스트를 가져옵니다. 이 작업은 이미지를 인식하거나 인식 서비스에 연결하지 않습니다.",
    "Use one-based page numbers. Each span needs text and bounds [left, bottom, right, top] in PDF points, not image pixels. Confidence is optional and defaults to 1.":
        "페이지 번호는 1부터 시작합니다. 각 영역에는 텍스트와 경계 [left, bottom, right, top]가 필요하며 단위는 이미지 픽셀이 아닌 PDF 포인트입니다. 신뢰도는 선택 사항이며 기본값은 1입니다.",
    "Import OCR JSON": "OCR JSON 가져오기",
    "Recognized page spans (JSON)": "인식된 페이지 텍스트 영역 (JSON)",
    "Skip pages that already contain text": "이미 텍스트가 있는 페이지 건너뛰기",
    "Turning this off appends another text layer and can duplicate existing searchable text.":
        "이 옵션을 끄면 텍스트 레이어가 추가되어 기존의 검색 가능한 텍스트가 중복될 수 있습니다.",
    "The added text is invisible. Select or search text in the generated preview to check the result.":
        "추가된 텍스트는 보이지 않습니다. 생성된 미리 보기에서 텍스트를 선택하거나 검색하여 결과를 확인하세요.",
    "Search preview text": "미리 보기 텍스트 검색",
    "Clear search": "검색 지우기",
    "Previous match": "이전 일치 항목",
    "Next match": "다음 일치 항목",
    "required": "필수",
    "read-only": "읽기 전용",
    "password": "암호",
    "Rotation": "회전",
    "90° clockwise": "시계 방향 90°",
    "90° counterclockwise": "반시계 방향 90°",
    "At least one page must remain. Deleting pages is a page organization action; it is not secure content removal.":
        "최소 한 페이지는 남아 있어야 합니다. 페이지 삭제는 페이지를 정리하는 작업이며 콘텐츠를 안전하게 제거하는 작업이 아닙니다.",
    "Allow an unprotected output when required": "필요한 경우 보호되지 않은 출력 허용",
    "Page extraction can remove password protection. Merge output follows the first PDF’s encryption. Only continue if that output is appropriate.":
        "페이지를 추출하면 암호 보호가 제거될 수 있습니다. 병합 결과에는 첫 번째 PDF의 암호화가 적용됩니다. 해당 출력이 적절한 경우에만 계속하세요.",
    "Review the generated PDF, then save a new copy or export it to your device.":
        "생성된 PDF를 확인한 다음 새 사본을 저장하거나 기기로 내보내세요.",
    "Review output notes": "출력 참고 사항 확인",
    "Output file name": "출력 파일 이름",
    "New copy beside": "원본 옆에 새 사본",
    "Back to options": "옵션으로 돌아가기",
    "Preview PDF": "PDF 미리 보기",
    "Download PDF": "PDF 다운로드",
    "Export PDF": "PDF 내보내기",
    "Save new copy": "새 사본 저장",
    "Reading PDFs…": "PDF 읽는 중…",
    "Selected PDFs exceed the 256 MiB input limit.":
        "선택한 PDF가 입력 제한인 256 MiB를 초과합니다.",
    "Insert protected pages?": "보호된 페이지를 삽입하시겠습니까?",
    "The inserted pages will use this document’s protection. This document has no password protection.":
        "삽입된 페이지에는 이 문서의 보호 설정이 적용됩니다. 이 문서는 암호로 보호되어 있지 않습니다.",
  },
  'ar': {
    "Edit PDF": "تحرير PDF",
    "Merge selected PDFs": "دمج ملفات PDF المحددة",
    "Extract these pages": "استخراج هذه الصفحات",
    "Rotate selected pages": "تدوير الصفحات المحددة",
    "Reorder PDF pages": "إعادة ترتيب صفحات PDF",
    "Delete PDF pages": "حذف صفحات PDF",
    "Add a watermark": "إضافة علامة مائية",
    "Fill known form fields": "تعبئة حقول النموذج ذات الأسماء المعروفة",
    "Insert an image": "إدراج صورة",
    "Import OCR text": "استيراد نص OCR",
    "Could not start PDF operation": "تعذر بدء عملية PDF",
    "Password required": "كلمة المرور مطلوبة",
    "Password": "كلمة المرور",
    "Incorrect password. Try again.": "كلمة المرور غير صحيحة. حاول مجددًا.",
    "Open": "فتح",
    "Cancel": "إلغاء",
    "Close": "إغلاق",
    "Retry": "إعادة المحاولة",
    "Font size": "حجم الخط",
    "Angle": "الزاوية",
    "Margin (points)": "الهامش (نقاط)",
    "Width (%)": "العرض (%)",
    "Height (%)": "الارتفاع (%)",
    "Left (%)": "من اليسار (%)",
    "Top (%)": "من الأعلى (%)",
    "Choose a PNG or JPEG image.": "اختر صورة PNG أو JPEG.",
    "The selected file could not be read.": "تعذرت قراءة الملف المحدد.",
    "Choose a new PDF file name without a folder path.":
        "اختر اسمًا جديدًا لملف PDF دون مسار مجلد.",
    "Download started. Keep the downloaded file before closing.":
        "بدأ التنزيل. احتفظ بالملف المنزّل قبل الإغلاق.",
    "PDF copy saved.": "تم حفظ نسخة PDF.",
    "Close after downloading?": "هل تريد الإغلاق بعد التنزيل؟",
    "Close without saving?": "هل تريد الإغلاق دون حفظ؟",
    "Make sure the downloaded PDF is available before closing.":
        "تأكد من توفر ملف PDF المنزّل قبل الإغلاق.",
    "The generated PDF has not been saved. You can return to the preview to save or export it.":
        "لم يتم حفظ ملف PDF الذي تم إنشاؤه. يمكنك العودة إلى المعاينة لحفظه أو تصديره.",
    "Return to preview": "العودة إلى المعاينة",
    "Pages": "الصفحات",
    "pages": "صفحات",
    "New page order": "الترتيب الجديد للصفحات",
    "List every page once, for example 3,1,2 or 5-1.":
        "اذكر كل صفحة مرة واحدة، مثل 3,1,2 أو 5-1.",
    "Use all, 1-3,7, or a descending range such as 5-1.":
        "استخدم all أو 1-3,7 أو نطاقًا تنازليًا مثل 5-1.",
    "PDFs are merged in the order below. Choose pages from each source.":
        "سيتم دمج ملفات PDF بالترتيب أدناه. اختر الصفحات من كل ملف مصدر.",
    "Move up": "نقل لأعلى",
    "Move down": "نقل لأسفل",
    "Choose PNG / JPEG": "اختيار PNG / JPEG",
    "Font": "الخط",
    "Choose TTF / OTF": "اختيار TTF / OTF",
    "Opacity": "التعتيم",
    "Bake the new marks into page content":
        "دمج العلامات الجديدة في محتوى الصفحة",
    "Turn off to keep the new marks as editable annotations. Existing annotations and form fields are preserved.":
        "عطّل هذا الخيار للاحتفاظ بالعلامات الجديدة كتعليقات توضيحية قابلة للتحرير. يتم الاحتفاظ بالتعليقات التوضيحية وحقول النماذج الحالية.",
    "Text": "نص",
    "Logo / image": "شعار / صورة",
    "Watermark text": "نص العلامة المائية",
    "Position": "الموضع",
    "Watermarks are placed over page content. Review the generated preview before saving.":
        "توضع العلامات المائية فوق محتوى الصفحة. راجع المعاينة التي تم إنشاؤها قبل الحفظ.",
    "Top left": "أعلى اليسار",
    "Top center": "أعلى الوسط",
    "Top right": "أعلى اليمين",
    "Center left": "وسط اليسار",
    "Center": "الوسط",
    "Center right": "وسط اليمين",
    "Bottom left": "أسفل اليسار",
    "Bottom center": "أسفل الوسط",
    "Bottom right": "أسفل اليمين",
    "Placement is measured from the visible top-left corner of each page, including rotated pages.":
        "يُقاس الموضع من الزاوية العلوية اليسرى المرئية لكل صفحة، بما في ذلك الصفحات المُدوّرة.",
    "Blank keeps aspect ratio": "اتركه فارغًا للحفاظ على نسبة الأبعاد",
    "This PDF has no named AcroForm fields. Open the editor to place text or create form fields.":
        "لا يحتوي ملف PDF هذا على حقول AcroForm مسماة. افتح المحرر لوضع نص أو إنشاء حقول نموذج.",
    "Only changed fields are written. Field names and option values must match the PDF exactly. Password, signature, and read-only fields cannot be batch-filled.":
        "تُكتب الحقول المعدلة فقط. يجب أن تتطابق أسماء الحقول وقيم الخيارات مع ملف PDF تمامًا. لا يمكن تعبئة حقول كلمات المرور والتوقيع والحقول المخصصة للقراءة فقط دفعة واحدة.",
    "Fields": "الحقول",
    "Import JSON": "استيراد JSON",
    "Field name → value": "اسم الحقل → القيمة",
    "Text: string; checkbox: true/false; radio/choice: option value; multiple choice: array of values.":
        "نص: سلسلة نصية؛ مربع اختيار: true/false؛ زر اختيار/قائمة اختيار: قيمة الخيار؛ اختيار متعدد: مصفوفة قيم.",
    "Known field names": "أسماء الحقول المعروفة",
    "OCR data exceeds 16 MiB.": "تتجاوز بيانات OCR حجم 16 MiB.",
    "OCR data must be a JSON array of pages with text spans.":
        "يجب أن تكون بيانات OCR مصفوفة JSON من صفحات تتضمن مقاطع نصية.",
    "Minimum confidence (0–1)": "الحد الأدنى للثقة (0–1)",
    "Import text already recognized by an OCR tool. This action does not recognize images or contact a recognition service.":
        "استورد نصًا سبق أن تعرّفت عليه أداة OCR. لا ينفّذ هذا الإجراء تعرّفًا على الصور ولا يتصل بخدمة تعرّف.",
    "Use one-based page numbers. Each span needs text and bounds [left, bottom, right, top] in PDF points, not image pixels. Confidence is optional and defaults to 1.":
        "استخدم ترقيم الصفحات الذي يبدأ من 1. يحتاج كل مقطع إلى نص وحدود [left, bottom, right, top] بوحدة نقاط PDF، وليس بكسلات الصورة. درجة الثقة اختيارية وقيمتها الافتراضية 1.",
    "Import OCR JSON": "استيراد JSON الخاص بـ OCR",
    "Recognized page spans (JSON)":
        "المقاطع النصية المتعرّف عليها في الصفحات (JSON)",
    "Skip pages that already contain text":
        "تخطي الصفحات التي تحتوي على نص بالفعل",
    "Turning this off appends another text layer and can duplicate existing searchable text.":
        "يؤدي تعطيل هذا الخيار إلى إلحاق طبقة نصية أخرى وقد يكرر النص القابل للبحث الموجود بالفعل.",
    "The added text is invisible. Select or search text in the generated preview to check the result.":
        "النص المضاف غير مرئي. حدد نصًا أو ابحث عنه في المعاينة التي تم إنشاؤها للتحقق من النتيجة.",
    "Search preview text": "البحث في نص المعاينة",
    "Clear search": "مسح البحث",
    "Previous match": "التطابق السابق",
    "Next match": "التطابق التالي",
    "required": "مطلوب",
    "read-only": "للقراءة فقط",
    "password": "كلمة المرور",
    "Rotation": "التدوير",
    "90° clockwise": "90° باتجاه عقارب الساعة",
    "90° counterclockwise": "90° عكس اتجاه عقارب الساعة",
    "At least one page must remain. Deleting pages is a page organization action; it is not secure content removal.":
        "يجب الإبقاء على صفحة واحدة على الأقل. حذف الصفحات إجراء لتنظيم الصفحات؛ ولا يزيل المحتوى بطريقة آمنة.",
    "Allow an unprotected output when required":
        "السماح بإخراج غير محمي عند الحاجة",
    "Page extraction can remove password protection. Merge output follows the first PDF’s encryption. Only continue if that output is appropriate.":
        "قد يؤدي استخراج الصفحات إلى إزالة الحماية بكلمة المرور. يتبع ناتج الدمج تشفير ملف PDF الأول. تابع فقط إذا كان هذا الإخراج مناسبًا.",
    "Review the generated PDF, then save a new copy or export it to your device.":
        "راجع ملف PDF الذي تم إنشاؤه، ثم احفظ نسخة جديدة أو صدّره إلى جهازك.",
    "Review output notes": "مراجعة ملاحظات الإخراج",
    "Output file name": "اسم ملف الإخراج",
    "New copy beside": "نسخة جديدة بجانب",
    "Back to options": "العودة إلى الخيارات",
    "Preview PDF": "معاينة PDF",
    "Download PDF": "تنزيل PDF",
    "Export PDF": "تصدير PDF",
    "Save new copy": "حفظ نسخة جديدة",
    "Reading PDFs…": "جارٍ قراءة ملفات PDF…",
    "Selected PDFs exceed the 256 MiB input limit.":
        "تتجاوز ملفات PDF المحددة حد الإدخال البالغ 256 MiB.",
    "Insert protected pages?": "هل تريد إدراج صفحات محمية؟",
    "The inserted pages will use this document’s protection. This document has no password protection.":
        "ستستخدم الصفحات المدرجة حماية هذا المستند. لا توجد حماية بكلمة مرور لهذا المستند.",
  },
};
