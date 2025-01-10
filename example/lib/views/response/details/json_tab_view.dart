import 'package:flutter/material.dart';
import 'dart:convert';

class JSONTabView extends StatelessWidget {
  final String rawResponse;

  const JSONTabView({super.key, required this.rawResponse});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _prettyPrint(rawResponse),
              style: const TextStyle(
                fontFamily: 'Courier',
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _prettyPrint(String rawJson) {
    try {
      final object = json.decode(rawJson);
      return const JsonEncoder.withIndent('  ').convert(object);
    } catch (e) {
      return 'Invalid JSON data';
    }
  }
}
