// SPDX-License-Identifier: MPL-2.0
// Independent read-only text/structure observations from Apache POI.
// Invoke in a separate JVM with a timeout and bounded heap for each document.
import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.apache.poi.hwpf.HWPFDocument;
import org.apache.poi.hwpf.HWPFOldDocument;
import org.apache.poi.hwpf.OldWordFileFormatException;
import org.apache.poi.hwpf.extractor.Word6Extractor;
import org.apache.poi.hwpf.extractor.WordExtractor;
import org.apache.poi.poifs.filesystem.POIFSFileSystem;
import org.apache.poi.xwpf.extractor.XWPFWordExtractor;
import org.apache.poi.xwpf.usermodel.IBodyElement;
import org.apache.poi.xwpf.usermodel.XWPFDocument;
import org.apache.poi.xwpf.usermodel.XWPFParagraph;
import org.apache.poi.xwpf.usermodel.XWPFTable;

public final class ExternalWordOracle {
    private static String json(Object value) {
        if (value == null) return "null";
        if (value instanceof Number || value instanceof Boolean) return value.toString();
        if (value instanceof Map<?, ?> map) {
            var values = new ArrayList<String>();
            for (var entry : map.entrySet()) values.add(json(entry.getKey().toString()) + ":" + json(entry.getValue()));
            return "{" + String.join(",", values) + "}";
        }
        if (value instanceof Iterable<?> iterable) {
            var values = new ArrayList<String>();
            for (var item : iterable) values.add(json(item));
            return "[" + String.join(",", values) + "]";
        }
        if (value instanceof String[] strings) return json(List.of(strings));
        String text = value.toString();
        var encoded = new StringBuilder("\"");
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            if (c == '"' || c == '\\') encoded.append('\\').append(c);
            else if (c < 0x20 || Character.isSurrogate(c)) encoded.append(String.format("\\u%04x", (int)c));
            else encoded.append(c);
        }
        return encoded.append('"').toString();
    }

    private static void body(List<IBodyElement> elements, List<String> paragraphs) {
        for (IBodyElement element : elements) {
            if (element instanceof XWPFParagraph p) paragraphs.add(p.getText());
            else if (element instanceof XWPFTable table) {
                for (var row : table.getRows()) for (var cell : row.getTableCells()) body(cell.getBodyElements(), paragraphs);
            }
        }
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 2) throw new IllegalArgumentException("INPUT.doc[x] NEW_OUTPUT.json required");
        Path source = Path.of(args[0]), target = Path.of(args[1]);
        if (Files.exists(target)) throw new IllegalArgumentException("Output must be new");
        if (Files.size(source) > 16 * 1024 * 1024) throw new IllegalArgumentException("Input exceeds 16 MiB");
        byte[] bytes = Files.readAllBytes(source);
        var report = new LinkedHashMap<String, Object>();
        report.put("oracle", "Apache POI 6.0.0");
        report.put("source", source.toAbsolutePath().toString());
        report.put("sourceSha256", HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes)));
        int result = 0;
        try {
            if (source.getFileName().toString().toLowerCase().endsWith(".docx")) {
                try (var document = new XWPFDocument(new ByteArrayInputStream(bytes));
                     var extractor = new XWPFWordExtractor(document)) {
                    report.put("format", "docx");
                    report.put("text", extractor.getText());
                    var paragraphs = new ArrayList<String>();
                    body(document.getBodyElements(), paragraphs);
                    report.put("mainParagraphsIncludingTableCells", paragraphs);
                    report.put("mainDirectTables", document.getTables().size());
                    report.put("footnotes", document.getFootnotes().size());
                    report.put("endnotes", document.getEndnotes().size());
                    var comments = document.getComments();
                    report.put("comments", comments == null ? 0 : comments.length);
                }
            } else {
                try (var document = new HWPFDocument(new ByteArrayInputStream(bytes));
                     var extractor = new WordExtractor(document)) {
                    report.put("format", "doc97");
                    report.put("mainRaw", document.getRange().text());
                    report.put("mainParagraphs", extractor.getParagraphText());
                    var displayParagraphs = new ArrayList<String>();
                    for (String paragraph : extractor.getParagraphText()) {
                        displayParagraphs.add(WordExtractor.stripFields(paragraph));
                    }
                    report.put("mainDisplayParagraphs", displayParagraphs);
                    report.put("footnotes", extractor.getFootnoteText());
                    report.put("endnotes", extractor.getEndnoteText());
                    report.put("comments", extractor.getCommentsText());
                    report.put("mainTextboxes", extractor.getMainTextboxText());
                    report.put("text", extractor.getText());
                } catch (OldWordFileFormatException old) {
                    try (var filesystem = new POIFSFileSystem(new ByteArrayInputStream(bytes));
                         var document = new HWPFOldDocument(filesystem);
                         var extractor = new Word6Extractor(document)) {
                        report.put("format", "word6-or-95");
                        report.put("text", extractor.getText());
                        report.put("mainParagraphs", extractor.getParagraphText());
                    }
                }
            }
            report.put("status", "ok");
        } catch (Exception | LinkageError error) {
            report.put("status", "error");
            report.put("errorType", error.getClass().getName());
            report.put("error", error.toString());
            result = 2;
        }
        Files.createDirectories(target.toAbsolutePath().getParent());
        Files.writeString(target, json(report) + "\n", StandardCharsets.UTF_8);
        System.exit(result);
    }
}
