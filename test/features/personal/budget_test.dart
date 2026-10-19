import 'package:budget_app/features/personal/budget.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fixed savings subtracts every category in integer cents', () {
    final budget = PersonalBudget(
      earnings: 100000,
      savingsValue: 10000,
      items: [
        BudgetItem('Rent', 40000, ItemKind.bill),
        BudgetItem('Music', 1000, ItemKind.subscription),
        BudgetItem('Shoes', 5000, ItemKind.oneTime),
      ],
      transactions: [Spending('Lunch', 1234, DateTime(2026, 10, 19))],
    );
    expect(budget.spendingMoney, 42766);
  });
  test('percent savings uses money after bills and rounds half up', () {
    final budget = PersonalBudget(
      earnings: 100005,
      savingsMode: SavingsMode.percent,
      savingsValue: 10,
      items: [BudgetItem('Rent', 40000, ItemKind.bill)],
    );
    expect(budget.savings, 6001);
    expect(budget.spendingMoney, 54004);
  });
  test('overspending stays negative', () {
    expect(
      PersonalBudget(earnings: 100, savingsValue: 200).spendingMoney,
      -100,
    );
  });
  test('percent savings is zero when bills exceed income', () {
    expect(
      PersonalBudget(
        earnings: 100,
        savingsMode: SavingsMode.percent,
        savingsValue: 50,
        items: [BudgetItem('Rent', 200, ItemKind.bill)],
      ).savings,
      0,
    );
  });
  test('period order and conversion including negative rounding', () {
    expect(BudgetPeriod.values, [
      BudgetPeriod.week,
      BudgetPeriod.month,
      BudgetPeriod.year,
    ]);
    expect(BudgetPeriod.month.convert(5200), 5200);
    expect(BudgetPeriod.week.convert(5200), 1200);
    expect(BudgetPeriod.year.convert(5200), 62400);
    expect(BudgetPeriod.week.convert(-101), -23);
  });
  test('money parsing is exact and rejects excess precision', () {
    expect(parseCents('12.34'), 1234);
    expect(parseCents('0.01'), 1);
    expect(parseCents('1.234'), isNull);
    expect(parseCents('-1'), isNull);
  });
}
