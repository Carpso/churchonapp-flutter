/// Shared PDF text sanitiser.
///
/// The `pdf` package's BUILT-IN fonts (Helvetica) only cover WinAnsi. This repo
/// bundles no .ttf at all and there is no network at PDF-build time on a
/// church laptop, so instead of shipping a font binary we fold every string to
/// what the built-in font can actually draw.
///
/// Without this, any PDF containing a curly quote, an en/em dash, an ellipsis,
/// a bullet or a non-Latin name logs
/// "Could not find a set of Noto fonts to display all missing characters" and
/// renders tofu boxes.
library;

class PdfTextSanitizer {
  const PdfTextSanitizer._();

  static String sanitize(String? input) {
    if (input == null || input.isEmpty) return '';
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      switch (ch) {
        // Typography -> ASCII
        case '‘':
        case '’':
        case '‛':
        case '´':
          buffer.write("'");
        case '“':
        case '”':
        case '‟':
          buffer.write('"');
        case '–': // en dash
        case '—': // em dash
        case '−': // minus
          buffer.write('-');
        case '…': // ellipsis
          buffer.write('...');
        case ' ': // non-breaking space
        case ' ':
        case ' ':
          buffer.write(' ');
        case '•': // bullet
        case '·': // middle dot
        case '●':
          buffer.write('-');
        case '☐':
        case '☑':
        case '☒':
          buffer.write('[ ]');
        case '→':
        case '⇒':
          buffer.write('->');
        case '★':
        case '☆':
          buffer.write('*');
        case '\n':
          buffer.write('\n');
        default:
          if (rune >= 0x20 && rune <= 0x7E) {
            buffer.write(ch);
          } else if (rune >= 0xA0 && rune <= 0xFF) {
            // WinANSI covers all of Latin-1 supplement, so every accented
            // letter (é, ñ, ü …) is already safe.
            buffer.write(ch);
          }
          // Anything else (CJK, emoji, symbols) is dropped rather than drawn
          // as a missing-glyph box.
      }
    }
    return buffer.toString();
  }

  /// ASCII-safe filename for exports.
  static String safeFileName(String? input) => sanitize(input)
      .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')
      .trim()
      .replaceAll(' ', '_')
      .replaceAll(RegExp(r'_+'), '_');
}
