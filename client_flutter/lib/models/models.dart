int _int(dynamic v) => v is int ? v : int.tryParse('${v ?? ''}') ?? 0;

double _double(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

String _str(dynamic v) => v == null ? '' : v.toString();

bool _bool(dynamic v) => v == true || v == 'true' || v == 1;

class User {
  const User({
    required this.id,
    required this.userName,
    required this.nickName,
    required this.avatar,
    required this.role,
  });

  final int id;
  final String userName;
  final String nickName;
  final String avatar;
  final String role;

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: _int(json['id']),
        userName: _str(json['userName']),
        nickName: _str(json['nickName']),
        avatar: _str(json['avatar']),
        role: _str(json['role']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'userName': userName,
        'nickName': nickName,
        'avatar': avatar,
        'role': role,
      };

  String get displayName => nickName.isEmpty ? userName : nickName;
}

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.refreshExpiresIn,
    required this.deviceId,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  final int refreshExpiresIn;
  final String deviceId;
  final User user;

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        accessToken: _str(json['accessToken']),
        refreshToken: _str(json['refreshToken']),
        expiresIn: _int(json['expiresIn']),
        refreshExpiresIn: _int(json['refreshExpiresIn']),
        deviceId: _str(json['deviceId']),
        user: User.fromJson((json['user'] as Map?)?.cast<String, dynamic>() ?? {}),
      );
}

class QrCreateResult {
  const QrCreateResult({
    required this.qid,
    required this.pollToken,
    required this.qrUrl,
    required this.expiresIn,
    required this.pollInterval,
  });

  final String qid;
  final String pollToken;
  final String qrUrl;
  final int expiresIn;
  final int pollInterval;

  factory QrCreateResult.fromJson(Map<String, dynamic> json) => QrCreateResult(
        qid: _str(json['qid']),
        pollToken: _str(json['pollToken']),
        qrUrl: _str(json['qrUrl']),
        expiresIn: _int(json['expiresIn']),
        pollInterval: _int(json['pollInterval']),
      );
}

class QrPollResult {
  const QrPollResult({required this.status, this.auth});

  final String status;
  final AuthSession? auth;

  factory QrPollResult.fromJson(Map<String, dynamic> json) => QrPollResult(
        status: _str(json['status']),
        auth: json['auth'] is Map
            ? AuthSession.fromJson((json['auth'] as Map).cast<String, dynamic>())
            : null,
      );
}

class DeviceSession {
  const DeviceSession({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.appVersion,
    required this.current,
    required this.lastActiveAt,
    required this.lastIp,
  });

  final String deviceId;
  final String deviceName;
  final String platform;
  final String appVersion;
  final bool current;
  final int lastActiveAt;
  final String lastIp;

  factory DeviceSession.fromJson(Map<String, dynamic> json) => DeviceSession(
        deviceId: _str(json['deviceId']),
        deviceName: _str(json['deviceName']),
        platform: _str(json['platform']),
        appVersion: _str(json['appVersion']),
        current: _bool(json['current']),
        lastActiveAt: _int(json['lastActiveAt']),
        lastIp: _str(json['lastIp']),
      );
}

class MovieBasic {
  const MovieBasic({
    required this.id,
    required this.name,
    required this.picture,
    required this.cName,
    required this.year,
    required this.remarks,
    required this.area,
    required this.state,
    required this.subTitle,
    required this.actor,
    required this.director,
    required this.blurb,
    required this.cid,
    required this.pid,
  });

  final int id;
  final String name;
  final String picture;
  final String cName;
  final String year;
  final String remarks;
  final String area;
  final String state;
  final String subTitle;
  final String actor;
  final String director;
  final String blurb;
  final int cid;
  final int pid;

  factory MovieBasic.fromJson(Map<String, dynamic> json) => MovieBasic(
        id: _int(json['id'] ?? json['mid']),
        name: _str(json['name']),
        picture: _str(json['picture']),
        cName: _str(json['cName']),
        year: _str(json['year']),
        remarks: _str(json['remarks']),
        area: _str(json['area']),
        state: _str(json['state']),
        subTitle: _str(json['subTitle']),
        actor: _str(json['actor']),
        director: _str(json['director']),
        blurb: _str(json['blurb']),
        cid: _int(json['cid']),
        pid: _int(json['pid']),
      );

  String get meta {
    final parts = [if (year.isNotEmpty) year, if (area.isNotEmpty) area, if (remarks.isNotEmpty) remarks];
    return parts.join(' · ');
  }
}

class CategoryNode {
  const CategoryNode({
    required this.id,
    required this.pid,
    required this.name,
    required this.children,
  });

  final int id;
  final int pid;
  final String name;
  final List<CategoryNode> children;

  factory CategoryNode.fromJson(Map<String, dynamic> json) => CategoryNode(
        id: _int(json['id']),
        pid: _int(json['pid']),
        name: _str(json['name']),
        children: ((json['children'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => CategoryNode.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );
}

class BannerItem {
  const BannerItem({
    required this.mid,
    required this.name,
    required this.poster,
    required this.picture,
    required this.remark,
  });

  final int mid;
  final String name;
  final String poster;
  final String picture;
  final String remark;

  factory BannerItem.fromJson(Map<String, dynamic> json) => BannerItem(
        mid: _int(json['mid']),
        name: _str(json['name']),
        poster: _str(json['poster']),
        picture: _str(json['picture']),
        remark: _str(json['remark']),
      );
}

class IndexSection {
  const IndexSection({
    required this.nav,
    required this.movies,
  });

  final CategoryNode nav;
  final List<MovieBasic> movies;

  factory IndexSection.fromJson(Map<String, dynamic> json) => IndexSection(
        nav: CategoryNode.fromJson(
            (json['nav'] as Map?)?.cast<String, dynamic>() ?? {}),
        movies: ((json['movies'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => MovieBasic.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );
}

class IndexBundle {
  const IndexBundle({
    required this.banners,
    required this.sections,
    required this.categories,
  });

  final List<BannerItem> banners;
  final List<IndexSection> sections;
  final List<CategoryNode> categories;

  factory IndexBundle.fromJson(Map<String, dynamic> json) {
    final category =
        (json['category'] as Map?)?.cast<String, dynamic>() ?? const {};
    return IndexBundle(
      banners: ((json['banners'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => BannerItem.fromJson(e.cast<String, dynamic>()))
          .toList(),
      sections: ((json['content'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => IndexSection.fromJson(e.cast<String, dynamic>()))
          .where((s) => s.movies.isNotEmpty)
          .toList(),
      categories: ((category['children'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => CategoryNode.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }
}

class PlayItem {
  const PlayItem({required this.episode, required this.link});

  final String episode;
  final String link;

  factory PlayItem.fromJson(Map<String, dynamic> json) => PlayItem(
        episode: _str(json['episode']),
        link: _str(json['link']),
      );
}

class PlaySource {
  const PlaySource({
    required this.id,
    required this.name,
    required this.items,
  });

  final String id;
  final String name;
  final List<PlayItem> items;

  factory PlaySource.fromJson(Map<String, dynamic> json) => PlaySource(
        id: _str(json['id']),
        name: _str(json['name']),
        items: ((json['linkList'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => PlayItem.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );
}

class MovieDetail {
  const MovieDetail({
    required this.mid,
    required this.name,
    required this.picture,
    required this.cName,
    required this.year,
    required this.area,
    required this.language,
    required this.state,
    required this.remarks,
    required this.actor,
    required this.director,
    required this.dbScore,
    required this.content,
    required this.updateTime,
    required this.sources,
  });

  final int mid;
  final String name;
  final String picture;
  final String cName;
  final String year;
  final String area;
  final String language;
  final String state;
  final String remarks;
  final String actor;
  final String director;
  final String dbScore;
  final String content;
  final String updateTime;
  final List<PlaySource> sources;

  factory MovieDetail.fromJson(Map<String, dynamic> json) => MovieDetail(
        mid: _int(json['mid'] ?? json['id']),
        name: _str(json['name']),
        picture: _str(json['picture']),
        cName: _str(json['cName']),
        year: _str(json['year']),
        area: _str(json['area']),
        language: _str(json['language']),
        state: _str(json['state']),
        remarks: _str(json['remarks']),
        actor: _str(json['actor']),
        director: _str(json['director']),
        dbScore: _str(json['dbScore']),
        content: _str(json['content']),
        updateTime: _str(json['updateTime']),
        sources: ((json['list'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => PlaySource.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );

  String get meta {
    final parts = [
      if (year.isNotEmpty) year,
      if (area.isNotEmpty) area,
      if (cName.isNotEmpty) cName,
      if (remarks.isNotEmpty) remarks,
    ];
    return parts.join(' · ');
  }
}

class DetailBundle {
  const DetailBundle({required this.detail, required this.relate});

  final MovieDetail detail;
  final List<MovieBasic> relate;

  factory DetailBundle.fromJson(Map<String, dynamic> json) => DetailBundle(
        detail: MovieDetail.fromJson(
            (json['detail'] as Map?)?.cast<String, dynamic>() ?? {}),
        relate: ((json['relate'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => MovieBasic.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );
}

class PlayBundle {
  const PlayBundle({
    required this.detail,
    required this.current,
    required this.currentPlayFrom,
    required this.currentEpisode,
    required this.relate,
    required this.proxy,
  });

  final MovieDetail detail;
  final PlayItem current;
  final String currentPlayFrom;
  final int currentEpisode;
  final List<MovieBasic> relate;
  final bool proxy;

  factory PlayBundle.fromJson(Map<String, dynamic> json) => PlayBundle(
        detail: MovieDetail.fromJson(
            (json['detail'] as Map?)?.cast<String, dynamic>() ?? {}),
        current: PlayItem.fromJson(
            (json['current'] as Map?)?.cast<String, dynamic>() ?? {}),
        currentPlayFrom: _str(json['currentPlayFrom']),
        currentEpisode: _int(json['currentEpisode']),
        relate: ((json['relate'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => MovieBasic.fromJson(e.cast<String, dynamic>()))
            .toList(),
        proxy: _bool(json['proxy']),
      );
}

class PageMeta {
  const PageMeta({
    required this.current,
    required this.pageSize,
    required this.total,
    required this.pageCount,
    required this.hasMore,
  });

  final int current;
  final int pageSize;
  final int total;
  final int pageCount;
  final bool hasMore;

  factory PageMeta.fromJson(Map<String, dynamic> json) => PageMeta(
        current: _int(json['current']),
        pageSize: _int(json['pageSize']),
        total: _int(json['total']),
        pageCount: _int(json['pageCount']),
        hasMore: _bool(json['hasMore']),
      );
}

class MoviePage {
  const MoviePage({required this.list, required this.page});

  final List<MovieBasic> list;
  final PageMeta page;

  factory MoviePage.fromJson(Map<String, dynamic> json) => MoviePage(
        list: ((json['list'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => MovieBasic.fromJson(e.cast<String, dynamic>()))
            .toList(),
        page: PageMeta.fromJson(
            (json['page'] as Map?)?.cast<String, dynamic>() ?? {}),
      );
}

class WatchHistory {
  const WatchHistory({
    required this.mid,
    required this.sourceId,
    required this.episode,
    required this.episodeName,
    required this.position,
    required this.duration,
    required this.progress,
    required this.updatedAt,
    required this.movie,
  });

  final int mid;
  final String sourceId;
  final int episode;
  final String episodeName;
  final int position;
  final int duration;
  final double progress;
  final int updatedAt;
  final MovieBasic? movie;

  factory WatchHistory.fromJson(Map<String, dynamic> json) => WatchHistory(
        mid: _int(json['mid']),
        sourceId: _str(json['sourceId']),
        episode: _int(json['episode']),
        episodeName: _str(json['episodeName']),
        position: _int(json['position']),
        duration: _int(json['duration']),
        progress: _double(json['progress']),
        updatedAt: _int(json['updatedAt']),
        movie: json['movie'] is Map
            ? MovieBasic.fromJson((json['movie'] as Map).cast<String, dynamic>())
            : null,
      );
}

class FavoriteItem {
  const FavoriteItem({
    required this.mid,
    required this.updatedAt,
    required this.movie,
  });

  final int mid;
  final int updatedAt;
  final MovieBasic? movie;

  factory FavoriteItem.fromJson(Map<String, dynamic> json) => FavoriteItem(
        mid: _int(json['mid']),
        updatedAt: _int(json['updatedAt']),
        movie: json['movie'] is Map
            ? MovieBasic.fromJson((json['movie'] as Map).cast<String, dynamic>())
            : null,
      );
}
