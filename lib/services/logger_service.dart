import 'package:logger/logger.dart';

class LoggerService {
  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 2,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
  );

  static Logger get logger => _logger;

  // Helper methods for common log levels
  static void debug(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    if (error != null) {
      _logger.d(message, error: error, stackTrace: stackTrace);
    } else {
      _logger.d(message);
    }
  }

  static void info(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    if (error != null) {
      _logger.i(message, error: error, stackTrace: stackTrace);
    } else {
      _logger.i(message);
    }
  }

  static void warning(dynamic message,
      [dynamic error, StackTrace? stackTrace]) {
    if (error != null) {
      _logger.w(message, error: error, stackTrace: stackTrace);
    } else {
      _logger.w(message);
    }
  }

  static void error(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    if (error != null) {
      _logger.e(message, error: error, stackTrace: stackTrace);
    } else {
      _logger.e(message);
    }
  }

  static void verbose(dynamic message,
      [dynamic error, StackTrace? stackTrace]) {
    if (error != null) {
      _logger.t(message, error: error, stackTrace: stackTrace);
    } else {
      _logger.t(message);
    }
  }
}
