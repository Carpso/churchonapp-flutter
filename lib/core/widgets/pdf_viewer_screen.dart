import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:universal_io/io.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class PDFViewerScreen extends StatefulWidget {
  final String url;
  final String title;

  const PDFViewerScreen({super.key, required this.url, required this.title});

  @override
  State<PDFViewerScreen> createState() => _PDFViewerScreenState();
}

class _PDFViewerScreenState extends State<PDFViewerScreen> {
  String? localPath;
  bool isLoading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _downloadFile();
  }

  Future<void> _downloadFile() async {
    try {
      final response = await http.get(Uri.parse(widget.url));
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/temp.pdf');
      await file.writeAsBytes(response.bodyBytes);
      if (mounted) {
        setState(() {
          localPath = file.path;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(LucideIcons.share2), onPressed: () {
            if (localPath != null) {
              SharePlus.instance.share(ShareParams(files: [XFile(localPath!)], text: widget.title));
            }
          }),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text("Error loading PDF: $error"))
              : localPath != null
                  ? PDFView(
                      filePath: localPath,
                      enableSwipe: true,
                      swipeHorizontal: true,
                      autoSpacing: false,
                      pageFling: false,
                      onRender: (pages) {
                        setState(() {
                          // pages = _pages;
                        });
                      },
                      onError: (error) {
                        debugPrint(error.toString());
                      },
                      onPageError: (page, error) {
                        debugPrint('$page: ${error.toString()}');
                      },
                    )
                  : const Center(child: Text("Could not load PDF")),
    );
  }
}

