// Domain models — mirror `src/shared/types/domain.ts` in the web app.
// Rows are read straight from Supabase (PostgREST JSON). Numeric columns can
// come back as num or String, so every read goes through [numOrNull].

typedef Json = Map<String, dynamic>;

double? numOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

/// JS `Number(x) || 0`.
double numOr0(dynamic v) {
  final n = numOrNull(v);
  if (n == null || n.isNaN || n.isInfinite) return 0;
  return n;
}

int intOr(dynamic v, int fallback) {
  final n = numOrNull(v);
  if (n == null || n.isNaN) return fallback;
  return n.toInt();
}

String? strOrNull(dynamic v) => v?.toString();

List<int> intList(dynamic v) {
  if (v is List) return v.map((e) => intOr(e, 0)).toList();
  return const [];
}

typedef CurrencyMode = String; // 'TOMAN' | 'USD'
const kCurrencies = ['IRT', 'USD', 'TRY', 'EUR'];
const kRateCurrencies = ['USD', 'TRY', 'EUR'];

class Category {
  final String id;
  final String userId;
  final String name;
  final String color;
  final String kind; // asset | income | expense
  final String? parentId;
  final int? orderIndex;
  final String? createdAt;

  Category({
    required this.id,
    required this.userId,
    required this.name,
    required this.color,
    required this.kind,
    this.parentId,
    this.orderIndex,
    this.createdAt,
  });

  factory Category.fromJson(Json j) => Category(
        id: j['id'] as String,
        userId: (j['user_id'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        color: (j['color'] ?? '#94a3b8') as String,
        kind: (j['kind'] ?? 'expense') as String,
        parentId: j['parent_id'] as String?,
        orderIndex: j['order_index'] == null ? null : intOr(j['order_index'], 0),
        createdAt: j['created_at'] as String?,
      );

  Category copyWith({String? name, String? color, String? parentId, bool clearParent = false, int? orderIndex}) =>
      Category(
        id: id,
        userId: userId,
        name: name ?? this.name,
        color: color ?? this.color,
        kind: kind,
        parentId: clearParent ? null : (parentId ?? this.parentId),
        orderIndex: orderIndex ?? this.orderIndex,
        createdAt: createdAt,
      );
}

class CategorySpendingCap {
  final String id;
  final String userId;
  final String categoryId;
  final double monthlyLimitToman;
  CategorySpendingCap({required this.id, required this.userId, required this.categoryId, required this.monthlyLimitToman});
  factory CategorySpendingCap.fromJson(Json j) => CategorySpendingCap(
        id: j['id'] as String,
        userId: (j['user_id'] ?? '') as String,
        categoryId: j['category_id'] as String,
        monthlyLimitToman: numOr0(j['monthly_limit_toman']),
      );
}

class Asset {
  final String id;
  final String userId;
  final String? categoryId;
  final String name;
  final String unit;
  final int decimalPlaces;
  final double priceToman;
  final double priceUsd;
  final String? iconUrl;
  final String? priceSourceId;
  final bool includeInProfitLoss;
  final bool? includeInBalance;
  final int? orderIndex;
  final String? createdAt;

  Asset({
    required this.id,
    required this.userId,
    this.categoryId,
    required this.name,
    required this.unit,
    this.decimalPlaces = 4,
    this.priceToman = 0,
    this.priceUsd = 0,
    this.iconUrl,
    this.priceSourceId,
    this.includeInProfitLoss = true,
    this.includeInBalance,
    this.orderIndex,
    this.createdAt,
  });

  factory Asset.fromJson(Json j) => Asset(
        id: j['id'] as String,
        userId: (j['user_id'] ?? '') as String,
        categoryId: j['category_id'] as String?,
        name: (j['name'] ?? '') as String,
        unit: (j['unit'] ?? '') as String,
        decimalPlaces: intOr(j['decimal_places'], 4),
        priceToman: numOr0(j['price_toman']),
        priceUsd: numOr0(j['price_usd']),
        iconUrl: j['icon_url'] as String?,
        priceSourceId: j['price_source_id'] as String?,
        includeInProfitLoss: (j['include_in_profit_loss'] ?? true) as bool,
        includeInBalance: j['include_in_balance'] as bool?,
        orderIndex: j['order_index'] == null ? null : intOr(j['order_index'], 0),
        createdAt: j['created_at'] as String?,
      );

  Asset copyWith({double? priceToman, double? priceUsd, int? orderIndex}) => Asset(
        id: id,
        userId: userId,
        categoryId: categoryId,
        name: name,
        unit: unit,
        decimalPlaces: decimalPlaces,
        priceToman: priceToman ?? this.priceToman,
        priceUsd: priceUsd ?? this.priceUsd,
        iconUrl: iconUrl,
        priceSourceId: priceSourceId,
        includeInProfitLoss: includeInProfitLoss,
        includeInBalance: includeInBalance,
        orderIndex: orderIndex ?? this.orderIndex,
        createdAt: createdAt,
      );

  /// Synthetic asset used for quantity-only replays.
  static Asset blank(String id) => Asset(id: id, userId: '', name: '', unit: '', includeInProfitLoss: false);
}

class Wallet {
  final String id;
  final String userId;
  final String name;
  final String currency;
  final double initialBalance;
  final String? iconUrl;
  final String? archivedAt;
  final String? cardNumber;
  final String? accountNumber;
  final String? iban;
  final String? accountOwnerName;
  final int? orderIndex;
  final String createdAt;

  Wallet({
    required this.id,
    required this.userId,
    required this.name,
    required this.currency,
    this.initialBalance = 0,
    this.iconUrl,
    this.archivedAt,
    this.cardNumber,
    this.accountNumber,
    this.iban,
    this.accountOwnerName,
    this.orderIndex,
    required this.createdAt,
  });

  factory Wallet.fromJson(Json j) => Wallet(
        id: j['id'] as String,
        userId: (j['user_id'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        currency: (j['currency'] ?? 'IRT') as String,
        initialBalance: numOr0(j['initial_balance']),
        iconUrl: j['icon_url'] as String?,
        archivedAt: j['archived_at'] as String?,
        cardNumber: j['card_number'] as String?,
        accountNumber: j['account_number'] as String?,
        iban: j['iban'] as String?,
        accountOwnerName: j['account_owner_name'] as String?,
        orderIndex: j['order_index'] == null ? null : intOr(j['order_index'], 0),
        createdAt: (j['created_at'] ?? '') as String,
      );

  Wallet withOrder(int i) => Wallet(
        id: id,
        userId: userId,
        name: name,
        currency: currency,
        initialBalance: initialBalance,
        iconUrl: iconUrl,
        archivedAt: archivedAt,
        cardNumber: cardNumber,
        accountNumber: accountNumber,
        iban: iban,
        accountOwnerName: accountOwnerName,
        orderIndex: i,
        createdAt: createdAt,
      );
}

class WalletSavingsPot {
  final String id;
  final String userId;
  final String walletId;
  final String name;
  final String color;
  final double? targetAmount;
  final double currentAmount;
  final String? archivedAt;
  final int orderIndex;
  final String createdAt;

  WalletSavingsPot({
    required this.id,
    required this.userId,
    required this.walletId,
    required this.name,
    required this.color,
    this.targetAmount,
    required this.currentAmount,
    this.archivedAt,
    required this.orderIndex,
    required this.createdAt,
  });

  factory WalletSavingsPot.fromJson(Json j) => WalletSavingsPot(
        id: j['id'] as String,
        userId: (j['user_id'] ?? '') as String,
        walletId: j['wallet_id'] as String,
        name: (j['name'] ?? '') as String,
        color: (j['color'] ?? '#a855f7') as String,
        targetAmount: numOrNull(j['target_amount']),
        currentAmount: numOr0(j['current_amount']),
        archivedAt: j['archived_at'] as String?,
        orderIndex: intOr(j['order_index'], 0),
        createdAt: (j['created_at'] ?? '') as String,
      );
}

class RecurringTransaction {
  final String id;
  final String userId;
  final String title;
  final String type; // INCOME | EXPENSE
  final double amountToman;
  final String walletId;
  final String categoryId;
  final int intervalNumber;
  final String intervalPeriod;
  final String nextDueDateString;
  final String? endDateString;
  final bool isActive;
  final String? note;
  final String? deletedAt;
  final String createdAt;

  RecurringTransaction({
    required this.id,
    required this.userId,
    required this.title,
    required this.type,
    required this.amountToman,
    required this.walletId,
    required this.categoryId,
    required this.intervalNumber,
    required this.intervalPeriod,
    required this.nextDueDateString,
    this.endDateString,
    required this.isActive,
    this.note,
    this.deletedAt,
    required this.createdAt,
  });

  factory RecurringTransaction.fromJson(Json j) => RecurringTransaction(
        id: j['id'] as String,
        userId: (j['user_id'] ?? '') as String,
        title: (j['title'] ?? '') as String,
        type: (j['type'] ?? 'EXPENSE') as String,
        amountToman: numOr0(j['amount_toman']),
        walletId: (j['wallet_id'] ?? '') as String,
        categoryId: (j['category_id'] ?? '') as String,
        intervalNumber: intOr(j['interval_number'], 1),
        intervalPeriod: (j['interval_period'] ?? 'month') as String,
        nextDueDateString: (j['next_due_date_string'] ?? '') as String,
        endDateString: j['end_date_string'] as String?,
        isActive: (j['is_active'] ?? true) as bool,
        note: j['note'] as String?,
        deletedAt: j['deleted_at'] as String?,
        createdAt: (j['created_at'] ?? '') as String,
      );
}

class Subscription {
  final String id;
  final String userId;
  final String platform;
  final double amount;
  final String currency;
  final int intervalNumber;
  final String intervalPeriod;
  final String nextDueDateString;
  final String? walletId;
  final String? categoryId;
  final String status; // active | cancelled
  final String? cancelledAt;
  final List<int> reminderDaysBefore;
  final String? note;
  final String? deletedAt;
  final String createdAt;

  Subscription({
    required this.id,
    required this.userId,
    required this.platform,
    required this.amount,
    required this.currency,
    required this.intervalNumber,
    required this.intervalPeriod,
    required this.nextDueDateString,
    this.walletId,
    this.categoryId,
    required this.status,
    this.cancelledAt,
    required this.reminderDaysBefore,
    this.note,
    this.deletedAt,
    required this.createdAt,
  });

  factory Subscription.fromJson(Json j) => Subscription(
        id: j['id'] as String,
        userId: (j['user_id'] ?? '') as String,
        platform: (j['platform'] ?? '') as String,
        amount: numOr0(j['amount']),
        currency: (j['currency'] ?? 'IRT') as String,
        intervalNumber: intOr(j['interval_number'], 1),
        intervalPeriod: (j['interval_period'] ?? 'month') as String,
        nextDueDateString: (j['next_due_date_string'] ?? '') as String,
        walletId: j['wallet_id'] as String?,
        categoryId: j['category_id'] as String?,
        status: (j['status'] ?? 'active') as String,
        cancelledAt: j['cancelled_at'] as String?,
        reminderDaysBefore: intList(j['reminder_days_before']),
        note: j['note'] as String?,
        deletedAt: j['deleted_at'] as String?,
        createdAt: (j['created_at'] ?? '') as String,
      );
}

class ExpensePlanItem {
  final String id;
  final String userId;
  final String monthStartString;
  final String title;
  final double amountToman;
  final String? categoryId;
  final String? note;
  final String sourceType; // manual | installment | recurring | check | subscription
  final String? sourceId;
  final int sortOrder;

  ExpensePlanItem({
    required this.id,
    required this.userId,
    required this.monthStartString,
    required this.title,
    required this.amountToman,
    this.categoryId,
    this.note,
    required this.sourceType,
    this.sourceId,
    required this.sortOrder,
  });

  factory ExpensePlanItem.fromJson(Json j) => ExpensePlanItem(
        id: j['id'] as String,
        userId: (j['user_id'] ?? '') as String,
        monthStartString: (j['month_start_string'] ?? '') as String,
        title: (j['title'] ?? '') as String,
        amountToman: numOr0(j['amount_toman']),
        categoryId: j['category_id'] as String?,
        note: j['note'] as String?,
        sourceType: (j['source_type'] ?? 'manual') as String,
        sourceId: j['source_id'] as String?,
        sortOrder: intOr(j['sort_order'], 0),
      );
}

class Person {
  final String id;
  final String userId;
  final String name;
  final int? orderIndex;
  final String createdAt;
  Person({required this.id, required this.userId, required this.name, this.orderIndex, required this.createdAt});
  factory Person.fromJson(Json j) => Person(
        id: j['id'] as String,
        userId: (j['user_id'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        orderIndex: j['order_index'] == null ? null : intOr(j['order_index'], 0),
        createdAt: (j['created_at'] ?? '') as String,
      );
}

class CurrencyRate {
  final String id;
  final String userId;
  final String currency;
  final double tomanPerUnit;
  final String updatedAt;
  CurrencyRate({required this.id, required this.userId, required this.currency, required this.tomanPerUnit, required this.updatedAt});
  factory CurrencyRate.fromJson(Json j) => CurrencyRate(
        id: (j['id'] ?? '') as String,
        userId: (j['user_id'] ?? '') as String,
        currency: (j['currency'] ?? 'USD') as String,
        tomanPerUnit: numOr0(j['toman_per_unit']),
        updatedAt: (j['updated_at'] ?? '') as String,
      );
}

class PriceSourceSetting {
  final String userId;
  final String slug;
  final double conversionRate;
  final String usdFactor; // none | multiply | divide
  final String updatedAt;
  PriceSourceSetting({required this.userId, required this.slug, required this.conversionRate, required this.usdFactor, required this.updatedAt});
  factory PriceSourceSetting.fromJson(Json j) => PriceSourceSetting(
        userId: (j['user_id'] ?? '') as String,
        slug: j['slug'] as String,
        conversionRate: numOrNull(j['conversion_rate']) ?? double.nan,
        usdFactor: (j['usd_factor'] ?? 'none') as String,
        updatedAt: (j['updated_at'] ?? '') as String,
      );
}

class PriceSourceRecord {
  final String userId;
  final String slug;
  final String provider; // abantether | zarpay
  final String label;
  final String? fetchKey;
  final String? updatesRate;
  final bool deprecated;
  final bool isBuiltin;
  PriceSourceRecord({
    required this.userId,
    required this.slug,
    required this.provider,
    required this.label,
    this.fetchKey,
    this.updatesRate,
    this.deprecated = false,
    this.isBuiltin = false,
  });
  factory PriceSourceRecord.fromJson(Json j) => PriceSourceRecord(
        userId: (j['user_id'] ?? '') as String,
        slug: j['slug'] as String,
        provider: (j['provider'] ?? 'abantether') as String,
        label: (j['label'] ?? '') as String,
        fetchKey: j['fetch_key'] as String?,
        updatesRate: j['updates_rate'] as String?,
        deprecated: (j['deprecated'] ?? false) as bool,
        isBuiltin: (j['is_builtin'] ?? false) as bool,
      );
}

class DailyPrice {
  final String userId;
  final String assetId;
  final String dateString;
  final double priceToman;
  final double priceUsd;
  final String source; // manual | trade | auto
  DailyPrice({
    required this.userId,
    required this.assetId,
    required this.dateString,
    required this.priceToman,
    required this.priceUsd,
    required this.source,
  });
  factory DailyPrice.fromJson(Json j) => DailyPrice(
        userId: (j['user_id'] ?? '') as String,
        assetId: j['asset_id'] as String,
        dateString: (j['date_string'] ?? '') as String,
        priceToman: numOr0(j['price_toman']),
        priceUsd: numOr0(j['price_usd']),
        source: (j['source'] ?? 'manual') as String,
      );
}

class Goal {
  final String id;
  final String userId;
  final String scope; // asset | asset_group
  final String? assetId;
  final String? categoryId;
  final String targetKind; // quantity | allocation_percent
  final double? targetQuantity;
  final double? targetPercent;
  final String? createdAt;
  Goal({
    required this.id,
    required this.userId,
    required this.scope,
    this.assetId,
    this.categoryId,
    required this.targetKind,
    this.targetQuantity,
    this.targetPercent,
    this.createdAt,
  });
  factory Goal.fromJson(Json j) => Goal(
        id: j['id'] as String,
        userId: (j['user_id'] ?? '') as String,
        scope: (j['scope'] ?? 'asset') as String,
        assetId: j['asset_id'] as String?,
        categoryId: j['category_id'] as String?,
        targetKind: (j['target_kind'] ?? 'quantity') as String,
        targetQuantity: numOrNull(j['target_quantity']),
        targetPercent: numOrNull(j['target_percent']),
        createdAt: j['created_at'] as String?,
      );
}

class Transaction {
  final String id;
  final String userId;
  final String type; // BUY | SELL | TRANSFER | INCOME | EXPENSE
  final String dateString;
  final String? note;
  final String createdAt;
  final String? sourceWalletId;
  final String? sourceAssetId;
  final String? sourcePersonId;
  final String? targetWalletId;
  final String? targetAssetId;
  final String? targetPersonId;
  final double? sourceAmount;
  final double? targetAmount;
  final String? categoryId;
  final String? assetId;
  final double? amount;
  final double? priceToman;
  final double? usdRate;
  final double? amountTomanAtTime;
  final double? amountUsdAtTime;
  final String? operationId;

  Transaction({
    required this.id,
    required this.userId,
    required this.type,
    required this.dateString,
    this.note,
    required this.createdAt,
    this.sourceWalletId,
    this.sourceAssetId,
    this.sourcePersonId,
    this.targetWalletId,
    this.targetAssetId,
    this.targetPersonId,
    this.sourceAmount,
    this.targetAmount,
    this.categoryId,
    this.assetId,
    this.amount,
    this.priceToman,
    this.usdRate,
    this.amountTomanAtTime,
    this.amountUsdAtTime,
    this.operationId,
  });

  factory Transaction.fromJson(Json j) => Transaction(
        id: j['id'] as String,
        userId: (j['user_id'] ?? '') as String,
        type: (j['type'] ?? 'EXPENSE') as String,
        dateString: (j['date_string'] ?? '') as String,
        note: j['note'] as String?,
        createdAt: (j['created_at'] ?? '') as String,
        sourceWalletId: j['source_wallet_id'] as String?,
        sourceAssetId: j['source_asset_id'] as String?,
        sourcePersonId: j['source_person_id'] as String?,
        targetWalletId: j['target_wallet_id'] as String?,
        targetAssetId: j['target_asset_id'] as String?,
        targetPersonId: j['target_person_id'] as String?,
        sourceAmount: numOrNull(j['source_amount']),
        targetAmount: numOrNull(j['target_amount']),
        categoryId: j['category_id'] as String?,
        assetId: j['asset_id'] as String?,
        amount: numOrNull(j['amount']),
        priceToman: numOrNull(j['price_toman']),
        usdRate: numOrNull(j['usd_rate']),
        amountTomanAtTime: numOrNull(j['amount_toman_at_time']),
        amountUsdAtTime: numOrNull(j['amount_usd_at_time']),
        operationId: j['operation_id'] as String?,
      );

  Json toJson() => {
        'id': id,
        'user_id': userId,
        'type': type,
        'date_string': dateString,
        'note': note,
        'created_at': createdAt,
        'source_wallet_id': sourceWalletId,
        'source_asset_id': sourceAssetId,
        'source_person_id': sourcePersonId,
        'target_wallet_id': targetWalletId,
        'target_asset_id': targetAssetId,
        'target_person_id': targetPersonId,
        'source_amount': sourceAmount,
        'target_amount': targetAmount,
        'category_id': categoryId,
        'asset_id': assetId,
        'amount': amount,
        'price_toman': priceToman,
        'usd_rate': usdRate,
        'amount_toman_at_time': amountTomanAtTime,
        'amount_usd_at_time': amountUsdAtTime,
        'operation_id': operationId,
      };
}

class Loan {
  final String id;
  final String userId;
  final String title;
  final String type; // expense | loan
  final String? categoryId;
  final String currency;
  final String? assetId;
  final double installmentAmount;
  final double? totalAmount;
  final String loanStartDateString;
  final String firstDueDateString;
  final int repeatCount;
  final int intervalNumber;
  final String intervalPeriod;
  final bool autoIncomeOnCreate;
  final String? autoIncomeWalletId;
  final String? description;
  final List<int> reminderDaysBefore;
  final String? deletedAt;
  final String createdAt;

  Loan({
    required this.id,
    required this.userId,
    required this.title,
    required this.type,
    this.categoryId,
    required this.currency,
    this.assetId,
    required this.installmentAmount,
    this.totalAmount,
    required this.loanStartDateString,
    required this.firstDueDateString,
    required this.repeatCount,
    required this.intervalNumber,
    required this.intervalPeriod,
    required this.autoIncomeOnCreate,
    this.autoIncomeWalletId,
    this.description,
    required this.reminderDaysBefore,
    this.deletedAt,
    required this.createdAt,
  });

  factory Loan.fromJson(Json j) => Loan(
        id: j['id'] as String,
        userId: (j['user_id'] ?? '') as String,
        title: (j['title'] ?? '') as String,
        type: (j['type'] ?? 'loan') as String,
        categoryId: j['category_id'] as String?,
        currency: (j['currency'] ?? 'IRT') as String,
        assetId: j['asset_id'] as String?,
        installmentAmount: numOr0(j['installment_amount']),
        totalAmount: numOrNull(j['total_amount']),
        loanStartDateString: (j['loan_start_date_string'] ?? '') as String,
        firstDueDateString: (j['first_due_date_string'] ?? '') as String,
        repeatCount: intOr(j['repeat_count'], 1),
        intervalNumber: intOr(j['interval_number'], 1),
        intervalPeriod: (j['interval_period'] ?? 'month') as String,
        autoIncomeOnCreate: (j['auto_income_on_create'] ?? false) as bool,
        autoIncomeWalletId: j['auto_income_wallet_id'] as String?,
        description: j['description'] as String?,
        reminderDaysBefore: intList(j['reminder_days_before']),
        deletedAt: j['deleted_at'] as String?,
        createdAt: (j['created_at'] ?? '') as String,
      );
}

class LoanInstallment {
  final String id;
  final String userId;
  final String loanId;
  final String dueDateString;
  final double amount;
  final double paidAmount;
  final int sequenceNo;
  final bool isPaid;
  final String? paidAt;
  final String? paidTransactionId;
  final String? note;
  // Joined in PortfolioStore for upcoming deadlines.
  final String? loanTitle;
  final String? loanCurrency;

  LoanInstallment({
    required this.id,
    required this.userId,
    required this.loanId,
    required this.dueDateString,
    required this.amount,
    required this.paidAmount,
    required this.sequenceNo,
    required this.isPaid,
    this.paidAt,
    this.paidTransactionId,
    this.note,
    this.loanTitle,
    this.loanCurrency,
  });

  factory LoanInstallment.fromJson(Json j) => LoanInstallment(
        id: j['id'] as String,
        userId: (j['user_id'] ?? '') as String,
        loanId: j['loan_id'] as String,
        dueDateString: (j['due_date_string'] ?? '') as String,
        amount: numOr0(j['amount']),
        paidAmount: numOr0(j['paid_amount']),
        sequenceNo: intOr(j['sequence_no'], 0),
        isPaid: (j['is_paid'] ?? false) as bool,
        paidAt: j['paid_at'] as String?,
        paidTransactionId: j['paid_transaction_id'] as String?,
        note: j['note'] as String?,
      );

  LoanInstallment withLoan(String? title, String? currency) => LoanInstallment(
        id: id,
        userId: userId,
        loanId: loanId,
        dueDateString: dueDateString,
        amount: amount,
        paidAmount: paidAmount,
        sequenceNo: sequenceNo,
        isPaid: isPaid,
        paidAt: paidAt,
        paidTransactionId: paidTransactionId,
        note: note,
        loanTitle: title,
        loanCurrency: currency,
      );
}

class Check {
  final String id;
  final String userId;
  final String title;
  final String? bankName;
  final String? checkNumber;
  final double amount;
  final String currency;
  final String dueDateString;
  final String? walletId;
  final String? categoryId;
  final String status; // pending | cleared | bounced | cancelled
  final String? clearedAt;
  final String? paidTransactionId;
  final String? note;
  final String? deletedAt;
  final String createdAt;

  Check({
    required this.id,
    required this.userId,
    required this.title,
    this.bankName,
    this.checkNumber,
    required this.amount,
    required this.currency,
    required this.dueDateString,
    this.walletId,
    this.categoryId,
    required this.status,
    this.clearedAt,
    this.paidTransactionId,
    this.note,
    this.deletedAt,
    required this.createdAt,
  });

  factory Check.fromJson(Json j) => Check(
        id: j['id'] as String,
        userId: (j['user_id'] ?? '') as String,
        title: (j['title'] ?? '') as String,
        bankName: j['bank_name'] as String?,
        checkNumber: j['check_number'] as String?,
        amount: numOr0(j['amount']),
        currency: (j['currency'] ?? 'IRT') as String,
        dueDateString: (j['due_date_string'] ?? '') as String,
        walletId: j['wallet_id'] as String?,
        categoryId: j['category_id'] as String?,
        status: (j['status'] ?? 'pending') as String,
        clearedAt: j['cleared_at'] as String?,
        paidTransactionId: j['paid_transaction_id'] as String?,
        note: j['note'] as String?,
        deletedAt: j['deleted_at'] as String?,
        createdAt: (j['created_at'] ?? '') as String,
      );
}

class AssetStats {
  double totalAmount = 0;
  double totalCostToman = 0;
  double totalCostUsd = 0;
  double avgBuyPriceToman = 0;
  double avgBuyPriceUsd = 0;
  double currentValueToman = 0;
  double currentValueUsd = 0;
  double profitLossToman = 0;
  double profitLossUsd = 0;
  double profitLossPercent = 0;
  double realizedProfitToman = 0;
  double realizedProfitUsd = 0;
  double unrealizedProfitToman = 0;
  double unrealizedProfitUsd = 0;
  double investedToman = 0;
  double investedUsd = 0;
  double proceedsToman = 0;
  double proceedsUsd = 0;
  String? activeSinceDate;
  double currentPriceToman = 0;
  double currentPriceUsd = 0;
  String currentPriceSource = 'none'; // live | trade | none
  String? currentPriceDate;
}
