/// Stable 32-bit FNV-1a hash: shuffles and quiz picks come out the same on every run and device.
int fnv32(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}
