import 'dart:core';

String normalizePath(String path) {
  return path.split('/').map(normalizeSegment).join('/');
}

final RegExp segmentReservedChars = RegExp(r'%|/');

String normalizeSegment(String segment) {
  if (segment.length < 3 || !segment.contains('%')) return segment;
  return Uri.decodeComponent(segment).replaceAllMapped(
    segmentReservedChars,
    (match) => Uri.encodeComponent(match.group(0)!),
  );
}

final RegExp pathSegmentEncodings = RegExp(r'%(?:2(?:4|6|B|C)|3(?:B|D|A)|40)');

String encodePathSegment(String str) {
  return Uri.encodeComponent(str).replaceAllMapped(
    pathSegmentEncodings,
    (match) => Uri.decodeComponent(match.group(0)!),
  );
}
