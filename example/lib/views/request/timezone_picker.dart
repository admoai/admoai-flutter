import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

class TimezonePicker extends StatefulWidget {
  final String? selectedTimezone;
  final ValueChanged<String?> onChanged;

  const TimezonePicker({
    super.key,
    required this.selectedTimezone,
    required this.onChanged,
  });

  @override
  State<TimezonePicker> createState() => _TimezonePickerState();
}

class _TimezonePickerState extends State<TimezonePicker> {
  String searchText = '';
  List<String> timezones = [];

  @override
  void initState() {
    super.initState();
    _loadTimezones();
  }

  Future<void> _loadTimezones() async {
    final zones = await FlutterTimezone.getAvailableTimezones();
    setState(() {
      timezones = zones..sort();
    });
  }

  List<String> get filteredTimezones {
    final filtered = searchText.isEmpty
        ? timezones
        : timezones
            .where((tz) => tz.toLowerCase().contains(searchText.toLowerCase()))
            .toList();
    return searchText.isEmpty ? ['None'] + filtered : filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Timezone'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: SearchBar(
              hintText: 'Search timezones',
              leading: const Icon(Icons.search),
              elevation: const WidgetStatePropertyAll(0),
              backgroundColor: WidgetStatePropertyAll(
                Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withAlpha(30),
              ),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 16),
              ),
              onChanged: (value) => setState(() => searchText = value),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filteredTimezones.length,
              itemBuilder: (context, index) {
                final timezone = filteredTimezones[index];
                final isSelected = widget.selectedTimezone == timezone;
                final isNone = timezone == 'None';

                return Column(
                  children: [
                    ListTile(
                      title: Text(
                        timezone,
                        style: TextStyle(
                          color: isNone
                              ? Theme.of(context).textTheme.bodySmall?.color
                              : null,
                        ),
                      ),
                      trailing: isSelected
                          ? Icon(
                              Icons.check,
                              color: Theme.of(context).colorScheme.primary,
                            )
                          : null,
                      onTap: () {
                        widget.onChanged(isNone ? null : timezone);
                        Navigator.pop(context);
                      },
                    ),
                    const Divider(height: 1),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
