import '../core/api_client.dart';
import '../models/models.dart';

class ContentService {
  ContentService(this.api);

  final ApiClient api;

  Future<IndexBundle> index() async {
    final data = await api.get('/api/v1/index');
    return IndexBundle.fromJson(_map(data));
  }

  Future<DetailBundle> detail(int mid) async {
    final data = await api.get('/api/v1/films/$mid');
    return DetailBundle.fromJson(_map(data));
  }

  Future<PlayBundle> play(
    int mid, {
    String? playFrom,
    int episode = 0,
  }) async {
    final data = await api.get(
      '/api/v1/films/$mid/play',
      query: {
        if (playFrom != null && playFrom.isNotEmpty) 'playFrom': playFrom,
        'episode': episode,
      },
    );
    return PlayBundle.fromJson(_map(data));
  }

  Future<MoviePage> search(
    String keyword, {
    int current = 1,
    int pageSize = 20,
  }) async {
    final data = await api.get(
      '/api/v1/search',
      query: {'keyword': keyword, 'current': current, 'pageSize': pageSize},
    );
    return MoviePage.fromJson(_map(data));
  }

  Future<List<CategoryNode>> nav() async {
    final data = await api.get('/api/v1/nav');
    final items = (_map(data)['items'] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map((e) => CategoryNode.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<MoviePage> category(
    int pid, {
    int cid = 0,
    int current = 1,
    int pageSize = 30,
    String sort = 'update_stamp',
  }) async {
    final data = await api.get(
      '/api/v1/classify/search',
      query: {
        'pid': pid,
        if (cid > 0) 'cid': cid,
        'current': current,
        'pageSize': pageSize,
        'sort': sort,
      },
    );
    return MoviePage.fromJson(_map(data));
  }

  Future<List<WatchHistory>> history({int limit = 30}) async {
    final data = await api.get(
      '/api/v1/me/history',
      query: {'limit': limit},
      auth: true,
    );
    final items = (_map(data)['items'] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map((e) => WatchHistory.fromJson(e.cast<String, dynamic>()))
        .where((e) => e.movie != null)
        .toList();
  }

  Future<List<FavoriteItem>> favorites({int limit = 200}) async {
    final data = await api.get(
      '/api/v1/me/favorites',
      query: {'limit': limit},
      auth: true,
    );
    final items = (_map(data)['items'] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map((e) => FavoriteItem.fromJson(e.cast<String, dynamic>()))
        .where((e) => e.movie != null)
        .toList();
  }

  Future<void> saveHistory({
    required int mid,
    String sourceId = '',
    int episode = 0,
    String episodeName = '',
    required int position,
    required int duration,
    bool deleted = false,
  }) async {
    await api.post(
      '/api/v1/me/history',
      auth: true,
      body: {
        'items': [
          {
            'mid': mid,
            'sourceId': sourceId,
            'episode': episode,
            'episodeName': episodeName,
            'position': position,
            'duration': duration,
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
            'deleted': deleted,
          }
        ]
      },
    );
  }

  Future<void> setFavorite(int mid, {required bool favorite}) async {
    await api.post(
      '/api/v1/me/favorites',
      auth: true,
      body: {
        'items': [
          {
            'mid': mid,
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
            'deleted': !favorite,
          }
        ]
      },
    );
  }
}

Map<String, dynamic> _map(dynamic data) =>
    (data as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
