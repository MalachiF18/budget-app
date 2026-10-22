import '../group/group_models.dart';

/// One explicit set of expenses producing the screenshot's pairwise balances.
/// The screenshot does not specify its underlying shares, so this fixture makes
/// them inspectable rather than inventing a hidden redistribution algorithm.
GroupLedger exampleLedger(DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  return GroupLedger(
    const [
      GroupMember('you', 'You'),
      GroupMember('malachi', 'Malachi'),
      GroupMember('davante', 'Davante'),
      GroupMember('jordan', 'Jordan'),
    ],
    [
      GroupExpense(
        id: 'lunch',
        description: 'Lunch for Davante',
        amount: 3000,
        date: today,
        paidBy: 'you',
        createdBy: 'you',
        shares: const {'davante': 3000},
      ),
      GroupExpense(
        id: 'groceries',
        description: 'Groceries with Malachi',
        amount: 4800,
        date: DateTime(today.year, today.month, today.day - 10),
        paidBy: 'malachi',
        createdBy: 'malachi',
        shares: const {'you': 1200, 'malachi': 3600},
      ),
      GroupExpense(
        id: 'dinner',
        description: 'Dinner with Jordan',
        amount: 5400,
        date: DateTime(today.year, today.month, today.day - 40),
        paidBy: 'jordan',
        createdBy: 'jordan',
        shares: const {'you': 1800, 'jordan': 3600},
      ),
    ],
    const [],
  );
}
