import 'package:flutter/material.dart';
import 'dart:convert';

class ValidationTabView extends StatelessWidget {
  final String response;

  const ValidationTabView({super.key, required this.response});

  Widget _buildValidationList(List<dynamic> items, bool isError) {
    return Column(
      children: items.asMap().entries.map((entry) {
        final isLast = entry.key == items.length - 1;
        return Column(
          children: [
            ListTile(
              leading: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isError ? Colors.red : Colors.orange,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  entry.value['code'].toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontFamily: 'Courier',
                  ),
                ),
              ),
              title: Text(
                entry.value['message'].toString(),
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
            if (!isLast) const Divider(height: 1),
          ],
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = json.decode(response);
    final errors = data['errors'] as List<dynamic>?;
    final warnings = data['warnings'] as List<dynamic>?;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Errors',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: errors?.isNotEmpty == true
              ? _buildValidationList(errors!, true)
              : ListTile(
                  title: Text(
                    'No errors found',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                  ),
                ),
        ),
        const SizedBox(height: 24),
        Text(
          'Warnings',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: warnings?.isNotEmpty == true
              ? _buildValidationList(warnings!, false)
              : ListTile(
                  title: Text(
                    'No warnings found',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                  ),
                ),
        ),
      ],
    );
  }
}
