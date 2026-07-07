import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QrCodeWithLogo extends StatelessWidget {
  final String data;
  final double size;
  final double logoSize;
  final int version;

  const QrCodeWithLogo({
    super.key,
    required this.data,
    this.size = 200,
    this.logoSize = 40,
    this.version = QrVersions.auto,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        QrImageView(
          data: data,
          version: version,
          size: size,
          backgroundColor: Colors.white,
          eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
          dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
        ),
        Container(
          width: logoSize + 8,
          height: logoSize + 8,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipOval(
            child: Image.asset(
              'assets/app_logo.png',
              width: logoSize,
              height: logoSize,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Icon(
                Icons.church,
                color: Theme.of(context).primaryColor,
                size: logoSize * 0.6,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
