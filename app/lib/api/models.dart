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
    this.shirtName,
    this.shirtNumber,
    this.town,
    this.level,
    this.goal,
    this.style,
    this.weakFoot,
    this.guardianPhone,
    this.guardianRelation,
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

  // Onboarding v2 (null from older servers).
  final String? shirtName;
  final int? shirtNumber;

  /// Private: never shown to other players (only the region is).
  final String? town;

  /// fun | amateur | school | club | academy | pro
  final String? level;

  /// fun | school | academy | standout | better | looking
  final String? goal;
  final String? style;

  /// 1 (hard to use) … 5 (strong as my best).
  final int? weakFoot;
  final String? guardianPhone;
  final String? guardianRelation;

  /// Players having fun or looking around get a lighter app (no scouting profile).
  bool get casual => goal == 'fun' || goal == 'looking';

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
        shirtName: j['shirtName'] as String?,
        shirtNumber: _i(j['shirtNumber']),
        town: j['town'] as String?,
        level: j['level'] as String?,
        goal: j['goal'] as String?,
        style: j['style'] as String?,
        weakFoot: _i(j['weakFoot']),
        guardianPhone: j['guardianPhone'] as String?,
        guardianRelation: j['guardianRelation'] as String?,
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
    this.findable = false,
    this.notifyOpportunities = false,
    this.notifications = const {},
    this.quietHours = true,
    this.homeCards,
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

  /// Pitchside: other players can find you in search (under 18 also needs your guardian).
  final bool findable;

  /// "Tell me when there's an opportunity near me".
  final bool notifyOpportunities;

  /// Settings › Notifications: kind → on (tips, reviews, reminders, events, respect).
  final Map<String, bool> notifications;

  /// No push messages 9 pm to 7 am (always on for under-18s).
  final bool quietHours;

  /// Home: the cards shown, in order. Null = Pep's suggestion (Customise home).
  final List<String>? homeCards;

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
        findable: j['findable'] as bool? ?? false,
        notifyOpportunities: j['notifyOpportunities'] as bool? ?? false,
        notifications: (j['notifications'] as Map<String, dynamic>? ?? const {}).map((k, v) => MapEntry(k, v as bool)),
        quietHours: j['quietHours'] as bool? ?? true,
        homeCards: (j['homeCards'] as List?)?.cast<String>(),
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
    this.guardianStatus,
  });

  final String id;
  final String email;
  final Profile profile;
  final AppSettings settings;
  final bool profileComplete;
  final bool needsGuardian;

  /// Under 18: none | pending | approved | declined | revoked | expired. Null for adults.
  final String? guardianStatus;

  factory Me.fromJson(Map<String, dynamic> j) => Me(
        id: j['id'] as String,
        email: j['email'] as String,
        profile: Profile.fromJson(j['profile'] as Map<String, dynamic>),
        settings: AppSettings.fromJson(j['settings'] as Map<String, dynamic>),
        profileComplete: j['profileComplete'] as bool? ?? false,
        needsGuardian: j['needsGuardian'] as bool? ?? false,
        guardianStatus: j['guardianStatus'] as String?,
      );
}

/// GET /v1/guardian: where the guardian's approval stands (pep/players/guardian_routes.py).
class GuardianState {
  GuardianState({
    required this.needed,
    required this.status,
    this.name,
    this.relation,
    this.phone,
    this.sendStatus,
    this.resendAt,
    this.permissions = const {},
    this.pendingKinds = const [],
    this.textsLive = false,
    this.selfConfirm = false,
  });

  final bool needed;
  final String status; // none | pending | approved | declined | revoked | expired
  final String? name;
  final String? relation;
  final String? phone; // masked: +233 24 ••• 4567
  final String? sendStatus; // logged | sent | failed
  final DateTime? resendAt;
  final Map<String, bool> permissions; // account, post, shareCard, search
  final List<String> pendingKinds;
  final bool textsLive;
  final bool selfConfirm;

  String get who => (name ?? '').isNotEmpty ? name! : 'your guardian';
  bool can(String kind) => permissions[kind] ?? false;

  factory GuardianState.fromJson(Map<String, dynamic> j) => GuardianState(
        needed: j['needed'] as bool? ?? false,
        status: j['status'] as String? ?? 'none',
        name: j['name'] as String?,
        relation: j['relation'] as String?,
        phone: j['phone'] as String?,
        sendStatus: j['sendStatus'] as String?,
        resendAt: j['resendAt'] == null ? null : DateTime.parse(j['resendAt'] as String).toLocal(),
        permissions: (j['permissions'] as Map<String, dynamic>? ?? const {}).map((k, v) => MapEntry(k, v as bool)),
        pendingKinds: [
          for (final r in (j['requests'] as List? ?? const []))
            if ((r as Map)['status'] == 'pending') r['kind'] as String,
        ],
        textsLive: j['textsLive'] as bool? ?? false,
        selfConfirm: j['selfConfirm'] as bool? ?? false,
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
  Meta({required this.positions, required this.regions, required this.drills, this.textsLive = false, this.guardianSelfConfirm = true});

  final List<String> positions;
  final List<String> regions;
  final Map<String, Drill> drills;

  /// Guardian texts reach phones (false while SMS is a placeholder).
  final bool textsLive;

  /// Show the interim "they've already said yes" tick for under-18s.
  final bool guardianSelfConfirm;

  factory Meta.fromJson(Map<String, dynamic> j) => Meta(
        positions: (j['positions'] as List).cast<String>(),
        regions: (j['regions'] as List).cast<String>(),
        drills: (j['drills'] as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, Drill.fromJson(k, v as Map<String, dynamic>))),
        textsLive: j['textsLive'] as bool? ?? false,
        guardianSelfConfirm: j['guardianSelfConfirm'] as bool? ?? true,
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
    this.review,
    this.reviewNote,
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

  /// Pep's review as a story (headline, moments, tips): GET /v1/videos/{id} only.
  final Review? review;

  /// The one line under the clip in Pep › Reviews ("2 things went well, 1 to work on.").
  final String? reviewNote;

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
        review: j['review'] == null ? null : Review.fromJson(j['review'] as Map<String, dynamic>),
        reviewNote: j['reviewNote'] as String?,
      );
}

/// A moment Pep pointed out: tap its time to jump the video there.
class ReviewMoment {
  ReviewMoment({required this.atSeconds, required this.good, required this.title, required this.text, this.area, this.areaName});

  final double atSeconds;
  final bool good;
  final String title;
  final String text;
  final String? area;
  final String? areaName;

  factory ReviewMoment.fromJson(Map<String, dynamic> j) => ReviewMoment(
        atSeconds: _d(j['atSeconds']) ?? 0,
        good: j['kind'] == 'GOOD',
        title: j['title'] as String? ?? '',
        text: j['text'] as String? ?? '',
        area: j['area'] as String?,
        areaName: j['areaName'] as String?,
      );
}

/// A drill Pep picked for a tip, from the kit the player has.
class TipDrill {
  TipDrill({required this.id, required this.name, required this.minutes, required this.how, this.needs = const []});

  final String id;
  final String name;
  final int minutes;
  final String how;
  final List<String> needs;

  factory TipDrill.fromJson(Map<String, dynamic> j) => TipDrill(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        minutes: _i(j['minutes']) ?? 10,
        how: j['how'] as String? ?? '',
        needs: [for (final n in (j['needs'] as List? ?? const [])) n as String],
      );
}

/// One thing to practise: from a moment in a clip, about a skill area, with a drill.
class ReviewTip {
  ReviewTip({
    required this.area,
    required this.areaName,
    required this.group,
    required this.title,
    required this.text,
    this.atSeconds,
    this.drill,
    this.videoId,
    this.videoTitle,
    this.clipType,
    this.thumbnailUrl,
  });

  final String area;
  final String areaName;
  final String group;
  final String title;
  final String text;
  final double? atSeconds;
  final TipDrill? drill;
  // Set in GET /v1/tips (which clip the tip came from).
  final String? videoId;
  final String? videoTitle;
  final String? clipType;
  final String? thumbnailUrl;

  factory ReviewTip.fromJson(Map<String, dynamic> j) => ReviewTip(
        area: j['area'] as String,
        areaName: j['areaName'] as String? ?? '',
        group: j['group'] as String? ?? '',
        title: j['title'] as String? ?? '',
        text: j['text'] as String? ?? '',
        atSeconds: _d(j['atSeconds']),
        drill: j['drill'] == null ? null : TipDrill.fromJson(j['drill'] as Map<String, dynamic>),
        videoId: j['videoId'] as String?,
        videoTitle: j['videoTitle'] as String?,
        clipType: j['clipType'] as String?,
        thumbnailUrl: j['thumbnailUrl'] as String?,
      );
}

class ReviewArea {
  ReviewArea({required this.id, required this.name, required this.group, required this.good});

  final String id;
  final String name;
  final String group;
  final bool good;

  factory ReviewArea.fromJson(Map<String, dynamic> j) => ReviewArea(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        group: j['group'] as String? ?? '',
        good: j['kind'] == 'GOOD',
      );
}

/// Pep's review of one clip (pep/players/review.py). Words and drills, never scores.
class Review {
  Review({
    required this.title,
    required this.text,
    this.wentWell = const [],
    this.workOn = const [],
    this.tips = const [],
    this.areas = const [],
    this.source = 'rules',
  });

  final String title;
  final String text;
  final List<ReviewMoment> wentWell;
  final List<ReviewMoment> workOn;
  final List<ReviewTip> tips;
  final List<ReviewArea> areas;
  final String source; // gemini (watched by the AI coach) | rules (written from measurements)

  factory Review.fromJson(Map<String, dynamic> j) {
    final h = j['headline'] as Map<String, dynamic>? ?? const {};
    return Review(
      title: h['title'] as String? ?? '',
      text: h['text'] as String? ?? '',
      wentWell: _list(j['wentWell'], ReviewMoment.fromJson),
      workOn: _list(j['workOn'], ReviewMoment.fromJson),
      tips: _list(j['tips'], ReviewTip.fromJson),
      areas: _list(j['areas'], ReviewArea.fromJson),
      source: j['source'] as String? ?? 'rules',
    );
  }
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
    this.skillAreas,
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

  /// Me › Growth: bands per skill area (null from older servers).
  final SkillAreas? skillAreas;

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
        skillAreas: j['skillAreas'] is Map<String, dynamic> ? SkillAreas.fromJson(j['skillAreas'] as Map<String, dynamic>) : null,
      );
}


/// Me › Growth (GET /v1/coach → skillAreas): skill areas grouped as Skills,
/// Reading the game, Body (Goalkeeping), Attitude, compared with the player's age group.
class SkillAreas {
  SkillAreas({required this.ageGroup, required this.comparedWith, required this.measured, required this.groups});

  final String ageGroup;
  final String comparedWith;
  final int measured;
  final List<SkillGroup> groups;

  factory SkillAreas.fromJson(Map<String, dynamic> j) => SkillAreas(
        ageGroup: j['ageGroup'] as String? ?? '',
        comparedWith: j['comparedWith'] as String? ?? '',
        measured: _i(j['measured']) ?? 0,
        groups: _list(j['groups'], SkillGroup.fromJson),
      );
}

class SkillGroup {
  SkillGroup({required this.name, required this.items});

  final String name;
  final List<SkillItem> items;

  factory SkillGroup.fromJson(Map<String, dynamic> j) =>
      SkillGroup(name: j['name'] as String? ?? '', items: _list(j['items'], SkillItem.fromJson));
}

class SkillItem {
  SkillItem({
    required this.id,
    required this.name,
    required this.key,
    required this.state,
    this.band,
    this.average,
    this.confidence = 'low',
    this.trend = 'new',
    this.measurements = 0,
    this.howToMeasure,
  });

  final String id;
  final String name;

  /// Matters most for the player's position (a small dot in the app).
  final bool key;

  /// "measured" | "not_seen" | "coming_later" | "cant_see".
  final String state;

  /// "below" | "average" | "above" | "strong" | "standout" (only when measured).
  final String? band;

  /// The measured value in plain words ("10 m in 1.92 s").
  final String? average;
  final String confidence;
  final String trend;
  final int measurements;

  /// What to film so Pep can measure it (when not seen yet).
  final String? howToMeasure;

  bool get measured => state == 'measured';

  /// The words shown instead of a band when it isn't measured.
  String get stateLabel => switch (state) {
        'coming_later' => 'Coming later',
        'cant_see' => "Pep can't see this",
        _ => 'Not seen yet',
      };

  factory SkillItem.fromJson(Map<String, dynamic> j) => SkillItem(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        key: j['key'] as bool? ?? false,
        state: j['state'] as String? ?? 'not_seen',
        band: j['band'] as String?,
        average: j['average'] as String?,
        confidence: j['confidence'] as String? ?? 'low',
        trend: j['trend'] as String? ?? 'new',
        measurements: _i(j['measurements']) ?? 0,
        howToMeasure: j['howToMeasure'] as String?,
      );
}

// ---------------------------------------------------------------- training (GET /v1/week etc.)

/// One thing on a day: your own football (team, match, school, game), a Pep
/// session, a rest day, or a timed test.
class WeekItem {
  WeekItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.status,
    this.time,
    this.durationMin,
    this.mode,
    this.moved = false,
    this.repeats = false,
    this.drill,
  });

  final String id;

  /// "team" | "match" | "school" | "game" | "other" | "pep" | "rest" | "test".
  final String kind;
  final String title;

  /// "planned" | "done" | "skipped".
  final String status;
  final String? time;
  final int? durationMin;

  /// Pep sessions: "normal" | "light" | "rest".
  final String? mode;
  final bool moved;
  final bool repeats;

  /// Tests: which standard drill to film.
  final String? drill;

  bool get isPep => kind == 'pep' || kind == 'rest';
  bool get isFootball => !isPep && kind != 'test';

  factory WeekItem.fromJson(Map<String, dynamic> j) => WeekItem(
        id: j['id'] as String,
        kind: j['kind'] as String? ?? 'other',
        title: j['title'] as String? ?? '',
        status: j['status'] as String? ?? 'planned',
        time: j['time'] as String?,
        durationMin: _i(j['durationMin']),
        mode: j['mode'] as String?,
        moved: j['moved'] as bool? ?? false,
        repeats: j['repeats'] as bool? ?? false,
        drill: j['drill'] as String?,
      );
}

class WeekDay {
  WeekDay({required this.date, required this.weekday, required this.isToday, required this.matchDay, required this.items});

  final DateTime date;
  final String weekday;
  final bool isToday;
  final bool matchDay;
  final List<WeekItem> items;

  factory WeekDay.fromJson(Map<String, dynamic> j) => WeekDay(
        date: DateTime.parse(j['date'] as String),
        weekday: j['weekday'] as String? ?? '',
        isToday: j['isToday'] as bool? ?? false,
        matchDay: j['matchDay'] as bool? ?? false,
        items: _list(j['items'], WeekItem.fromJson),
      );
}

class Week {
  Week({required this.start, required this.today, required this.health, required this.days, this.sessionsPerWeek = 3});

  final DateTime start;
  final DateTime today;
  final String health;
  final int sessionsPerWeek;
  final List<WeekDay> days;

  WeekDay? get todayDay => days.where((d) => d.isToday).firstOrNull;

  /// The next Pep session from today that isn't done or skipped.
  (WeekDay, WeekItem)? get nextSession {
    for (final d in days) {
      if (d.date.isBefore(today)) continue;
      for (final i in d.items) {
        if (i.isPep && i.status == 'planned') return (d, i);
      }
    }
    return null;
  }

  factory Week.fromJson(Map<String, dynamic> j) => Week(
        start: DateTime.parse(j['start'] as String),
        today: DateTime.parse(j['today'] as String),
        health: (j['health'] as Map?)?['status'] as String? ?? 'fine',
        sessionsPerWeek: _i(j['sessionsPerWeek']) ?? 3,
        days: _list(j['days'], WeekDay.fromJson),
      );
}

class SessionStep {
  SessionStep({required this.id, required this.name, required this.minutes, required this.how, this.needs = const [], this.film, this.test});

  final String id;
  final String name;
  final int minutes;
  final String how;
  final List<String> needs;

  /// A standard drill Pep can count if you film it.
  final String? film;

  /// Set when this step is a timed test.
  final String? test;

  factory SessionStep.fromJson(Map<String, dynamic> j) => SessionStep(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        minutes: _i(j['minutes']) ?? 0,
        how: j['how'] as String? ?? '',
        needs: (j['needs'] as List? ?? const []).cast<String>(),
        film: j['film'] as String?,
        test: j['test'] as String?,
      );
}

class SessionPlan {
  SessionPlan({
    required this.key,
    required this.date,
    required this.mode,
    required this.title,
    required this.minutes,
    required this.focus,
    required this.steps,
    required this.safety,
    required this.status,
  });

  final String key;
  final DateTime date;
  final String mode;
  final String title;
  final int minutes;

  /// Skill areas this session works on (names).
  final List<String> focus;
  final List<SessionStep> steps;
  final String safety;
  final String status;

  factory SessionPlan.fromJson(Map<String, dynamic> j) => SessionPlan(
        key: j['key'] as String,
        date: DateTime.parse(j['date'] as String),
        mode: j['mode'] as String? ?? 'normal',
        title: j['title'] as String? ?? '',
        minutes: _i(j['minutes']) ?? 0,
        focus: (j['focus'] as List? ?? const []).map((e) => (e as Map)['name'] as String).toList(),
        steps: _list(j['steps'], SessionStep.fromJson),
        safety: j['safety'] as String? ?? '',
        status: j['status'] as String? ?? 'planned',
      );
}

/// How your body feels (GET/PUT /v1/health).
class HealthState {
  HealthState({required this.status, this.area, this.advice = ''});

  /// "fine" | "sore" | "pain" | "injured".
  final String status;
  final String? area;
  final String advice;

  factory HealthState.fromJson(Map<String, dynamic> j) =>
      HealthState(status: j['status'] as String? ?? 'fine', area: j['area'] as String?, advice: j['advice'] as String? ?? '');
}

/// Your own football (GET /v1/events): team training, matches, school, games.
class FootballEvent {
  FootballEvent({required this.id, required this.kind, required this.title, this.weekdays = const [], this.onDate, this.time, this.durationMin = 90});

  final String id;
  final String kind;
  final String title;

  /// Repeating: 0 = Monday … 6 = Sunday. Empty for a one-off.
  final List<int> weekdays;
  final DateTime? onDate;
  final String? time;
  final int durationMin;

  factory FootballEvent.fromJson(Map<String, dynamic> j) => FootballEvent(
        id: j['id'] as String,
        kind: j['kind'] as String? ?? 'other',
        title: j['title'] as String? ?? '',
        weekdays: (j['weekdays'] as List? ?? const []).map((e) => (e as num).toInt()).toList(),
        onDate: j['onDate'] == null ? null : DateTime.parse(j['onDate'] as String),
        time: j['time'] as String?,
        durationMin: _i(j['durationMin']) ?? 90,
      );
}


/// A player card as people with the share link see it (pep/players/card.py).
/// Only safe fields: never the full name, date of birth, town or contact details.
class PlayerCard {
  PlayerCard({
    required this.shirtName,
    required this.initials,
    this.shirtNumber,
    this.positions = const [],
    this.positionName,
    this.foot,
    this.region,
    this.level,
    this.ageGroup,
    this.style,
    this.pepSees = const [],
    this.bests = const [],
    this.skills = const [],
    this.comparedWith = '',
    this.clips = const [],
    this.under18 = false,
  });

  final String shirtName;
  final String initials;
  final int? shirtNumber;
  final List<String> positions;
  final String? positionName;
  final String? foot;
  final String? region;
  final String? level;
  final String? ageGroup;
  final String? style;
  final List<String> pepSees;
  final List<({String label, String value, String unit})> bests;
  final List<({String name, String band, String? average, String confidence, String trend})> skills;
  final String comparedWith;
  final List<({String id, String title, String? thumbnailUrl, String videoUrl, String date})> clips;
  final bool under18;

  String get line => [
        if (foot != null) '${foot![0].toUpperCase()}${foot!.substring(1)} foot',
        if (region != null) region!,
        if (level != null) level!,
        if (ageGroup != null) ageGroup!,
      ].join(' · ');

  factory PlayerCard.fromJson(Map<String, dynamic> j) => PlayerCard(
        shirtName: j['shirtName'] as String? ?? '',
        initials: j['initials'] as String? ?? '?',
        shirtNumber: _i(j['shirtNumber']),
        positions: [for (final p in (j['positions'] as List? ?? const [])) p as String],
        positionName: j['positionName'] as String?,
        foot: j['foot'] as String?,
        region: j['region'] as String?,
        level: j['level'] as String?,
        ageGroup: j['ageGroup'] as String?,
        style: j['style'] as String?,
        pepSees: [for (final p in (j['pepSees'] as List? ?? const [])) p as String],
        bests: [
          for (final b in (j['bests'] as List? ?? const []))
            (label: (b as Map)['label'] as String, value: b['value'] as String, unit: b['unit'] as String? ?? ''),
        ],
        skills: [
          for (final s in (j['skills'] as List? ?? const []))
            (
              name: (s as Map)['name'] as String,
              band: s['band'] as String? ?? '',
              average: s['average'] as String?,
              confidence: s['confidence'] as String? ?? 'low',
              trend: s['trend'] as String? ?? 'new',
            ),
        ],
        comparedWith: j['comparedWith'] as String? ?? '',
        clips: [
          for (final c in (j['clips'] as List? ?? const []))
            (
              id: (c as Map)['id'] as String,
              title: c['title'] as String? ?? '',
              thumbnailUrl: c['thumbnailUrl'] as String?,
              videoUrl: c['videoUrl'] as String,
              date: c['date'] as String? ?? '',
            ),
        ],
        under18: j['under18'] as bool? ?? false,
      );
}

/// GET /v1/card: your card, the share link, and what's shown on it.
class CardState {
  CardState({required this.card, required this.linkOn, this.url, this.show = const {}, this.portfolio = const [], this.canShare = false});

  final PlayerCard card;
  final bool linkOn;
  final String? url;
  final Map<String, bool> show; // bests, skills, clips
  final List<String> portfolio; // video ids, in order
  final bool canShare;

  factory CardState.fromJson(Map<String, dynamic> j) {
    final link = j['link'] as Map<String, dynamic>? ?? const {};
    return CardState(
      card: PlayerCard.fromJson(j['card'] as Map<String, dynamic>),
      linkOn: link['on'] as bool? ?? false,
      url: link['url'] as String?,
      show: (j['show'] as Map<String, dynamic>? ?? const {}).map((k, v) => MapEntry(k, v as bool)),
      portfolio: [for (final v in (j['portfolio'] as List? ?? const [])) v as String],
      canShare: j['canShare'] as bool? ?? false,
    );
  }
}

/// How other players see someone on Pitchside: shirt name, position, age group, region.
class FeedAuthor {
  FeedAuthor({required this.id, required this.shirtName, required this.initials, this.position, this.ageGroup, this.region, this.under18 = false, this.following = false});

  final String id;
  final String shirtName;
  final String initials;
  final String? position;
  final String? ageGroup;
  final String? region;
  final bool under18;
  final bool following;

  String get line => [if (position != null) position!, if (ageGroup != null) ageGroup!, if (region != null) region!].join(' · ');

  factory FeedAuthor.fromJson(Map<String, dynamic> j) => FeedAuthor(
        id: j['id'] as String,
        shirtName: j['shirtName'] as String? ?? '',
        initials: j['initials'] as String? ?? '?',
        position: j['position'] as String?,
        ageGroup: j['ageGroup'] as String?,
        region: j['region'] as String?,
        under18: j['under18'] as bool? ?? false,
        following: j['following'] as bool? ?? false,
      );
}

/// A posted clip. No Pep here: Pep's notes are only for the player who filmed it.
class FeedPost {
  FeedPost({
    required this.id,
    required this.author,
    required this.videoUrl,
    this.caption = '',
    this.challenge,
    this.thumbnailUrl,
    this.respect = 0,
    this.respected = false,
    this.saved = false,
    this.mine = false,
  });

  final String id;
  final FeedAuthor author;
  final String videoUrl;
  final String caption;
  final String? challenge;
  final String? thumbnailUrl;
  int respect;
  bool respected;
  bool saved;
  final bool mine;

  factory FeedPost.fromJson(Map<String, dynamic> j) => FeedPost(
        id: j['id'] as String,
        author: FeedAuthor.fromJson(j['author'] as Map<String, dynamic>),
        videoUrl: j['videoUrl'] as String,
        caption: j['caption'] as String? ?? '',
        challenge: j['challenge'] as String?,
        thumbnailUrl: j['thumbnailUrl'] as String?,
        respect: _i(j['respect']) ?? 0,
        respected: j['respected'] as bool? ?? false,
        saved: j['saved'] as bool? ?? false,
        mine: j['mine'] as bool? ?? false,
      );
}

class PlayerPage {
  PlayerPage({required this.player, this.style, this.level, this.clips = 0, this.respect = 0, this.followers = 0, this.posts = const []});

  final FeedAuthor player;
  final String? style;
  final String? level;
  final int clips;
  final int respect;
  final int followers;
  final List<FeedPost> posts;

  factory PlayerPage.fromJson(Map<String, dynamic> j) {
    final p = j['player'] as Map<String, dynamic>;
    return PlayerPage(
      player: FeedAuthor.fromJson(p),
      style: p['style'] as String?,
      level: p['level'] as String?,
      clips: _i(j['clips']) ?? 0,
      respect: _i(j['respect']) ?? 0,
      followers: _i(j['followers']) ?? 0,
      posts: _list(j['posts'], FeedPost.fromJson),
    );
  }
}

class WeeklyChallenge {
  WeeklyChallenge({
    required this.id,
    required this.name,
    required this.group,
    required this.how,
    required this.drill,
    required this.endsOn,
    this.steps = const [],
    this.best,
    this.band,
    this.tries = 0,
    this.playersIn = 0,
  });

  final String id;
  final String name;
  final String group;
  final String how;
  final String drill;
  final DateTime endsOn;
  final List<String> steps;
  final String? best;
  final String? band;
  final int tries;
  final int playersIn;

  factory WeeklyChallenge.fromJson(Map<String, dynamic> j) => WeeklyChallenge(
        id: j['id'] as String,
        name: j['name'] as String,
        group: j['group'] as String? ?? '',
        how: j['how'] as String? ?? '',
        drill: j['drill'] as String,
        endsOn: DateTime.parse(j['endsOn'] as String),
        steps: [for (final s in (j['steps'] as List? ?? const [])) s as String],
        best: j['best'] as String?,
        band: j['band'] as String?,
        tries: _i(j['tries']) ?? 0,
        playersIn: _i(j['playersIn']) ?? 0,
      );
}

class ChallengesState {
  ChallengesState({required this.thisWeek, this.fun = const [], this.past = const [], this.comparedWith = ''});

  final WeeklyChallenge thisWeek;
  final List<({String id, String name, String how, int playersIn})> fun;
  final List<({String id, String name, String group, String? best, String? band})> past;
  final String comparedWith;

  factory ChallengesState.fromJson(Map<String, dynamic> j) => ChallengesState(
        thisWeek: WeeklyChallenge.fromJson(j['thisWeek'] as Map<String, dynamic>),
        fun: [
          for (final f in (j['fun'] as List? ?? const []))
            (id: (f as Map)['id'] as String, name: f['name'] as String, how: f['how'] as String? ?? '', playersIn: _i(f['playersIn']) ?? 0),
        ],
        past: [
          for (final p in (j['past'] as List? ?? const []))
            (id: (p as Map)['id'] as String, name: p['name'] as String, group: p['group'] as String? ?? '', best: p['best'] as String?, band: p['band'] as String?),
        ],
        comparedWith: j['comparedWith'] as String? ?? '',
      );
}

class Pitch {
  Pitch({
    required this.id,
    required this.name,
    required this.surface,
    required this.size,
    required this.town,
    this.confirmations = 0,
    this.confirmed = false,
    this.needs = 0,
    this.confirmedByMe = false,
    this.addedByMe = false,
  });

  final String id;
  final String name;
  final String surface;
  final String size;
  final String town;
  final int confirmations;
  final bool confirmed;
  final int needs;
  final bool confirmedByMe;
  final bool addedByMe;

  factory Pitch.fromJson(Map<String, dynamic> j) => Pitch(
        id: j['id'] as String,
        name: j['name'] as String,
        surface: j['surface'] as String? ?? '',
        size: j['size'] as String? ?? '',
        town: j['town'] as String? ?? '',
        confirmations: _i(j['confirmations']) ?? 0,
        confirmed: j['confirmed'] as bool? ?? false,
        needs: _i(j['needs']) ?? 0,
        confirmedByMe: j['confirmedByMe'] as bool? ?? false,
        addedByMe: j['addedByMe'] as bool? ?? false,
      );
}

/// One line in the bell (pep/players/notifications.py).
class AppNotification {
  AppNotification({required this.id, required this.kind, required this.group, required this.title, required this.createdAt, this.body = '', this.link, this.read = false});

  final String id;
  final String kind;
  final String group; // pep | activity
  final String title;
  final String body;
  final Map<String, dynamic>? link; // {"screen": "video", "id": "..."}
  final DateTime createdAt;
  bool read;

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as String,
        kind: j['kind'] as String? ?? '',
        group: j['group'] as String? ?? 'activity',
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        link: j['link'] as Map<String, dynamic>?,
        createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
        read: j['read'] as bool? ?? false,
      );
}

/// A skill area as the Pep tab shows it: name, band, trend. Never a 0-100 score.
class AreaLine {
  AreaLine({required this.id, required this.name, required this.group, this.band, this.trend = 'new', this.average, this.state = 'not_seen'});

  final String id;
  final String name;
  final String group;
  final String? band;
  final String trend; // growing | steady | dipping | new
  final String? average;
  final String state;

  String get trendWords => switch (trend) {
        'growing' => 'Growing',
        'dipping' => 'Dipping a little',
        'steady' => 'Steady',
        _ => state == 'measured' ? 'Just started' : 'Not seen yet',
      };

  factory AreaLine.fromJson(Map<String, dynamic> j) => AreaLine(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        group: j['group'] as String? ?? '',
        band: j['band'] as String?,
        trend: j['trend'] as String? ?? 'new',
        average: j['average'] as String?,
        state: j['state'] as String? ?? 'not_seen',
      );
}

/// GET /v1/focus: what the sessions work on, the next test, your bests, what's growing.
class FocusState {
  FocusState({this.focus = const [], this.growing = const [], this.nextTest, this.bests = const [], this.comparedWith = ''});

  final List<AreaLine> focus;
  final List<AreaLine> growing;
  final ({String drill, String name, DateTime? date})? nextTest;
  final List<({String metric, String label, String value, String unit})> bests;
  final String comparedWith;

  factory FocusState.fromJson(Map<String, dynamic> j) {
    final t = j['nextTest'] as Map<String, dynamic>?;
    return FocusState(
      focus: _list(j['focus'], AreaLine.fromJson),
      growing: _list(j['growing'], AreaLine.fromJson),
      nextTest: t == null
          ? null
          : (drill: t['drill'] as String, name: t['name'] as String, date: t['date'] == null ? null : DateTime.parse(t['date'] as String)),
      bests: [
        for (final b in (j['bests'] as List? ?? const []))
          (metric: (b as Map)['metric'] as String, label: b['label'] as String, value: b['value'] as String, unit: b['unit'] as String? ?? ''),
      ],
      comparedWith: j['comparedWith'] as String? ?? '',
    );
  }
}

/// GET /v1/progress: Home's progress cards (pep/players/progress.py).
class ProgressState {
  ProgressState({this.tests = const [], this.streakWeeks = 0, this.bestStreak = 0, this.weekDone = 0, this.weekPlanned = 0, this.readyDone = 0, this.readyTotal = 5, this.readyNext, this.readySteps = const [], this.nextRetest});

  final List<({String label, String unit, double first, double latest, double change, bool better, int weeks, String? line})> tests;
  final int streakWeeks;
  final int bestStreak;
  final int weekDone;
  final int weekPlanned;
  final int readyDone;
  final int readyTotal;
  final String? readyNext;
  final List<({String name, bool done})> readySteps;
  final String? nextRetest;

  factory ProgressState.fromJson(Map<String, dynamic> j) {
    final s = j['streak'] as Map<String, dynamic>? ?? const {};
    final w = s['thisWeek'] as Map<String, dynamic>?;
    final r = j['readiness'] as Map<String, dynamic>? ?? const {};
    return ProgressState(
      tests: [
        for (final t in (j['tests'] as List? ?? const []))
          (
            label: (t as Map)['label'] as String,
            unit: t['unit'] as String? ?? '',
            first: (t['first'] as num).toDouble(),
            latest: (t['latest'] as num).toDouble(),
            change: (t['change'] as num).toDouble(),
            better: t['better'] as bool? ?? false,
            weeks: (t['weeks'] as num?)?.toInt() ?? 1,
            line: t['line'] as String?,
          ),
      ],
      streakWeeks: _i(s['weeks']) ?? 0,
      bestStreak: _i(s['best']) ?? 0,
      weekDone: _i(w?['done']) ?? 0,
      weekPlanned: _i(w?['planned']) ?? 0,
      readyDone: _i(r['done']) ?? 0,
      readyTotal: _i(r['total']) ?? 5,
      readyNext: r['next'] as String?,
      readySteps: [for (final x in (r['steps'] as List? ?? const [])) (name: (x as Map)['name'] as String, done: x['done'] as bool? ?? false)],
      nextRetest: j['nextRetest'] as String?,
    );
  }
}
