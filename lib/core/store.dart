// Port of PortfolioProvider.tsx + RateHistoryProvider.tsx.

import 'dart:async';

import 'package:flutter/foundation.dart' hide Category;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'logic/rate_history.dart';
import 'models.dart';
import 'services/prices.dart';
import 'ui/toast.dart';

const _txPageSize = 200;
const _fallbackUsdRate = 60000.0;

class PortfolioStore extends ChangeNotifier {
  User? user;
  bool isLoadingAuth = false;

  List<Category> categories = const [];
  List<Asset> assets = const [];
  List<Transaction> _transactions = const [];
  List<Wallet> wallets = const [];
  List<CurrencyRate> currencyRates = const [];
  List<Person> persons = const [];
  List<DailyPrice> dailyPrices = const [];
  List<Goal> goals = const [];
  List<PriceSourceSetting> priceSourceSettings = const [];
  List<PriceSourceRecord> priceSources = const [];
  List<CategorySpendingCap> spendingCaps = const [];
  List<Check> checks = const [];
  List<Subscription> activeSubscriptions = const [];
  List<LoanInstallment> upcomingDeadlines = const [];
  bool isLoadingData = false;
  bool dataFetchError = false;
  bool transactionsFullyLoaded = true;

  String currencyMode = 'TOMAN';

  int _fetchSeq = 0;
  List<RateHistoryRow> _savedHistory = const [];
  RateHistories? _histories;
  String? _seededFor;
  StreamSubscription<AuthState>? _authSub;

  List<Transaction> get transactions => _transactions;
  set transactions(List<Transaction> v) {
    _transactions = List.unmodifiable(v);
    _histories = null;
  }

  List<PriceSource> get priceSourceCatalog => recordsToCatalog(priceSources);

  double get usdRate {
    final stored = _storedUsd;
    return stored > 0 ? stored : _fallbackUsdRate;
  }

  bool get usdRateIsSet => _storedUsd > 0;

  double get _storedUsd {
    for (final r in currencyRates) {
      if (r.currency == 'USD') return r.tomanPerUnit;
    }
    return 0;
  }

  RateHistories get rateHistories => _histories ??= buildRateHistories(
        transactions: _transactions,
        dailyPrices: dailyPrices,
        currencyRates: currencyRates,
        wallets: wallets,
        savedHistory: _savedHistory,
      );

  void _invalidateHistories() => _histories = null;

  void init() {
    final client = Supabase.instance.client;
    user = client.auth.currentUser;
    _authSub = client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedOut) {
        _setUser(null);
        return;
      }
      final next = state.session?.user;
      if (next != null && next.id != user?.id) _setUser(next);
    });
    if (user != null) unawaited(refresh());
  }

  void _setUser(User? next) {
    final changed = next?.id != user?.id;
    user = next;
    if (!changed) return;
    if (next != null) {
      unawaited(refresh());
    } else {
      _clear();
    }
    notifyListeners();
  }

  void _clear() {
    categories = const [];
    assets = const [];
    transactions = const [];
    wallets = const [];
    currencyRates = const [];
    persons = const [];
    dailyPrices = const [];
    goals = const [];
    priceSourceSettings = const [];
    priceSources = const [];
    spendingCaps = const [];
    checks = const [];
    activeSubscriptions = const [];
    upcomingDeadlines = const [];
    _savedHistory = const [];
    _seededFor = null;
    dataFetchError = false;
    transactionsFullyLoaded = true;
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> logout() async {
    isLoadingAuth = true;
    notifyListeners();
    await Supabase.instance.client.auth.signOut();
    isLoadingAuth = false;
    _setUser(null);
    notifyListeners();
  }

  void toggleCurrency() {
    currencyMode = currencyMode == 'USD' ? 'TOMAN' : 'USD';
    notifyListeners();
  }

  /// Mutators used by screens after a successful write (optimistic local state).
  void update(void Function(PortfolioStore s) fn) {
    fn(this);
    _invalidateHistories();
    notifyListeners();
  }

  Future<void> refresh() => _refreshInternal(false);
  Future<void> refreshAll() => _refreshInternal(true);

  Future<void> _refreshInternal(bool includeExternal) async {
    final u = user;
    if (u == null) return;
    final seq = ++_fetchSeq;
    isLoadingData = true;
    dataFetchError = false;
    notifyListeners();
    final c = Supabase.instance.client;
    try {
      final results = await Future.wait<dynamic>([
        c.from('categories').select().order('order_index', ascending: true, nullsFirst: false).order('created_at', ascending: true),
        c.from('assets').select().order('order_index', ascending: true, nullsFirst: false).order('created_at', ascending: true),
        c
            .from('transactions')
            .select()
            .order('created_at', ascending: false)
            .order('id', ascending: false)
            .range(0, _txPageSize - 1)
            .count(CountOption.exact),
        c.from('wallets').select().isFilter('archived_at', null).order('order_index', ascending: true, nullsFirst: false).order('created_at', ascending: true),
        c.from('currency_rates').select(),
        c.from('persons').select().order('order_index', ascending: true, nullsFirst: false).order('created_at', ascending: true),
        c.from('daily_prices').select().order('date_string', ascending: false),
        c.from('goals').select().order('created_at', ascending: true),
        c.from('price_source_settings').select(),
        c.from('price_sources').select().order('is_builtin', ascending: false).order('slug', ascending: true),
        c.from('category_spending_caps').select(),
        c.from('checks').select().isFilter('deleted_at', null).order('due_date_string', ascending: true),
        c.from('subscriptions').select().isFilter('deleted_at', null).eq('status', 'active').order('next_due_date_string', ascending: true),
        c.from('loan_installments').select().eq('is_paid', false).order('due_date_string', ascending: true).limit(120),
      ]);
      if (seq != _fetchSeq) return;

      List<Json> rows(int i) => (results[i] as List).cast<Json>();
      final nextCategories = rows(0).map(Category.fromJson).toList();
      var nextAssets = rows(1).map(Asset.fromJson).toList();
      final txResp = results[2] as PostgrestResponse;
      final nextTransactions = (txResp.data as List).cast<Json>().map(Transaction.fromJson).toList();
      final txTotal = txResp.count;
      final nextWallets = rows(3).map(Wallet.fromJson).toList();
      var nextRates = rows(4).map(CurrencyRate.fromJson).toList();
      final nextPersons = rows(5).map(Person.fromJson).toList();
      var nextDaily = rows(6).map(DailyPrice.fromJson).toList();
      final nextGoals = rows(7).map(Goal.fromJson).toList();
      var nextPss = rows(8).map(PriceSourceSetting.fromJson).toList();
      var nextPs = rows(9).map(PriceSourceRecord.fromJson).toList();
      final nextCaps = rows(10).map(CategorySpendingCap.fromJson).toList();
      final nextChecks = rows(11).map(Check.fromJson).toList();
      final nextSubs = rows(12).map(Subscription.fromJson).toList();
      final installments = rows(13).map(LoanInstallment.fromJson).toList();

      var nextUpcoming = <LoanInstallment>[];
      if (installments.isNotEmpty) {
        final loanIds = installments.map((i) => i.loanId).toSet().toList();
        final loansData = await c.from('loans').select('id,title,currency').inFilter('id', loanIds);
        if (seq != _fetchSeq) return;
        final loanMap = {for (final l in (loansData as List).cast<Json>()) l['id'] as String: l};
        nextUpcoming = installments
            .map((i) => i.withLoan(loanMap[i.loanId]?['title'] as String?, loanMap[i.loanId]?['currency'] as String?))
            .toList();
      }

      if (nextPs.isEmpty) {
        final seeded = await ensureDefaultPriceSources(u.id);
        if (seeded.isNotEmpty) {
          nextPs = seeded;
          final fresh = await c.from('price_source_settings').select();
          nextPss = (fresh as List).cast<Json>().map(PriceSourceSetting.fromJson).toList();
        }
      }

      final catalog = recordsToCatalog(nextPs);
      final configs = buildConversionConfigMap(nextPss);

      if (includeExternal) {
        try {
          final providerSlugs = <String>{kUsdRateSourceSlug, ...nextAssets.map((a) => a.priceSourceId).whereType<String>()}
              .where((s) => s.isNotEmpty)
              .toList();
          if (providerSlugs.isNotEmpty) {
            final quotesRaw = await fetchProviderQuotes(providerSlugs, catalogToApiSources(catalog));
            ProviderQuote? usdQuote;
            for (final q in quotesRaw) {
              if (q.slug == kUsdRateSourceSlug) usdQuote = q;
            }
            double storedUsd() {
              for (final r in nextRates) {
                if (r.currency == 'USD') return r.tomanPerUnit;
              }
              return 0;
            }

            final effectiveUsd = usdQuote != null && usdQuote.priceToman > 0 ? usdQuote.priceToman : storedUsd();
            if (usdQuote != null && usdQuote.priceToman > 0) {
              final fresh = await persistCurrencyRate(u.id, 'USD', usdQuote.priceToman);
              nextRates = mergeCurrencyRates(nextRates, fresh);
            }
            if (effectiveUsd > 0) {
              final quotes = applyConversionRatesToQuotes(
                mergeGlobalUsdDollarQuotes(quotesRaw, nextAssets, effectiveUsd),
                configs,
                effectiveUsd,
              );
              final persisted = await persistProviderQuotes(
                userId: u.id,
                assets: nextAssets,
                dailyPrices: nextDaily,
                usdRate: effectiveUsd,
                quotes: quotes,
              );
              nextAssets = mergeById(nextAssets, persisted.assets, (a) => a.id);
              nextDaily = mergeDailyPrices(nextDaily, persisted.dailyPrices);
            }
          }
        } catch (e) {
          debugPrint('external price sync failed $e');
        }
      }

      categories = nextCategories;
      assets = nextAssets;
      transactions = nextTransactions;
      wallets = nextWallets;
      currencyRates = nextRates;
      persons = nextPersons;
      dailyPrices = nextDaily;
      goals = nextGoals;
      priceSourceSettings = nextPss;
      priceSources = nextPs;
      spendingCaps = nextCaps;
      checks = nextChecks;
      activeSubscriptions = nextSubs;
      upcomingDeadlines = nextUpcoming;

      final needsMore = txTotal > _txPageSize;
      transactionsFullyLoaded = !needsMore;
      isLoadingData = false;
      notifyListeners();
      unawaited(_loadSavedHistory(u.id));

      if (needsMore) {
        unawaited(() async {
          var offset = _txPageSize;
          var merged = [...nextTransactions];
          while (offset < txTotal) {
            List page;
            try {
              page = await c
                  .from('transactions')
                  .select()
                  .order('created_at', ascending: false)
                  .order('id', ascending: false)
                  .range(offset, offset + _txPageSize - 1);
            } catch (_) {
              break;
            }
            if (page.isEmpty) break;
            final seen = merged.map((t) => t.id).toSet();
            merged = [
              ...merged,
              ...page.cast<Json>().map(Transaction.fromJson).where((t) => !seen.contains(t.id)),
            ];
            offset += _txPageSize;
            if (seq == _fetchSeq) {
              transactions = merged;
              notifyListeners();
            }
            if (page.length < _txPageSize) break;
          }
          if (seq == _fetchSeq) {
            transactionsFullyLoaded = true;
            notifyListeners();
            _maybeSeedHistory(u.id);
          }
        }());
      } else {
        _maybeSeedHistory(u.id);
      }
    } catch (e) {
      if (seq != _fetchSeq) return;
      debugPrint('Error fetching data: $e');
      dataFetchError = true;
      isLoadingData = false;
      notifyListeners();
      Toast.error('خطا در دریافت اطلاعات از سرور.');
    } finally {
      if (seq == _fetchSeq && isLoadingData) {
        isLoadingData = false;
        notifyListeners();
      }
    }
  }

  Future<void> _loadSavedHistory(String userId) async {
    try {
      final data = await Supabase.instance.client
          .from('currency_rate_history')
          .select('currency, date_string, toman_per_unit, source')
          .eq('user_id', userId)
          .neq('source', 'derived');
      _savedHistory = (data as List).cast<Json>().map(RateHistoryRow.fromJson).toList();
      _invalidateHistories();
      notifyListeners();
    } catch (_) {}
  }

  void _maybeSeedHistory(String userId) {
    if (_transactions.isEmpty || _seededFor == userId) return;
    _seededFor = userId;
    unawaited(seedDerivedRateHistory(userId, derivedHistoryRows(rateHistories)));
  }
}
