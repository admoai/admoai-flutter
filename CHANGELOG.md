# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] - 2024-11-26

### Fixed
- Special characters like £ now display correctly in ad content by properly implementing UTF-8 encoding for API responses

## [0.1.0] - 2024-11-01

### Added
- Initial release of AdMoai Flutter SDK
- Ad request and decision API with `DecisionRequestBuilder`
- Support for targeting (location, demographics, interests, custom attributes)
- Real-time ad tracking (impressions, clicks, custom events)
- Cross-platform support (iOS and Android)
- Configuration management (user, app, and SDK configs)
- Error handling with structured exception types
- Example application demonstrating SDK integration

[0.1.1]: https://github.com/admoai/admoai-flutter/releases/tag/v0.1.1
[0.1.0]: https://github.com/admoai/admoai-flutter/releases/tag/v0.1.0
