// Entidades puras: sem Flutter, Riverpod, JSON ou SDK de persistência.
enum UserRole { admin, user, tablet, medium, cambono }

enum MediumDegree { medium, dirigente }

enum Ribbon { yellow, green, blue, indigo, purple, colorful, white }

enum ConsultationStatus { waiting, queue, inProgress, completed, cancelled }

class Identity {
  const Identity(this.id, this.email);
  final String id;
  final String? email;
}

class Profile {
  Profile({
    required this.id,
    required this.name,
    required this.role,
    this.email,
    this.mediumId,
    this.photoUrl,
    this.createdAt,
    this.updatedAt,
    List<String> nucleoIds = const [],
  }) : nucleoIds = List.unmodifiable(nucleoIds);
  final String id, name;
  final UserRole role;
  final String? email, mediumId, photoUrl;
  final List<String> nucleoIds;
  final DateTime? createdAt, updatedAt;
}

class Nucleo {
  const Nucleo({
    required this.id,
    required this.name,
    required this.description,
    this.createdAt,
    this.updatedAt,
    this.code,
    this.abbreviation,
    this.active = true,
  });
  final String id, name, description;
  final String? code, abbreviation;
  final bool active;
  final DateTime? createdAt, updatedAt;
}

class Phalanx {
  const Phalanx({
    required this.id,
    required this.name,
    required this.requiredForRegistration,
  });
  final String id, name;
  final bool requiredForRegistration;
}

class Guide {
  const Guide({
    required this.id,
    required this.mediumId,
    required this.name,
    required this.phalanxId,
  });
  final String id, mediumId, name, phalanxId;
}

class GuideDraft {
  const GuideDraft({this.id, required this.name, required this.phalanxId});
  final String? id;
  final String name, phalanxId;
}

class Medium {
  Medium({
    required this.id,
    required this.name,
    required this.degree,
    required this.ribbon,
    required List<String> nucleoIds,
    required List<Guide> guides,
    required this.active,
    this.inactiveReason,
    this.inactivatedAt,
    this.inactivatedBy,
    this.createdAt,
    this.updatedAt,
  }) : nucleoIds = List.unmodifiable(nucleoIds),
       guides = List.unmodifiable(guides);
  final String id, name;
  final MediumDegree degree;
  final Ribbon ribbon;
  final List<String> nucleoIds;
  final List<Guide> guides;
  final bool active;
  final String? inactiveReason;
  final DateTime? inactivatedAt, createdAt, updatedAt;
  final String? inactivatedBy;
}

class MediumDraft {
  MediumDraft({
    this.id,
    required this.name,
    required this.degree,
    required this.ribbon,
    required List<String> nucleoIds,
    required List<GuideDraft> guides,
  }) : nucleoIds = List.unmodifiable(nucleoIds),
       guides = List.unmodifiable(guides);
  final String? id;
  final String name;
  final MediumDegree degree;
  final Ribbon ribbon;
  final List<String> nucleoIds;
  final List<GuideDraft> guides;
}

class WorkSession {
  const WorkSession({
    required this.id,
    required this.nucleoId,
    required this.day,
    required this.phalanxId,
    required this.durationMinutes,
    required this.consultationLimit,
    this.dirigentId,
    this.lockedAt,
  });
  final String id, nucleoId, phalanxId;
  final DateTime day;
  final int durationMinutes, consultationLimit;
  final String? dirigentId;
  final DateTime? lockedAt;
}

class Attendance {
  const Attendance({
    required this.sessionId,
    required this.mediumId,
    required this.present,
  });
  final String sessionId, mediumId;
  final bool present;
}

class Consultation {
  const Consultation({
    required this.id,
    required this.sessionId,
    required this.nucleoId,
    required this.mediumId,
    required this.guideId,
    required this.password,
    required this.consultantName,
    required this.status,
    required this.createdAt,
    required this.durationMinutes,
    required this.isTest,
    required this.isExtra,
    this.startedAt,
    this.endedAt,
    this.rating,
    this.feedback,
    this.overrideReason,
    this.exceededBy = 0,
    this.serviceMinutes,
    this.mediumName,
    this.guideName,
    this.phalanxId,
    this.dirigentId,
    this.dirigentName,
    this.queuePosition,
    this.queuedAt,
    this.updatedAt,
  });
  final String id,
      sessionId,
      nucleoId,
      mediumId,
      guideId,
      password,
      consultantName;
  final ConsultationStatus status;
  final DateTime createdAt;
  final DateTime? startedAt, endedAt;
  final int durationMinutes, exceededBy;
  final int? rating, serviceMinutes;
  final String? feedback, overrideReason;
  final bool isTest, isExtra;
  final String? mediumName, guideName, phalanxId, dirigentId, dirigentName;
  final int? queuePosition;
  final DateTime? queuedAt, updatedAt;
  String get classification => isExtra ? 'extra' : 'normal';
}

class OpenConsultation {
  const OpenConsultation({
    required this.sessionId,
    required this.mediumId,
    required this.guideId,
    required this.password,
    required this.consultantName,
    this.isTest = false,
    this.overrideReason,
  });
  final String sessionId, mediumId, guideId, password, consultantName;
  final bool isTest;
  final String? overrideReason;
}

enum QuickAccessRole { cambono, tablet }

class QuickAccessTarget {
  const QuickAccessTarget({required this.nucleoId, required this.role});
  final String nucleoId;
  final QuickAccessRole role;
}
