import 'native_contract.dart';

class DesktopScreenCapturePlatformException implements Exception {
  final String status;
  final String message;
  final String recoverySuggestion;
  final String nativeCode;
  final NativeFailureEnvelope? failure;
  final bool requiresRestart;
  final Object? cause;
  final StackTrace? stackTrace;

  const DesktopScreenCapturePlatformException({
    required this.status,
    required this.message,
    this.recoverySuggestion = '',
    this.nativeCode = '',
    this.failure,
    this.requiresRestart = false,
    this.cause,
    this.stackTrace,
  });

  factory DesktopScreenCapturePlatformException.fromFailure({
    required NativeFailureEnvelope failure,
    required String message,
    String recoverySuggestion = '',
    Object? cause,
  }) {
    return DesktopScreenCapturePlatformException(
      status: failure.status,
      message: message,
      recoverySuggestion: recoverySuggestion,
      nativeCode: failure.nativeCode,
      failure: failure,
      requiresRestart: failure.requiresRestart,
      cause: cause,
    );
  }

  @override
  String toString() {
    return recoverySuggestion.isEmpty
        ? message
        : '$message $recoverySuggestion';
  }
}
