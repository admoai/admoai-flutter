import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'models/decision_request.dart';
import 'models/decision_response.dart';

class AdMoaiClient {
  final String baseUrl;
  final Logger logger;
  final http.Client _client;

  AdMoaiClient({
    required this.baseUrl,
    required this.logger,
  }) : _client = http.Client();

  Future<APIResponse<T>> send<T>(HTTPRequest request) async {
    final uri = Uri.parse('$baseUrl${request.path}');

    try {
      final response = await _client.post(
        uri,
        headers: request.headers,
        body: request.body,
      );

      final rawBody = utf8.decode(response.bodyBytes);
      final jsonBody = jsonDecode(rawBody) as Map<String, dynamic>;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (T == List<Decision>) {
          final List<dynamic> dataList = jsonBody['data'];
          final decisions = dataList
              .map((item) => Decision.fromJson(item as Map<String, dynamic>))
              .toList();

          final responseBody = APIResponseBody<T>(
            success: jsonBody['success'] as bool,
            data: decisions as T,
            errors: [],
            warnings: [],
          );

          return APIResponse<T>(
            response: response,
            body: responseBody,
            rawBody: rawBody,
          );
        }

        throw UnimplementedError('Unsupported type: $T');
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
          final errors = (jsonBody['errors'] as List?)
                  ?.map((e) => AdMoaiError.fromJson(e as Map<String, dynamic>))
                  .toList() ??
              [];
          if (errors.isNotEmpty) {
            throw ValidationError(errors);
          }
          throw ClientError(HTTPStatus.unprocessableEntity);
        case 429:
          throw ClientError(HTTPStatus.tooManyRequests);
        case 500:
          throw ServerError(response.statusCode);
        default:
          throw NetworkError('Unexpected status code: ${response.statusCode}');
      }
    } catch (e) {
      throw NetworkError(e.toString());
    }
  }

  HTTPRequest getDecisionRequest(DecisionRequest request) {
    return HTTPRequest(
      path: '/v1/decision',
      method: HTTPMethod.post,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
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
