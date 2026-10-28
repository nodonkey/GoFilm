import 'package:flutter_test/flutter_test.dart';
import 'package:gofilm/models/models.dart';

void main() {
  test('IndexBundle parses sections and drops empty ones', () {
    final bundle = IndexBundle.fromJson({
      'banners': [
        {'mid': 1, 'name': 'Banner', 'picture': 'http://img/1.jpg'},
      ],
      'category': {
        'children': [
          {'id': 1, 'pid': 0, 'name': '电影', 'children': <dynamic>[]},
        ],
      },
      'content': [
        {
          'nav': {'id': 1, 'pid': 0, 'name': '电影'},
          'movies': [
            {'id': 10, 'name': 'Movie', 'year': '2026', 'remarks': '正片'},
          ],
        },
        {
          'nav': {'id': 2, 'pid': 0, 'name': '空分类'},
          'movies': <dynamic>[],
        },
      ],
    });

    expect(bundle.banners, hasLength(1));
    expect(bundle.categories, hasLength(1));
    expect(bundle.sections, hasLength(1));
    expect(bundle.sections.first.movies.single.id, 10);
    expect(bundle.sections.first.movies.single.meta, '2026 · 正片');
  });

  test('PlayBundle reads signed proxy flag and sources', () {
    final bundle = PlayBundle.fromJson({
      'proxy': true,
      'current': {'episode': '第1集', 'link': 'http://server/api/v1/proxy/m3u8?url=x'},
      'currentPlayFrom': 'source-a',
      'currentEpisode': 0,
      'detail': {
        'mid': 7,
        'name': 'Movie',
        'list': [
          {
            'id': 'source-a',
            'name': '线路一',
            'linkList': [
              {'episode': '第1集', 'link': 'http://server/api/v1/proxy/m3u8?url=x'},
            ],
          },
        ],
      },
      'relate': <dynamic>[],
    });

    expect(bundle.proxy, isTrue);
    expect(bundle.detail.mid, 7);
    expect(bundle.detail.sources.single.items.single.episode, '第1集');
    expect(bundle.currentEpisode, 0);
  });

  test('WatchHistory parses movie and progress', () {
    final item = WatchHistory.fromJson({
      'mid': 3,
      'sourceId': 'a',
      'episode': 2,
      'episodeName': '第3集',
      'position': 120,
      'duration': 600,
      'progress': 0.2,
      'updatedAt': 1700000000000,
      'movie': {'id': 3, 'name': 'Movie'},
    });

    expect(item.movie?.name, 'Movie');
    expect(item.progress, 0.2);
    expect(item.position, 120);
  });
}
