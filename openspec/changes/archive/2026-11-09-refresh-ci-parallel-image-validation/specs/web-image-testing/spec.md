## REMOVED Requirements

### Requirement: Web image consumer jobs do not rebuild the image

**Reason**: Duplicates rules that now cover every image, `flutter-web` included.
**Migration**: `ci-image-handoff` — "Consumer jobs never rebuild the image" and "Fork PRs use an artifact handoff"; `ci-image-vulnerability-scan` — "Scan is skipped for fork PRs at the job level".
