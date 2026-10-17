enum FailureKind {
  validation,
  unauthenticated,
  forbidden,
  conflict,
  notFound,
  unavailable,
  unexpected,
}

class AppFailure implements Exception {
  const AppFailure(this.kind, this.message, {this.code});
  final FailureKind kind;
  final String message;
  final String? code;
  @override
  String toString() => message;
}

void require(bool condition, String message) {
  if (!condition) throw AppFailure(FailureKind.validation, message);
}
