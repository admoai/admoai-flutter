# Contributing to AdMoai Flutter SDK

Thank you for considering contributing to the AdMoai Flutter SDK! This document outlines the process and guidelines for contributing.

## 🔀 Development Workflow

1. **Fork the repository** and clone it locally
2. **Create a feature branch** from `main`:
   ```bash
   git checkout -b feat/your-feature-name
   ```
3. **Make your changes** following our coding standards
4. **Test your changes** thoroughly
5. **Commit using Conventional Commits** (see below)
6. **Push to your fork** and create a Pull Request

## 📝 Commit Message Convention

We use [Conventional Commits](https://www.conventionalcommits.org/) for automated changelog generation and semantic versioning.

### Format

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

### Types

- **feat**: A new feature (triggers MINOR version bump)
- **fix**: A bug fix (triggers PATCH version bump)
- **perf**: Performance improvements (triggers PATCH version bump)
- **refactor**: Code changes that neither fix bugs nor add features
- **chore**: Changes to build process, dependencies, or tooling
- **docs**: Documentation only changes
- **style**: Code style changes (formatting, missing semicolons, etc.)
- **test**: Adding or updating tests
- **build**: Changes to build system or dependencies
- **ci**: Changes to CI/CD configuration

### Breaking Changes

To indicate a breaking change (triggers MAJOR version bump):

```
feat!: remove deprecated API methods

BREAKING CHANGE: The old `requestAd()` method has been removed. Use `requestAds()` instead.
```

### Examples

**Good commit messages:**

```bash
feat: add location-based targeting support
fix: resolve UTF-8 encoding issue for special characters
perf: optimize ad request caching mechanism
docs: update README with usage examples
refactor: simplify decision request builder API
test: add unit tests for custom targeting
chore: update dependencies to latest versions
```

**Bad commit messages:**

```bash
Update code                    # Too vague
Fixed bug                      # Missing type and description
FEAT: Add feature             # Type should be lowercase
feat: Added new feature.      # Description should be imperative mood
```

## 🧪 Testing Requirements

Before submitting a PR:

1. **Run all tests:**
   ```bash
   flutter test
   ```

2. **Run the example app:**
   ```bash
   cd example
   flutter run
   ```

3. **Verify code formatting:**
   ```bash
   dart format .
   flutter analyze
   ```

4. **Test on multiple platforms:**
   - iOS (Simulator and device)
   - Android (Emulator and device)

## 📋 Pull Request Guidelines

### PR Title

PR titles must follow Conventional Commits format (enforced by CI):

```
feat: add video ad support
fix: resolve memory leak in ad tracking
docs: update README with installation steps
```

### PR Description

Include:
- **What**: Summary of changes
- **Why**: Motivation and context
- **How**: Technical approach (if non-trivial)
- **Testing**: How you tested the changes
- **Screenshots**: If UI changes (from example app)
- **Breaking Changes**: If applicable

### Checklist

- [ ] Code follows Dart style guidelines
- [ ] Self-reviewed the code
- [ ] Commented complex/non-obvious code
- [ ] Updated documentation (if needed)
- [ ] Added/updated tests
- [ ] All tests pass locally
- [ ] No analyzer warnings or errors
- [ ] PR title follows Conventional Commits

## 🏗️ Code Style

We follow [Effective Dart](https://dart.dev/effective-dart) style guide:

- **Formatting**: Use `dart format` (120 character line length)
- **Analysis**: Pass `flutter analyze` with no issues
- **Naming**:
  - Classes: `PascalCase`
  - Functions/variables: `camelCase`
  - Constants: `lowerCamelCase` (Dart convention)
  - Files: `snake_case.dart`

Run the analyzer before committing:
```bash
dart format .
flutter analyze
```

## 🔐 Security

If you discover a security vulnerability:

1. **DO NOT** open a public issue
2. Email security@admoai.com with details
3. Wait for acknowledgment before disclosing publicly

## 📦 Publishing

Publishing is handled automatically by Release Please when a release PR is merged. Manual publishing requires:

1. Update version in `pubspec.yaml`
2. Update `CHANGELOG.md`
3. Create git tag: `git tag v0.x.x`
4. Push tag: `git push origin v0.x.x`
5. Publish to pub.dev: `flutter pub publish`

(This will be automated via GitHub Actions in the future)

## 📄 License

By contributing, you agree that your contributions will be licensed under the same license as the project.

## 🆘 Need Help?

- **Documentation**: [README.md](README.md)
- **Issues**: [GitHub Issues](https://github.com/admoai/admoai-flutter/issues)
- **Discussions**: [GitHub Discussions](https://github.com/admoai/admoai-flutter/discussions)

---

Thank you for contributing! 🎉

