import '../../domain/entities.dart';
import 'data_sources.dart';

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.parse(value as String);
Identity identityFromJson(Json j) =>
    Identity(j['id'] as String, j['email'] as String?);
Profile profileFromJson(Json j) => Profile(
  id: j['id'] as String,
  name: j['name'] as String,
  role: UserRole.values.byName(j['role'] as String),
  email: j['email'] as String?,
  mediumId: j['medium_id'] as String?,
  photoUrl: j['photo_url'] as String?,
  createdAt: _date(j['created_at']),
  updatedAt: _date(j['updated_at']),
  nucleoIds: (j['user_nucleos'] as List? ?? const [])
      .map((r) => (r as Map)['nucleo_id'] as String)
      .toList(),
);
Nucleo nucleoFromJson(Json j) => Nucleo(
  id: j['id'] as String,
  name: j['name'] as String,
  description: j['description'] as String,
  code: j['code'] as String?,
  abbreviation: j['abbreviation'] as String?,
  active: j['active'] as bool? ?? true,
  createdAt: _date(j['created_at']),
  updatedAt: _date(j['updated_at']),
);
Phalanx phalanxFromJson(Json j) => Phalanx(
  id: j['id'] as String,
  name: j['name'] as String,
  requiredForRegistration: j['required_for_registration'] as bool,
);
Guide guideFromJson(Json j) => Guide(
  id: j['id'] as String,
  mediumId: j['medium_id'] as String,
  name: j['name'] as String,
  phalanxId: j['phalanx_id'] as String,
);
Medium mediumFromJson(Json j) => Medium(
  id: j['id'] as String,
  name: j['name'] as String,
  degree: MediumDegree.values.byName(j['degree'] as String),
  ribbon: Ribbon.values.byName(j['ribbon'] as String),
  nucleoIds: (j['medium_nucleos'] as List)
      .map((r) => (r as Map)['nucleo_id'] as String)
      .toList(),
  guides: (j['guides'] as List)
      .map((r) => guideFromJson(Json.from(r as Map)))
      .toList(),
  active: j['active'] as bool,
  inactiveReason: j['inactive_reason'] as String?,
  inactivatedAt: _date(j['inactivated_at']),
  inactivatedBy: j['inactivated_by'] as String?,
  createdAt: _date(j['created_at']),
  updatedAt: _date(j['updated_at']),
);
WorkSession sessionFromJson(Json j) => WorkSession(
  id: j['id'] as String,
  nucleoId: j['nucleo_id'] as String,
  day: DateTime.parse(j['work_day'] as String),
  phalanxId: j['phalanx_id'] as String,
  durationMinutes: j['duration_minutes'] as int,
  consultationLimit: j['consultation_limit'] as int,
  dirigentId: j['dirigent_id'] as String?,
  lockedAt: _date(j['locked_at']),
);
Attendance attendanceFromJson(Json j) => Attendance(
  sessionId: j['session_id'] as String,
  mediumId: j['medium_id'] as String,
  present: j['present'] as bool,
);
Consultation consultationFromJson(Json j) => Consultation(
  id: j['id'] as String,
  sessionId: j['session_id'] as String,
  nucleoId: j['nucleo_id'] as String,
  mediumId: j['medium_id'] as String,
  guideId: j['guide_id'] as String,
  password: j['password'] as String,
  consultantName: j['consultant_name'] as String,
  status: j['status'] == 'in_progress'
      ? ConsultationStatus.inProgress
      : ConsultationStatus.values.byName(j['status'] as String),
  createdAt: DateTime.parse(j['created_at'] as String),
  durationMinutes: j['duration_minutes'] as int,
  isTest: j['is_test'] as bool,
  isExtra: j['is_extra'] as bool,
  startedAt: _date(j['started_at']),
  endedAt: _date(j['ended_at']),
  rating: j['rating'] as int?,
  feedback: j['feedback'] as String?,
  overrideReason: j['override_reason'] as String?,
  exceededBy: j['exceeded_by'] as int,
  serviceMinutes: j['service_minutes'] as int?,
  mediumName: j['medium_name'] as String?,
  guideName: j['guide_name'] as String?,
  phalanxId: j['phalanx_id'] as String?,
  dirigentId: j['dirigent_id'] as String?,
  dirigentName: j['dirigent_name'] as String?,
  queuePosition: j['queue_position'] as int?,
  queuedAt: _date(j['queued_at']),
  updatedAt: _date(j['updated_at']),
);
Json mediumToJson(MediumDraft d) => {
  'id': d.id,
  'name': d.name.trim(),
  'degree': d.degree.name,
  'ribbon': d.ribbon.name,
  'nucleo_ids': d.nucleoIds,
  'guides': d.guides
      .map(
        (g) => {'id': g.id, 'name': g.name.trim(), 'phalanx_id': g.phalanxId},
      )
      .toList(),
};
Json openToJson(OpenConsultation d) => {
  'session_id': d.sessionId,
  'medium_id': d.mediumId,
  'guide_id': d.guideId,
  'password': d.password,
  'consultant_name': d.consultantName,
  'is_test': d.isTest,
  'override_reason': d.overrideReason,
};
