import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'models/decision_request.dart';
import 'models/decision_response.dart';
import 'version.dart';

class AdMoaiClient {
  final String baseUrl;
  final String? apiVersion;
  final String? defaultLanguage;
  final Duration requestTimeout;
  final Logger logger;
  final http.Client _client;

  AdMoaiClient({
    required this.baseUrl,
    this.apiVersion,
    this.defaultLanguage,
    this.requestTimeout = const Duration(seconds: 10),
    required this.logger,
    http.Client? httpClient,
  }) : _client = httpClient ?? http.Client();

  Future<APIResponse<T>> send<T>(HTTPRequest request) async {
    final uri = Uri.parse('$baseUrl${request.path}');

    try {
      final response = await _client
          .post(
            uri,
            headers: request.headers,
            body: request.body,
          )
          .timeout(requestTimeout);

      _warnIfDeprecated(response);

      final rawBody = utf8.decode(response.bodyBytes);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final jsonBody = jsonDecode(rawBody) as Map<String, dynamic>;
        if (T == List<Decision>) {
          // Tolerant Reader envelope parse: `data` may be absent/non-list, and
          // individual entries may not be objects — never throw, just skip.
          final rawData = jsonBody['data'];
          final decisions = rawData is List
              ? rawData
                  .whereType<Map<String, dynamic>>()
                  .map(Decision.fromJson)
                  .toList()
              : <Decision>[];

          // Parse errors/warnings rather than hardcoding them empty. The engine returns
          // `warnings` on a 200 in staging — that is where a publisher is meant to discover a
          // misconfiguration before it reaches production — and they were discarded here, so
          // Flutter integrators saw none of them while iOS and Android surfaced them. Entries are
          // dropped individually if malformed, consistent with the Tolerant Reader posture used
          // everywhere else in this file.
          final responseBody = APIResponseBody<T>(
            success: jsonBody['success'] == true,
            data: decisions as T,
            errors: _messageList(jsonBody['errors'], AdMoaiError.tryFromJson),
            warnings: _messageList(jsonBody['warnings'], AdMoaiWarning.tryFromJson),
          );

          return APIResponse<T>(
            response: response,
            body: responseBody,
            rawBody: rawBody,
          );
        }

        throw UnimplementedError('Unsupported type: $T');
      }

      if (response.statusCode >= 500 && response.statusCode <= 599) {
        throw ServerError(response.statusCode);
      }

      switch (response.statusCode) {
        case 400:
          throw ClientError(HTTPStatus.badRequest);
        case 404:
          throw ClientError(HTTPStatus.notFound);
        case 405:
          throw ClientError(HTTPStatus.methodNotAllowed);
        case 410:
          throw ClientError(HTTPStatus.gone);
        case 422:
          Map<String, dynamic>? jsonBody;
          try {
            jsonBody = jsonDecode(rawBody) as Map<String, dynamic>;
          } catch (_) {
            jsonBody = null;
          }
          final errors = (jsonBody?['errors'] as List?)
                  ?.map((e) => AdMoaiError.fromJson(e as Map<String, dynamic>))
                  .toList() ??
              [];
          if (errors.isNotEmpty) {
            throw ValidationError(errors);
          }
          throw ClientError(HTTPStatus.unprocessableEntity);
        case 429:
          throw ClientError(HTTPStatus.tooManyRequests);
        default:
          throw UnexpectedStatusError(response.statusCode);
      }
    } on APIError {
      rethrow;
    } catch (e) {
      throw NetworkError(e);
    }
  }

  /// Surfaces API-version deprecation to the developer per the Admoai
  /// versioning lifecycle (docs.admoai.com). Deprecated responses carry
  /// `X-API-Deprecated: true` (and may include a sunset date); we log a single
  /// warning and otherwise process the response normally. Header lookup is
  /// case-insensitive (the http package lowercases response header keys).
  void _warnIfDeprecated(http.Response response) {
    final deprecated = response.headers['x-api-deprecated'];
    if (deprecated?.toLowerCase() == 'true') {
      final sunset =
          response.headers['sunset'] ?? response.headers['x-api-sunset'];
      logger.warning(
        'AdMoai API version is deprecated'
        '${sunset != null ? ' (sunset: $sunset)' : ''}. '
        'Upgrade the SDK or apiVersion before sunset.',
      );
    }
  }

  HTTPRequest getDecisionRequest(DecisionRequest request) {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': 'AdMoaiSDK/$sdkVersion',
    };

    if (apiVersion != null) {
      headers['X-Decision-Version'] = apiVersion!;
    }

    if (defaultLanguage != null) {
      headers['Accept-Language'] = defaultLanguage!;
    }

    return HTTPRequest(
      path: '/v1/decision',
      method: HTTPMethod.post,
      headers: headers,
      body: jsonEncode(request.toJson()),
    );
  }

  Future<APIResponse<DecisionResponse>> requestDecision(
      DecisionRequest request) async {
    final httpRequest = getDecisionRequest(request);
    return send(httpRequest);
  }

  void dispose() {
    _client.close();
  }
}

class APIResponse<T> {
  final http.Response response;
  final APIResponseBody<T> body;
  final String? rawBody;

  APIResponse({
    required this.response,
    required this.body,
    this.rawBody,
  });
}

class APIResponseBody<T> {
  final bool success;
  final T? data;
  final List<AdMoaiError> errors;
  final List<AdMoaiWarning> warnings;

  APIResponseBody({
    required this.success,
    this.data,
    this.errors = const [],
    this.warnings = const [],
  });
}

/// Tolerant Reader list parse for the envelope's `errors` / `warnings`: a non-list yields an
/// empty list, and an entry missing or retyping `code`/`message` is dropped rather than throwing.
List<T> _messageList<T>(dynamic raw, T? Function(dynamic) tryParse) {
  if (raw is! List) return const [];
  return raw.map(tryParse).whereType<T>().toList();
}

class AdMoaiError {
  final int code;
  final String message;

  AdMoaiError({required this.code, required this.message});

  factory AdMoaiError.fromJson(Map<String, dynamic> json) {
    return AdMoaiError(
      code: json['code'] as int,
      message: json['message'] as String,
    );
  }

  /// Tolerant variant: returns `null` instead of throwing on a malformed entry.
  static AdMoaiError? tryFromJson(dynamic json) {
    if (json is! Map) return null;
    final code = json['code'];
    final message = json['message'];
    if (code is! int || message is! String) return null;
    return AdMoaiError(code: code, message: message);
  }
}

class AdMoaiWarning {
  final int code;
  final String message;

  AdMoaiWarning({required this.code, required this.message});

  factory AdMoaiWarning.fromJson(Map<String, dynamic> json) {
    return AdMoaiWarning(
      code: json['code'] as int,
      message: json['message'] as String,
    );
  }

  /// Tolerant variant: returns `null` instead of throwing on a malformed entry.
  static AdMoaiWarning? tryFromJson(dynamic json) {
    if (json is! Map) return null;
    final code = json['code'];
    final message = json['message'];
    if (code is! int || message is! String) return null;
    return AdMoaiWarning(code: code, message: message);
  }
}

sealed class APIError implements Exception {
  final String message;
  APIError(this.message);
}

class InvalidURLError extends APIError {
  InvalidURLError() : super('Invalid URL');
}

class NetworkError extends APIError {
  final Object error;
  NetworkError(this.error) : super('Network error: ${error.toString()}');
}

class DecodingError extends APIError {
  final Object error;
  DecodingError(this.error) : super('Decoding error: ${error.toString()}');
}

class ServerError extends APIError {
  final int code;
  ServerError(this.code) : super('Server error with status code: $code');
}

class ValidationError extends APIError {
  final List<AdMoaiError> errors;
  ValidationError(this.errors) : super(_formatErrors(errors));

  static String _formatErrors(List<AdMoaiError> errors) {
    if (errors.isEmpty) return 'Validation error: Unknown';
    final messages = errors.map((e) => '[${e.code}] ${e.message}');
    return 'Validation errors:\n${messages.join('\n')}';
  }
}

class ClientError extends APIError {
  final HTTPStatus status;
  ClientError(this.status)
      : super('Client error: ${status.code} - ${status.description}');
}

class UnexpectedStatusError extends APIError {
  final int statusCode;
  UnexpectedStatusError(this.statusCode)
      : super('Unexpected HTTP status code: $statusCode');
}

class HTTPRequest {
  final String path;
  final HTTPMethod method;
  final Map<String, String>? headers;
  final String? body;

  HTTPRequest({
    required this.path,
    required this.method,
    this.headers,
    this.body,
  });
}

enum HTTPMethod {
  get('GET'),
  post('POST'),
  put('PUT'),
  patch('PATCH'),
  delete('DELETE');

  final String value;
  const HTTPMethod(this.value);
}

enum HTTPStatus {
  ok(200),
  badRequest(400),
  notFound(404),
  methodNotAllowed(405),
  gone(410),
  unprocessableEntity(422),
  tooManyRequests(429),
  internalServerError(500);

  final int code;
  const HTTPStatus(this.code);

  String get description {
    switch (this) {
      case HTTPStatus.ok:
        return 'OK';
      case HTTPStatus.badRequest:
        return 'Bad Request';
      case HTTPStatus.notFound:
        return 'Not Found';
      case HTTPStatus.methodNotAllowed:
        return 'Method Not Allowed';
      case HTTPStatus.gone:
        return 'Gone';
      case HTTPStatus.unprocessableEntity:
        return 'Unprocessable Entity';
      case HTTPStatus.tooManyRequests:
        return 'Too Many Requests';
      case HTTPStatus.internalServerError:
        return 'Internal Server Error';
    }
  }
}
