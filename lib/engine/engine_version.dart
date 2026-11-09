/// Version of the Pazulu Source Engine contract. Extension manifests declare
/// `minimumEngineVersion` and are refused when it is newer than this value.
const String pazuluEngineVersion = '2.0.0';

/// Minimal semantic version (MAJOR.MINOR.PATCH, optional -prerelease ignored
/// for ordering except that a prerelease sorts before its release).
class SemVer implements Comparable<SemVer> {
  const SemVer(this.major, this.minor, this.patch, {this.pre = ''});

  final int major;
  final int minor;
  final int patch;
  final String pre;

  static final RegExp _pattern =
      RegExp(r'^(\d{1,6})\.(\d{1,6})\.(\d{1,6})(?:-([0-9A-Za-z.-]{1,40}))?$');

  static SemVer? tryParse(String? raw) {
    if (raw == null) return null;
    final m = _pattern.firstMatch(raw.trim());
    if (m == null) return null;
    return SemVer(int.parse(m.group(1)!), int.parse(m.group(2)!),
        int.parse(m.group(3)!), pre: m.group(4) ?? '');
  }

  static SemVer parse(String raw) {
    final v = tryParse(raw);
    if (v == null) throw FormatException('Version invalide : $raw');
    return v;
  }

  @override
  int compareTo(SemVer other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    if (pre == other.pre) return 0;
    if (pre.isEmpty) return 1;
    if (other.pre.isEmpty) return -1;
    return pre.compareTo(other.pre);
  }

  bool operator >(SemVer other) => compareTo(other) > 0;
  bool operator <(SemVer other) => compareTo(other) < 0;
  bool operator >=(SemVer other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) => other is SemVer && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, pre);

  @override
  String toString() => pre.isEmpty ? '$major.$minor.$patch' : '$major.$minor.$patch-$pre';
}

bool engineSatisfies(String minimum) {
  final need = SemVer.tryParse(minimum);
  if (need == null) return false;
  return SemVer.parse(pazuluEngineVersion) >= need;
}
