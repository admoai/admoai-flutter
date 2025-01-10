import 'package:flutter/material.dart';
import 'package:admoai/admoai.dart';

class City {
  final int id; // Geoname ID
  final String name;
  final String country;

  const City({
    required this.id,
    required this.name,
    required this.country,
  });

  static const List<City> available = [
    City(id: 2643743, name: "London", country: "UK"),
    City(id: 3530597, name: "Miami", country: "US"),
    City(id: 5128581, name: "New York", country: "US"),
    City(id: 2988507, name: "Paris", country: "FR"),
    City(id: 3169070, name: "Rome", country: "IT"),
    City(id: 3871336, name: "Santiago", country: "CL"),
  ];
}

class GeoTargetingPicker extends StatefulWidget {
  final Targeting targeting;
  final ValueChanged<Targeting> onChanged;

  const GeoTargetingPicker({
    super.key,
    required this.targeting,
    required this.onChanged,
  });

  @override
  State<GeoTargetingPicker> createState() => _GeoTargetingPickerState();
}

class _GeoTargetingPickerState extends State<GeoTargetingPicker> {
  late Set<int> selectedIds;
  String searchText = '';

  @override
  void initState() {
    super.initState();
    selectedIds = Set.from(widget.targeting.geo ?? []);
  }

  List<City> get filteredCities {
    return searchText.isEmpty
        ? City.available
        : City.available
            .where((city) =>
                city.name.toLowerCase().contains(searchText.toLowerCase()))
            .toList();
  }

  void updateTargeting() {
    widget.onChanged(Targeting(
      geo: selectedIds.isEmpty ? null : selectedIds.toList(),
      location: widget.targeting.location,
      custom: widget.targeting.custom,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Geo Targeting'),
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
                      'Add city IDs to target specific geographic areas. You can add multiple cities to target different regions.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Cities List
                Card(
                  child: Column(
                    children: [
                      ...filteredCities.map((city) {
                        final isSelected = selectedIds.contains(city.id);
                        return Column(
                          children: [
                            ListTile(
                              title: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    city.name,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest
                                          .withAlpha(178),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      city.id.toString(),
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 13,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              trailing: isSelected
                                  ? Icon(
                                      Icons.check,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    )
                                  : null,
                              onTap: () {
                                setState(() {
                                  if (isSelected) {
                                    selectedIds.remove(city.id);
                                  } else {
                                    selectedIds.add(city.id);
                                  }
                                  updateTargeting();
                                });
                              },
                            ),
                            if (city != filteredCities.last)
                              const Divider(height: 1),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (selectedIds.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  backgroundColor:
                      Theme.of(context).colorScheme.error.withAlpha(25),
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () {
                  setState(() {
                    selectedIds.clear();
                    updateTargeting();
                  });
                },
                child: const Text('Clear Selection'),
              ),
            ),
        ],
      ),
    );
  }
}
