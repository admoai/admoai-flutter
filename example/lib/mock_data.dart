import 'package:flutter/material.dart';

class PlacementData {
  final String id;
  final String name;
  final IconData icon;

  const PlacementData({
    required this.id,
    required this.name,
    required this.icon,
  });
}

final placementMockData = [
  const PlacementData(id: "home", name: "Home", icon: Icons.home_outlined),
  const PlacementData(id: "search", name: "Search", icon: Icons.search),
  const PlacementData(id: "menu", name: "Menu", icon: Icons.list),
  const PlacementData(id: "promotions", name: "Promotions", icon: Icons.sell),
  const PlacementData(id: "waiting", name: "Waiting", icon: Icons.schedule),
  const PlacementData(
      id: "vehicleSelection",
      name: "Vehicle Selection",
      icon: Icons.directions_car),
  const PlacementData(
      id: "rideSummary", name: "Ride Summary", icon: Icons.arrow_upward),
  const PlacementData(
    id: "invalidPlacement",
    name: "Invalid Placement",
    icon: Icons.warning,
  ),
];
