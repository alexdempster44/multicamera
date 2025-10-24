extension StringList on List<Object?> {
  List<String> toStrings() => map((e) => e.toString()).toList();
}
