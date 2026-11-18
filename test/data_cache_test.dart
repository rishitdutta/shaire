import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shaire/services/custom_friend_balance_service.dart';
import 'package:shaire/services/data_cache.dart';

void main() {
  group('DataCache (stale-while-revalidate layer)', () {
    setUp(() => DataCache.instance.reset());

    test('serves a fresh key without hitting the network', () async {
      var calls = 0;
      Future<void> fetch() async => calls++;

      expect(await DataCache.instance.fetch('k', fetch: fetch), isTrue);
      expect(await DataCache.instance.fetch('k', fetch: fetch), isFalse);
      expect(calls, 1);
    });

    test('force: true bypasses freshness', () async {
      var calls = 0;
      Future<void> fetch() async => calls++;

      await DataCache.instance.fetch('k', fetch: fetch);
      expect(await DataCache.instance.fetch('k', fetch: fetch, force: true),
          isTrue);
      expect(calls, 2);
    });

    test('coalesces concurrent fetches of the same key into one', () async {
      var calls = 0;
      Future<void> slowFetch() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        calls++;
      }

      final results = await Future.wait([
        DataCache.instance.fetch('k', fetch: slowFetch),
        DataCache.instance.fetch('k', fetch: slowFetch),
      ]);

      expect(calls, 1);
      expect(results, [true, false]);
    });

    test('invalidate() makes the next fetch hit the network', () async {
      var calls = 0;
      Future<void> fetch() async => calls++;

      await DataCache.instance.fetch('k', fetch: fetch);
      DataCache.instance.invalidate('k');
      await DataCache.instance.fetch('k', fetch: fetch);
      expect(calls, 2);
    });

    test('failed fetch does not mark the key fresh', () async {
      Future<void> boom() async => throw StateError('network down');
      await expectLater(
        DataCache.instance.fetch('k', fetch: boom),
        throwsStateError,
      );

      var ok = 0;
      expect(
          await DataCache.instance.fetch('k', fetch: () async => ok++), isTrue);
      expect(ok, 1);
    });

    test('expired entries refetch; different keys are independent', () async {
      var calls = 0;
      Future<void> fetch() async => calls++;

      await DataCache.instance.fetch('a', fetch: fetch, ttl: Duration.zero);
      expect(
          await DataCache.instance.fetch('a', fetch: fetch, ttl: Duration.zero),
          isTrue);
      expect(await DataCache.instance.fetch('b', fetch: fetch), isTrue);
      expect(calls, 3);
    });
  });

  group('Custom friend settle-up (recordSettlement)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('adjusts balance and writes a visible history entry', () async {
      await CustomFriendBalanceService.recordSettlement(
        customFriendId: 'cf1',
        friendName: 'Alex',
        amount: 50,
        youPaid: true,
      );

      // youPaid=true moves the net toward "they owe you" (+50 from zero).
      final balance = await CustomFriendBalanceService.getBalance('cf1');
      expect(balance['youAreOwed'], 50.0);
      expect(balance['youOwe'], 0.0);

      final history = await CustomFriendBalanceService.getExpenses('cf1');
      expect(history, hasLength(1));
      expect(history.first['is_settlement'], true);
      expect(history.first['total_amount'], 50.0);
      expect(history.first['paid_by_you'], true);
      expect(history.first['description'], contains('Settlement'));
    });

    test('theyPaid direction reduces what you are owed', () async {
      final balance = await CustomFriendBalanceService.getBalance('cf1');
      expect(balance['youAreOwed'], 0.0);

      await CustomFriendBalanceService.recordSettlement(
        customFriendId: 'cf1',
        friendName: 'Alex',
        amount: 30,
        youPaid: false,
        note: 'cash at dinner',
      );

      final after = await CustomFriendBalanceService.getBalance('cf1');
      expect(after['youOwe'], 30.0);

      final history = await CustomFriendBalanceService.getExpenses('cf1');
      expect(history.first['description'], contains('cash at dinner'));
    });
  });
}
