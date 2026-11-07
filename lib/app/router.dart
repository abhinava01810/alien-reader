import 'package:flutter/material.dart';

import '../features/device/data/models/device_qr_payload.dart';
import '../features/device/presentation/device_identified_screen.dart';
import '../features/device/presentation/device_qr_scanner_screen.dart';
import '../features/device/presentation/pairing/device_pairing_screen.dart';
import '../features/device/presentation/wifi_onboarding_screen.dart';
import '../features/document/data/models/saved_document.dart';
import '../features/document/presentation/document_results_screen.dart';
import '../features/document/presentation/saved_document_detail_screen.dart';
import '../features/processing/presentation/processing_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../shared/models/document_output.dart';

abstract final class AppRoutes {
  static const settings = '/settings';
  static const processing = '/processing';
  static const documentResults = '/document-results';
  static const savedDocumentDetail = '/saved-document-detail';
  static const deviceQrScanner = '/device-qr-scanner';
  static const deviceIdentified = '/device-identified';
  static const wifiOnboarding = '/wifi-onboarding';
  static const devicePairing = '/device-pairing';
}

class DocumentResultsArgs {
  final DocumentOutput output;
  final SavedDocument? savedDocument;

  const DocumentResultsArgs({required this.output, this.savedDocument});
}

class ProcessingArgs {
  final Future<void> Function() onProcess;
  final int pageNumber;
  final String? imageUrl;
  final Stream<String>? statusStream;
  final bool onPhone;

  const ProcessingArgs({
    required this.onProcess,
    this.pageNumber = 1,
    this.imageUrl,
    this.statusStream,
    this.onPhone = false,
  });
}

abstract final class AppRouter {
  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.settings:
        return MaterialPageRoute<void>(
          builder: (_) => const SettingsScreen(),
          settings: settings,
        );

      case AppRoutes.processing:
        if (settings.arguments is ProcessingArgs) {
          final args = settings.arguments as ProcessingArgs;
          return MaterialPageRoute<void>(
            builder: (_) => ProcessingScreen(
              onProcess: args.onProcess,
              pageNumber: args.pageNumber,
              imageUrl: args.imageUrl,
              statusStream: args.statusStream,
              onPhone: args.onPhone,
            ),
            settings: settings,
          );
        }
        if (settings.arguments is Future<void> Function()) {
          final onProcess = settings.arguments as Future<void> Function();
          return MaterialPageRoute<void>(
            builder: (_) => ProcessingScreen(onProcess: onProcess),
            settings: settings,
          );
        }
        final callback = settings.arguments as VoidCallback;
        return MaterialPageRoute<void>(
          builder: (_) => ProcessingScreen(onCompleted: callback),
          settings: settings,
        );

      case AppRoutes.documentResults:
        if (settings.arguments is DocumentResultsArgs) {
          final args = settings.arguments as DocumentResultsArgs;
          return MaterialPageRoute<void>(
            builder: (_) => DocumentResultsScreen(
              output: args.output,
              savedDocument: args.savedDocument,
            ),
            settings: settings,
          );
        }
        final output = settings.arguments as DocumentOutput;
        return MaterialPageRoute<void>(
          builder: (_) => DocumentResultsScreen(output: output),
          settings: settings,
        );

      case AppRoutes.savedDocumentDetail:
        final doc = settings.arguments as SavedDocument;
        return MaterialPageRoute<bool>(
          builder: (_) => SavedDocumentDetailScreen(document: doc),
          settings: settings,
        );

      case AppRoutes.deviceQrScanner:
        return MaterialPageRoute<void>(
          builder: (_) => const DeviceQrScannerScreen(),
          settings: settings,
        );

      case AppRoutes.deviceIdentified:
        final payload = settings.arguments as DeviceQrPayload;
        return MaterialPageRoute<void>(
          builder: (_) => DeviceIdentifiedScreen(payload: payload),
          settings: settings,
        );

      case AppRoutes.devicePairing:
        final deviceId = (settings.arguments is String)
            ? settings.arguments as String
            : (settings.arguments is DeviceQrPayload
                  ? (settings.arguments as DeviceQrPayload).deviceId
                  : 'NAADH-UNKNOWN');
        return MaterialPageRoute<void>(
          builder: (_) => DevicePairingScreen(deviceId: deviceId),
          settings: settings,
        );

      case AppRoutes.wifiOnboarding:
        final deviceId = (settings.arguments is String)
            ? settings.arguments as String
            : (settings.arguments is DeviceQrPayload
                  ? (settings.arguments as DeviceQrPayload).deviceId
                  : 'NAADH-UNKNOWN');
        return MaterialPageRoute<void>(
          builder: (_) => WifiOnboardingScreen(deviceId: deviceId),
          settings: settings,
        );

      default:
        return null;
    }
  }
}
