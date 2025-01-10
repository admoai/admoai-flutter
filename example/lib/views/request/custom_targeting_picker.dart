import 'package:flutter/material.dart';
import 'package:admoai/admoai.dart';

class CustomTargetingPicker extends StatefulWidget {
  final Targeting targeting;
  final ValueChanged<Targeting> onChanged;

  const CustomTargetingPicker({
    super.key,
    required this.targeting,
    required this.onChanged,
  });

  @override
  State<CustomTargetingPicker> createState() => _CustomTargetingPickerState();
}

class _CustomTargetingPickerState extends State<CustomTargetingPicker> {
  late List<CustomKeyValue> customs;

  @override
  void initState() {
    super.initState();
    customs = widget.targeting.custom ?? [];
  }

  void updateTargeting() {
    widget.onChanged(Targeting(
      geo: widget.targeting.geo,
      location: widget.targeting.location,
      custom: customs.isEmpty ? null : customs,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Custom Targeting'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                // Info Section
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Add custom key-value pairs for targeting. Note: This demo only supports string values, but the SDK supports boolean and numeric values as well.\n\n'
                      'The key and value must be valid according to the ad server preset settings. For this demo you can use \'category\' as a valid key with possible values like \'sports\', \'news\', \'entertainment\', or \'technology\'.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Custom Targets List
                ...customs.asMap().entries.map((entry) {
                  final index = entry.key;
                  final custom = entry.value;
                  return Dismissible(
                    key: ValueKey(index),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: Theme.of(context).colorScheme.error,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 16),
                      child: const Icon(
                        Icons.delete,
                        color: Colors.white,
                      ),
                    ),
                    onDismissed: (_) {
                      setState(() {
                        customs.removeAt(index);
                        updateTargeting();
                      });
                    },
                    child: CustomTargetRow(
                      keyValue: custom,
                      onUpdate: (newKeyValue) {
                        setState(() {
                          customs[index] = newKeyValue;
                          updateTargeting();
                        });
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
          // Bottom Buttons
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                FilledButton(
                  onPressed: () {
                    setState(() {
                      customs.add(CustomKeyValue(key: '', value: ''));
                      updateTargeting();
                    });
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add),
                      SizedBox(width: 8),
                      Text('Add Custom Target'),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        Theme.of(context).colorScheme.error.withAlpha(25),
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: customs.isEmpty
                      ? null
                      : () {
                          setState(() {
                            customs.clear();
                            updateTargeting();
                          });
                        },
                  child: const Text('Clear All'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CustomTargetRow extends StatefulWidget {
  final CustomKeyValue keyValue;
  final ValueChanged<CustomKeyValue> onUpdate;

  const CustomTargetRow({
    super.key,
    required this.keyValue,
    required this.onUpdate,
  });

  @override
  State<CustomTargetRow> createState() => _CustomTargetRowState();
}

class _CustomTargetRowState extends State<CustomTargetRow> {
  late TextEditingController keyController;
  late TextEditingController valueController;

  @override
  void initState() {
    super.initState();
    keyController = TextEditingController(text: widget.keyValue.key);
    valueController = TextEditingController(text: widget.keyValue.value);
  }

  void updateKeyValue() {
    if (keyController.text.isNotEmpty) {
      widget.onUpdate(CustomKeyValue(
        key: keyController.text,
        value: valueController.text,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: keyController,
                decoration: const InputDecoration(
                  labelText: 'Key',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.none,
                onChanged: (_) => updateKeyValue(),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: valueController,
                decoration: const InputDecoration(
                  labelText: 'Value',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.none,
                onChanged: (_) => updateKeyValue(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    keyController.dispose();
    valueController.dispose();
    super.dispose();
  }
}
