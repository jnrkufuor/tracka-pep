// Data the app gets from the Pep API, as typed Dart classes.
// Each `fromJson` mirrors a JSON shape from pep/players/routes.py.

double? _d(dynamic v) => v == null ? null : (v as num).toDouble();
int? _i(dynamic v) => v == null ? null : (v as num).round();
List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) f) =>
    (v as List? ?? const []).map((e) => f(e as Map<String, dynamic>)).toList();

class Profile {
  Profile({
    required this.displayName,
    this.birthDate,
    this.age,
    this.sex,
    this.heightM,
    this.positions = const [],
    this.foot,
    this.region,
    this.club,
    this.bio,
    this.guardianEmail,
    this.guardianConsent = false,
  });

  final String displayName;
  final DateTime? birthDate;
  final int? age;
  final String? sex;
  final double? heightM;
  final List<String> positions;
  final String? foot;
  final String? region;
  final String? club;
  final String? bio;
  final String? guardianEmail;
  final bool guardianConsent;

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        displayName: j['displayName'] as String? ?? '',
        birthDate: j['birthDate'] == null ? null : DateTime.parse(j['birthDate'] as String),
        age: _i(j['age']),
        sex: j['sex'] as String?,
        heightM: _d(j['heightM']),
        positions: (j['positions'] as List? ?? const []).cast<String>(),
        foot: j['foot'] as String?,
        region: j['region'] as String?,
        club: j['club'] as String?,
        bio: j['bio'] as String?,
        guardianEmail: j['guardianEmail'] as String?,
        guardianConsent: j['guardianConsent'] as bool? ?? false,
      );

  String get firstName => displayName.split(' ').first;
}

class AppSettings {
  AppSettings({
    this.units = 'kmh',
    this.coachNotes = true,
    this.notifyWhenReady = true,
    this.shareWithScouts = false,
    this.mainColour = 'volt',
    this.reduceMotion = false,
    this.uploadOnWifiOnly = true,
  });

  final String units;
  final bool coachNotes;
  final bool notifyWhenReady;
  final bool shareWithScouts;

  /// Settings › Main colour: "volt" | "blue" | "pink" | "ice" | "aqua".
  final String mainColour;

  /// Settings › Accessibility: less movement, on top of the phone's own setting.
  final bool reduceMotion;

  /// Settings › Your data: clips wait for Wi-Fi unless the player chooses mobile data.
  final bool uploadOnWifiOnly;

  /// Every field has a default, so an older server that doesn't send the new
  /// ones still works (add fields, never rename them: see CLAUDE.md).
  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        units: j['units'] as String? ?? 'kmh',
        coachNotes: j['coachNotes'] as bool? ?? true,
        notifyWhenReady: j['notifyWhenReady'] as bool? ?? true,
        shareWithScouts: j['shareWithScouts'] as bool? ?? false,
        mainColour: j['mainColour'] as String? ?? 'volt',
        reduceMotion: j['reduceMotion'] as bool? ?? false,
        uploadOnWifiOnly: j['uploadOnWifiOnly'] as bool? ?? true,
      );

  /// Speed in the player's chosen unit.
  String speed(double? ms) {
    if (ms == null) return '–';
    return units == 'mph' ? (ms * 2.23694).toStringAsFixed(1) : (ms * 3.6).toStringAsFixed(1);
  }

  String get speedUnit => units == 'mph' ? 'mph' : 'km/h';
}

class Me {
  Me({
    required this.id,
    required this.email,
    required this.profile,
    required this.settings,
    required this.profileComplete,
    required this.needsGuardian,
  });

  final String id;
  final String email;
  final Profile profile;
  final AppSettings settings;
  final bool profileComplete;
  final bool needsGuardian;

  factory Me.fromJson(Map<String, dynamic> j) => Me(
        id: j['id'] as String,
        email: j['email'] as String,
        profile: Profile.fromJson(j['profile'] as Map<String, dynamic>),
        settings: AppSettings.fromJson(j['settings'] as Map<String, dynamic>),
        profileComplete: j['profileComplete'] as bool? ?? false,
        needsGuardian: j['needsGuardian'] as bool? ?? false,
      );
}

class Drill {
  Drill({required this.id, required this.label, required this.how, required this.needsCalibration, this.cones = const []});

  final String id;
  final String label;
  final String how;
  final bool needsCalibration;
  final List<List<double>> cones; // where the cones are, in metres

  factory Drill.fromJson(String id, Map<String, dynamic> j) => Drill(
        id: id,
        label: j['label'] as String,
        how: j['how'] as String,
        needsCalibration: j['needs_calibration'] as bool? ?? false,
        cones: (j['cones_m'] as List? ?? const [])
            .map((c) => (c as List).map((x) => (x as num).toDouble()).toList())
            .toList(),
      );
}

class Meta {
  Meta({required this.positions, required this.regions, required this.drills});

  final List<String> positions;
  final List<String> regions;
  final Map<String, Drill> drills;

  factory Meta.fromJson(Map<String, dynamic> j) => Meta(
        positions: (j['positions'] as List).cast<String>(),
        regions: (j['regions'] as List).cast<String>(),
        drills: (j['drills'] as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, Drill.fromJson(k, v as Map<String, dynamic>))),
      );
}

class Skill {
  Skill({
    required this.name,
    required this.score,
    this.explanation = '',
    this.drill = '',
    this.source,
    this.confidence,
    this.clips,
  });

  final String name;
  final int score;
  final String explanation;
  final String drill;
  final String? source; // drill | measured | ai_observed
  final String? confidence;
  final int? clips;

  factory Skill.fromJson(Map<String, dynamic> j) => Skill(
        name: j['name'] as String,
        score: _i(j['score']) ?? 0,
        explanation: j['explanation'] as String? ?? '',
        drill: j['drill'] as String? ?? '',
        source: j['source'] as String?,
        confidence: j['confidence'] as String?,
        clips: _i(j['clips']),
      );

  String get sourceLabel => switch (source) {
        'drill' => 'Timed drill',
        'ai_observed' => 'Pep watched',
        _ => 'Measured',
      };
}

class Moment {
  Moment({required this.atSeconds, required this.kind, required this.text, this.videoId, this.videoTitle});

  final double atSeconds;
  final String kind; // GOOD | WORK_ON
  final String text;
  final String? videoId;
  final String? videoTitle;

  bool get good => kind == 'GOOD';

  factory Moment.fromJson(Map<String, dynamic> j) => Moment(
        atSeconds: _d(j['atSeconds']) ?? 0,
        kind: j['kind'] as String? ?? 'GOOD',
        text: j['text'] as String? ?? '',
        videoId: j['videoId'] as String?,
        videoTitle: j['videoTitle'] as String?,
      );
}

class RoleFit {
  RoleFit({required this.role, required this.label, required this.score, this.coverage});

  final String role;
  final String label;
  final int score;
  final double? coverage;

  factory RoleFit.fromJson(Map<String, dynamic> j) => RoleFit(
        role: j['role'] as String,
        label: j['label'] as String,
        score: _i(j['score']) ?? 0,
        coverage: _d(j['coverage']),
      );
}

class Analysis {
  Analysis({
    this.overallScore,
    this.confidence,
    this.skills = const [],
    this.moments = const [],
    this.roleFit = const [],
    this.metrics = const {},
    this.summary,
    this.coachSource,
  });

  final int? overallScore;
  final String? confidence;
  final List<Skill> skills;
  final List<Moment> moments;
  final List<RoleFit> roleFit;
  final Map<String, double?> metrics;
  final String? summary;
  final String? coachSource;

  factory Analysis.fromJson(Map<String, dynamic> j) => Analysis(
        overallScore: _i(j['overallScore']),
        confidence: j['confidence'] as String?,
        skills: _list(j['skills'], Skill.fromJson),
        moments: _list(j['moments'], Moment.fromJson),
        roleFit: _list(j['roleFit'], RoleFit.fromJson),
        metrics: (j['metrics'] as Map<String, dynamic>? ?? const {}).map((k, v) => MapEntry(k, _d(v))),
        summary: j['summary'] as String?,
        coachSource: j['coachSource'] as String?,
      );
}

class Video {
  Video({
    required this.id,
    required this.title,
    required this.clipType,
    required this.createdAt,
    required this.status,
    this.drill,
    this.overallScore,
    this.confidence,
    this.thumbnailUrl,
    this.videoUrl,
    this.overlayUrl,
    this.error,
    this.analysis,
  });

  final String id;
  final String title;
  final String clipType;
  final String? drill;
  final DateTime createdAt;
  final String status; // QUEUED | RUNNING | READY | FAILED
  final int? overallScore;
  final String? confidence;
  final String? thumbnailUrl;
  final String? videoUrl;
  final String? overlayUrl;
  final String? error;
  final Analysis? analysis;

  bool get processing => status == 'QUEUED' || status == 'RUNNING';
  String get displayTitle => title.isEmpty ? (clipType == 'drill' ? 'Drill' : 'Clip') : title;

  factory Video.fromJson(Map<String, dynamic> j) => Video(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        clipType: j['clipType'] as String? ?? 'match',
        drill: j['drill'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
        status: j['status'] as String? ?? 'QUEUED',
        overallScore: _i(j['overallScore']),
        confidence: j['confidence'] as String?,
        thumbnailUrl: j['thumbnailUrl'] as String?,
        videoUrl: j['videoUrl'] as String?,
        overlayUrl: j['overlayUrl'] as String?,
        error: j['error'] as String?,
        analysis: j['analysis'] == null ? null : Analysis.fromJson(j['analysis'] as Map<String, dynamic>),
      );
}

class CoachSummary {
  CoachSummary({
    required this.clipsUploaded,
    required this.clipsAnalysed,
    required this.clipsNeeded,
    required this.processing,
    this.overallScore,
    this.change,
    this.confidence = 'LOW',
    this.skills = const [],
    this.focus = const [],
    this.strengths = const [],
    this.trend = const [],
    this.recentMoments = const [],
    this.suggestedDrill,
    this.bestRoles = const [],
  });

  final int clipsUploaded;
  final int clipsAnalysed;
  final int clipsNeeded;
  final int processing;
  final int? overallScore;
  final int? change;
  final String confidence;
  final List<Skill> skills;
  final List<Skill> focus;
  final List<Skill> strengths;
  final List<(String, int)> trend;
  final List<Moment> recentMoments;
  final Map<String, dynamic>? suggestedDrill;
  final List<RoleFit> bestRoles;

  factory CoachSummary.fromJson(Map<String, dynamic> j) => CoachSummary(
        clipsUploaded: _i(j['clipsUploaded']) ?? 0,
        clipsAnalysed: _i(j['clipsAnalysed']) ?? 0,
        clipsNeeded: _i(j['clipsNeeded']) ?? 3,
        processing: _i(j['processing']) ?? 0,
        overallScore: _i(j['overallScore']),
        change: _i(j['change']),
        confidence: j['confidence'] as String? ?? 'LOW',
        skills: _list(j['skills'], Skill.fromJson),
        focus: _list(j['focus'], Skill.fromJson),
        strengths: _list(j['strengths'], Skill.fromJson),
        trend: (j['trend'] as List? ?? const [])
            .map((e) => ((e as Map)['week'] as String, _i(e['score']) ?? 0))
            .toList(),
        recentMoments: _list(j['recentMoments'], Moment.fromJson),
        suggestedDrill: j['suggestedDrill'] as Map<String, dynamic>?,
        bestRoles: _list(j['bestRoles'], RoleFit.fromJson),
      );
}
