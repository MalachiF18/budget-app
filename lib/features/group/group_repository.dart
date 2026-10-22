import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'group_models.dart';

abstract class GroupRepository {
  String get userId;
  Future<List<SpendingGroup>> groups();
  Future<String> create(String name);
  Future<String?> join(String code);
  Future<GroupLedger> load(String groupId);
  Stream<void> changes(String groupId);
  Future<void> save(String groupId, GroupExpense expense);
  Future<void> delete(GroupExpense expense);
  Future<String> upload(String groupId, Uint8List bytes);
  Future<void> removeReceipt(String path);
  Future<Uint8List> receipt(String path);
}

class SupabaseGroupRepository implements GroupRepository {
  SupabaseGroupRepository(this.client);
  final SupabaseClient client;
  @override
  String get userId => client.auth.currentUser!.id;
  @override
  Future<List<SpendingGroup>> groups() async =>
      (await client
              .from('groups')
              .select('id,name,sync_code')
              .order('created_at'))
          .map(
            (r) => SpendingGroup(
              r['id'] as String,
              r['name'] as String,
              r['sync_code'] as String,
            ),
          )
          .toList();
  @override
  Future<String> create(String name) async {
    final rows = await client.rpc('create_group', params: {'p_name': name});
    return rows[0]['group_id'] as String;
  }

  @override
  Future<String?> join(String code) async =>
      await client.rpc('join_group', params: {'p_code': code}) as String?;
  @override
  Future<GroupLedger> load(String groupId) async {
    final members = await client
        .from('group_members')
        .select('user_id,profiles!group_members_user_id_fkey(display_name)')
        .eq('group_id', groupId);
    final expenses = await client
        .from('expenses')
        .select('*,expense_shares(user_id,share_cents)')
        .eq('group_id', groupId)
        .order('occurred_on', ascending: false);
    final payments = await client
        .from('payments')
        .select()
        .eq('group_id', groupId);
    return GroupLedger(
      members
          .map(
            (r) => GroupMember(
              r['user_id'] as String,
              (r['profiles'] as Map)['display_name'] as String,
            ),
          )
          .toList(),
      expenses
          .map(
            (r) => GroupExpense(
              id: r['id'] as String,
              description: r['description'] as String,
              amount: r['amount_cents'] as int,
              date: DateTime.parse(r['occurred_on'] as String),
              paidBy: r['paid_by'] as String,
              createdBy: r['created_by'] as String,
              receiptPath: r['receipt_path'] as String?,
              shares: {
                for (final s in r['expense_shares'] as List)
                  s['user_id'] as String: s['share_cents'] as int,
              },
            ),
          )
          .toList(),
      payments
          .map(
            (r) => GroupPayment(
              r['from_user'] as String,
              r['to_user'] as String,
              r['amount_cents'] as int,
              DateTime.parse(r['occurred_on'] as String),
            ),
          )
          .toList(),
    );
  }

  @override
  Stream<void> changes(String groupId) {
    late StreamController<void> controller;
    RealtimeChannel? channel;
    controller = StreamController<void>(
      onListen: () {
        channel = client.channel(
          'group:$groupId:${DateTime.now().microsecondsSinceEpoch}',
        );
        for (final table in ['expenses', 'payments']) {
          channel!.onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: table,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'group_id',
              value: groupId,
            ),
            callback: (_) => controller.add(null),
          );
          channel!.onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: table,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'group_id',
              value: groupId,
            ),
            callback: (_) => controller.add(null),
          );
          // DELETE carries only the primary key; it cannot use a group filter.
          channel!.onPostgresChanges(
            event: PostgresChangeEvent.delete,
            schema: 'public',
            table: table,
            callback: (_) => controller.add(null),
          );
        }
        channel!.subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed)
            controller.add(null);
          if (error != null) controller.addError(error);
        });
      },
      onCancel: () async {
        if (channel != null) await client.removeChannel(channel!);
      },
    );
    return controller.stream;
  }

  @override
  Future<void> save(String groupId, GroupExpense expense) async {
    if (expense.createdBy != userId)
      throw StateError('Only the creator can edit this expense.');
    await client.rpc(
      expense.id.isEmpty ? 'add_expense' : 'update_expense',
      params: {
        if (expense.id.isEmpty)
          'p_group_id': groupId
        else
          'p_expense_id': expense.id,
        'p_description': expense.description,
        'p_amount_cents': expense.amount,
        'p_occurred_on': dateOnly(expense.date),
        'p_paid_by': expense.paidBy,
        'p_receipt_path': expense.receiptPath,
        'p_shares': expense.shares.entries
            .map((e) => {'user_id': e.key, 'share_cents': e.value})
            .toList(),
      },
    );
  }

  @override
  Future<void> delete(GroupExpense expense) async {
    if (expense.createdBy != userId)
      throw StateError('Only the creator can delete this expense.');
    final path = await client.rpc(
      'delete_expense',
      params: {'p_expense_id': expense.id},
    );
    // A storage cleanup failure must not make a committed deletion look failed.
    if (path is String) {
      try {
        await removeReceipt(path);
      } catch (_) {}
    }
  }

  @override
  Future<String> upload(String groupId, Uint8List bytes) async {
    if (bytes.length > 5242880)
      throw ArgumentError('Choose a photo under 5 MiB.');
    String ext;
    if (bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255) {
      ext = 'jpeg';
    } else if (bytes.length >= 8 &&
        bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78 &&
        bytes[3] == 71) {
      ext = 'png';
    } else if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      ext = 'webp';
    } else {
      throw ArgumentError('Choose a JPEG, PNG or WebP photo.');
    }
    final random = Random.secure();
    final b = List.generate(16, (_) => random.nextInt(256));
    b[6] = (b[6] & 15) | 64;
    b[8] = (b[8] & 63) | 128;
    final h = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    final path =
        '$groupId/${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}.$ext';
    await client.storage
        .from('receipts')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: 'image/$ext'),
        );
    return path;
  }

  @override
  Future<void> removeReceipt(String path) async {
    await client.storage.from('receipts').remove([path]);
  }

  @override
  Future<Uint8List> receipt(String path) =>
      client.storage.from('receipts').download(path);
}
