import 'package:flutter/material.dart';
import 'package:admoai/admoai.dart';
import 'details/contents_tab_view.dart';
import 'details/info_tab_view.dart';
import 'details/tracking_tab_view.dart';
import 'details/validation_tab_view.dart';
import 'details/json_tab_view.dart';

enum DataTab {
  contents,
  info,
  tracking,
  validation,
  json,
}

class ResponseDetailsView extends StatefulWidget {
  final Creative creative;
  final String rawResponse;
  final DataTab selectedTab;
  final AdMoai sdk;

  const ResponseDetailsView({
    super.key,
    required this.creative,
    required this.rawResponse,
    required this.sdk,
    this.selectedTab = DataTab.contents,
  });

  @override
  State<ResponseDetailsView> createState() => _ResponseDetailsViewState();
}

class _ResponseDetailsViewState extends State<ResponseDetailsView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: DataTab.values.length,
      vsync: this,
      initialIndex: widget.selectedTab.index,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Response'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Contents'),
            Tab(text: 'Info'),
            Tab(text: 'Tracking'),
            Tab(text: 'Validation'),
            Tab(text: 'JSON'),
          ],
          isScrollable: true,
          dividerColor: Colors.transparent,
          padding: EdgeInsets.zero,
          tabAlignment: TabAlignment.start,
          indicatorSize: TabBarIndicatorSize.tab,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          ContentsTabView(creative: widget.creative),
          InfoTabView(creative: widget.creative),
          TrackingTabView(
            creative: widget.creative,
            sdk: widget.sdk,
          ),
          ValidationTabView(response: widget.rawResponse),
          JSONTabView(rawResponse: widget.rawResponse),
        ],
      ),
    );
  }
}
