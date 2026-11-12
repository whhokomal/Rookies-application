import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:rookies_jeans/constants/app_ui.dart';
import 'package:rookies_jeans/constants/shopify_constants.dart';
import 'package:rookies_jeans/models/collection_model.dart';
import 'package:rookies_jeans/models/product_model.dart';
import 'package:rookies_jeans/screens/products/products.dart';
import 'package:rookies_jeans/screens/products/product_detail_page.dart';
import 'package:rookies_jeans/screens/search/search_results_page.dart';
import 'package:rookies_jeans/services/search_history_service.dart';
import 'package:rookies_jeans/services/shopify_storefront_service.dart';
import 'package:rookies_jeans/widgets/price_text.dart';

/// The bottom-nav "Search" tab: a lightweight live-search landing page,
/// separate from ProductsPage (which is collection browsing only). Typing
/// shows an infinitely scrolling list; pressing enter/search opens SearchResultsPage
/// for the full paginated, sortable, filterable grid.
class SearchTabPage extends StatefulWidget {
  const SearchTabPage({super.key});

  @override
  State<SearchTabPage> createState() => _SearchTabPageState();
}

class _SearchTabPageState extends State<SearchTabPage> {
  static const int _kMinLiveSearchLength = 2;
  static const int _kResultCount = 20;

  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;

  String _activeQuery = '';
  List<ShopifyProduct> _products = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasNextPage = false;
  String? _endCursor;
  String? _error;

  /// Shown before anything is typed, like the website's search drawer.
  List<({String title, String handle})> _popularLinks = const [];
  List<ShopifyProduct> _trending = const [];

  /// The empty box's "Search for J|" placeholder, typed out a letter at a
  /// time through [ShopifyConstants.searchPlaceholderPhrases].
  final ValueNotifier<String> _typedPhrase = ValueNotifier('');
  Timer? _typingTimer;
  int _phraseIndex = 0;
  int _typedLength = 0;
  bool _deleting = false;
  int _pauseTicks = 0;

  void _startTyping() {
    _typingTimer = Timer.periodic(const Duration(milliseconds: 110), (_) {
      final phrases = ShopifyConstants.searchPlaceholderPhrases;
      if (phrases.isEmpty) return;
      if (_pauseTicks > 0) {
        _pauseTicks--;
        return;
      }
      final phrase = phrases[_phraseIndex % phrases.length];
      if (!_deleting) {
        _typedLength++;
        if (_typedLength >= phrase.length) {
          _typedLength = phrase.length;
          _deleting = true;
          _pauseTicks = 12; // Hold the full word a moment.
        }
      } else {
        _typedLength--;
        if (_typedLength <= 0) {
          _typedLength = 0;
          _deleting = false;
          _phraseIndex++;
          _pauseTicks = 3;
        }
      }
      _typedPhrase.value = phrase.substring(0, _typedLength);
    });
  }

  @override
  void initState() {
    super.initState();
    SearchHistoryService.instance.load();
    _loadDiscover();
    _startTyping();
    _searchFocusNode.addListener(() {
      if (_searchFocusNode.hasFocus) {
        ShopifyStorefrontService.instance.warmStyleIndex();
      }
    });
    // Keeps fetching the next page as the user nears the bottom, so the list
    // grows until every matching product has been shown.
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 300 &&
          !_isLoading &&
          !_isLoadingMore &&
          _hasNextPage) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _typingTimer?.cancel();
    _typedPhrase.dispose();
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadDiscover() async {
    final service = ShopifyStorefrontService.instance;
    final results = await Future.wait([
      service.getSearchPopularLinks(),
      service.getProductsByHandles(ShopifyConstants.searchTrendingHandles),
    ]);
    if (!mounted) return;
    setState(() {
      _popularLinks = results[0] as List<({String title, String handle})>;
      _trending = results[1] as List<ShopifyProduct>;
    });
  }

  void _openCollection(String title, String handle) {
    FocusScope.of(context).unfocus();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductsPage(
          collection: ShopifyCollection(
            id: handle,
            title: title,
            handle: handle,
            label: title.toUpperCase(),
          ),
        ),
      ),
    );
  }

  void _onSearchInputChanged(String value) {
    setState(() {});
    _searchDebounce?.cancel();

    final trimmed = value.trim();
    if (trimmed.length < _kMinLiveSearchLength) {
      _searchDebounce = Timer(const Duration(milliseconds: 250), () {
        if (!mounted || _searchCtrl.text.trim() != trimmed) return;
        if (_activeQuery.isEmpty) return;
        setState(() {
          _activeQuery = '';
          _products = [];
          _isLoading = false;
          _error = null;
        });
      });
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 380), () {
      if (!mounted || _searchCtrl.text.trim() != trimmed) return;
      _fetchSuggestions(trimmed);
    });
  }

  Future<void> _fetchSuggestions(String query) async {
    setState(() {
      _activeQuery = query;
      _isLoading = true;
      _isLoadingMore = false;
      _hasNextPage = false;
      _endCursor = null;
      _error = null;
    });

    try {
      final response = await ShopifyStorefrontService.instance
          .searchProductsPaginated(
            query,
            first: _kResultCount,
            sortKey: 'RELEVANCE',
          );
      if (!mounted || _searchCtrl.text.trim() != query) return;
      setState(() {
        _products = response.products;
        _hasNextPage = response.hasNextPage;
        _endCursor = response.endCursor;
        _isLoading = false;
      });
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    } catch (e) {
      if (!mounted || _searchCtrl.text.trim() != query) return;
      setState(() {
        _error = 'Failed to load results.';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasNextPage) return;
    final query = _activeQuery;
    setState(() => _isLoadingMore = true);

    try {
      final response = await ShopifyStorefrontService.instance
          .searchProductsPaginated(
            query,
            first: _kResultCount,
            after: _endCursor,
            sortKey: 'RELEVANCE',
          );
      // Drop the page if the user changed the query while it was in flight.
      if (!mounted || _activeQuery != query) return;
      setState(() {
        _products.addAll(response.products);
        _hasNextPage = response.hasNextPage;
        _endCursor = response.endCursor;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted || _activeQuery != query) return;
      setState(() => _isLoadingMore = false);
    }
  }

  void _resetSearchState() {
    _searchDebounce?.cancel();
    _searchCtrl.clear();
    if (!mounted) return;
    setState(() {
      _activeQuery = '';
      _products = [];
      _isLoading = false;
      _isLoadingMore = false;
      _hasNextPage = false;
      _endCursor = null;
      _error = null;
    });
  }

  void _clearSearchField() {
    _resetSearchState();
    _searchFocusNode.requestFocus();
  }

  // Pressing enter/search on the keyboard opens a fresh results page for the
  // query instead of just updating the live list in place.
  void _openSearchResultsPage(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    _searchDebounce?.cancel();
    SearchHistoryService.instance.add(trimmed);
    FocusScope.of(context).unfocus();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SearchResultsPage(
          initialQuery: trimmed,
          // This tab's state persists across bottom-nav navigation, so the
          // results page's back-to-dashboard action reaches back in to
          // clear it — otherwise the old query/results would still be
          // sitting here next time the user opens search.
          onBackToDashboard: _resetSearchState,
        ),
      ),
    );
  }

  void _goBack() {
    // This tab is the root of its own bottom-nav branch with nothing
    // beneath it to pop to, so a plain Navigator.pop here would leave a
    // blank screen — fall back to the dashboard tab instead.
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeService.instance,
      builder: (context, _) => Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Column(
            children: [
              _topBar(),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  static const double _kSide = 20;

  /// Big "SEARCH" heading with a close button, a rule, then the search
  /// box, like the website's search drawer.
  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_kSide, 12, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'SEARCH',
                  style: TextStyle(
                    fontFamily: AppFonts.heading,
                    fontSize: 36,
                    height: 1.1,
                    color: AppColors.primary,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded, size: 24),
                color: AppColors.primary,
                onPressed: _goBack,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: _kSide - 8),
            child: Divider(height: 1, thickness: 1, color: AppColors.border),
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.only(right: _kSide - 8),
            child: _searchField(),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _searchField() {
    return Container(
      height: 54,
      padding: const EdgeInsets.only(left: 18, right: 6),
      color: AppColors.fieldFill,
      child: ValueListenableBuilder<String>(
        valueListenable: _typedPhrase,
        builder: (context, typed, _) => TextField(
          controller: _searchCtrl,
          focusNode: _searchFocusNode,
          textInputAction: TextInputAction.search,
          textAlignVertical: TextAlignVertical.center,
          onSubmitted: _openSearchResultsPage,
          onChanged: _onSearchInputChanged,
          style: TextStyle(
            fontFamily: AppFonts.body,
            fontSize: 14,
            color: AppColors.primary,
          ),
          decoration: InputDecoration(
            hintText: 'Search for $typed|',
            hintStyle: TextStyle(
              fontFamily: AppFonts.body,
              fontSize: 15,
              color: AppColors.primary,
            ),
            border: InputBorder.none,
            isDense: true,
            suffixIcon: _searchCtrl.text.isNotEmpty
                ? IconButton(
                    tooltip: 'Clear',
                    icon: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: AppColors.primary,
                    ),
                    onPressed: _clearSearchField,
                  )
                : IconButton(
                    tooltip: 'Search',
                    icon: Icon(
                      Icons.search_rounded,
                      size: 22,
                      color: AppColors.primary,
                    ),
                    onPressed: () => _openSearchResultsPage(_searchCtrl.text),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_activeQuery.trim().isEmpty) {
      return AnimatedBuilder(
        animation: SearchHistoryService.instance,
        builder: (context, _) {
          final hasRecent = SearchHistoryService.instance.queries.isNotEmpty;
          if (!hasRecent && _popularLinks.isEmpty && _trending.isEmpty) {
            return _idleState();
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 90),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              if (_popularLinks.isNotEmpty) ..._popularLinksSection(),
              if (hasRecent) ..._recentSearches(),
              if (_trending.isNotEmpty) ..._trendingSection(),
            ],
          );
        },
      );
    }
    if (_isLoading) return _shimmerList();
    if (_error != null) return _errorState();
    if (_products.isEmpty) return _emptyState();
    return _resultsList();
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(_kSide, 18, _kSide, 10),
    child: Text(
      text,
      style: TextStyle(
        fontFamily: AppFonts.body,
        fontSize: 16,
        fontWeight: FontWeight.w900,
        fontStyle: FontStyle.italic,
        letterSpacing: 0.6,
        color: AppColors.primary,
      ),
    ),
  );

  /// "POPULAR LINKS": the website search's collection shortcuts.
  List<Widget> _popularLinksSection() => [
    _sectionLabel('POPULAR LINKS'),
    for (final link in _popularLinks)
      InkWell(
        onTap: () => _openCollection(link.title, link.handle),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _kSide, vertical: 8),
          child: Text(
            link.title.toUpperCase(),
            style: TextStyle(
              fontFamily: AppFonts.accent,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ),
      ),
    const SizedBox(height: 6),
  ];

  /// "TRENDING PRODUCTS": the website search's hand-picked products
  /// ([ShopifyConstants.searchTrendingHandles]).
  List<Widget> _trendingSection() => [
    _sectionLabel('TRENDING PRODUCT'),
    for (final product in _trending) _resultTile(product),
  ];

  List<Widget> _recentSearches() {
    final queries = SearchHistoryService.instance.queries;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 4),
        child: Row(
          children: [
            Text(
              'RECENT SEARCHES',
              style: TextStyle(
                fontFamily: AppFonts.body,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
                color: AppColors.secondaryText,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: SearchHistoryService.instance.clear,
              child: Text(
                'CLEAR ALL',
                style: TextStyle(
                  fontFamily: AppFonts.body,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
      for (final query in queries) ...[
        ListTile(
          dense: true,
          contentPadding: const EdgeInsets.only(left: 16, right: 4),
          leading: Icon(
            Icons.history_rounded,
            size: 20,
            color: AppColors.secondaryText,
          ),
          title: Text(
            query,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppFonts.body,
              fontSize: 14,
              color: AppColors.primary,
            ),
          ),
          trailing: IconButton(
            tooltip: 'Remove',
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: AppColors.secondaryText,
            ),
            onPressed: () => SearchHistoryService.instance.remove(query),
          ),
          onTap: () {
            _searchCtrl.text = query;
            _searchCtrl.selection = TextSelection.collapsed(
              offset: query.length,
            );
            _openSearchResultsPage(query);
          },
        ),
        Divider(height: 1, indent: 16, color: AppColors.border),
      ],
    ];
  }

  Widget _idleState() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.search_rounded, size: 52, color: AppColors.hint),
        const SizedBox(height: 14),
        Text(
          'SEARCH PRODUCTS',
          style: TextStyle(
            fontFamily: AppFonts.body,
            fontSize: 13,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
            color: AppColors.primary.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Start typing to find what you\'re looking for',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppFonts.body,
            fontSize: 12,
            color: AppColors.secondaryText,
          ),
        ),
      ],
    ),
  );

  Widget _emptyState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded, size: 48, color: AppColors.hint),
          const SizedBox(height: 16),
          Text(
            'No results for "$_activeQuery"',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppFonts.body,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Try a different search term.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppFonts.body,
              fontSize: 12,
              color: AppColors.secondaryText,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _errorState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded, size: 52, color: AppColors.hint),
          const SizedBox(height: 14),
          Text(
            _error ?? 'Something went wrong.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppFonts.body,
              fontSize: 13,
              color: AppColors.secondaryText,
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => _fetchSuggestions(_activeQuery),
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text(
              'RETRY',
              style: TextStyle(
                fontFamily: AppFonts.body,
                fontWeight: FontWeight.w900,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.primary),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _shimmerList() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: 8,
      itemBuilder: (_, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Container(height: 60, color: AppColors.fieldFill),
      ),
    );
  }

  Widget _resultsList() {
    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 90),
      itemCount: _products.length + (_isLoadingMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox.shrink(),
      itemBuilder: (_, i) {
        if (i >= _products.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return _resultTile(_products[i]);
      },
    );
  }

  /// A product row like the website's search: photo, name, price and the
  /// tax note.
  Widget _resultTile(ShopifyProduct product) {
    return InkWell(
      onTap: () {
        // Opening a live result counts as using this search.
        if (_activeQuery.isNotEmpty) {
          SearchHistoryService.instance.add(_activeQuery);
        }
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProductDetailPage(
              handle: product.handle,
              title: product.title,
              heroImageUrl: product.primaryImageUrl,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _kSide, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: product.primaryImageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: product.primaryImageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, _) =>
                          Container(color: AppColors.fieldFill),
                      errorWidget: (_, _, _) =>
                          Container(color: AppColors.fieldFill),
                    )
                  : Container(color: AppColors.fieldFill),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppFonts.body,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _priceBlock(product),
                  const SizedBox(height: 6),
                  Text(
                    'Taxes included Shipping calculated at checkout',
                    style: TextStyle(
                      fontFamily: AppFonts.body,
                      fontSize: 13,
                      color: AppColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _priceBlock(ShopifyProduct product) {
    if (!product.isOnSale) {
      return PriceText(
        product.formattedPrice,
        currencyCode: product.currencyCode,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.primary,
        amountFontFamily: AppFonts.body,
      );
    }
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        PriceText(
          product.formattedPrice,
          currencyCode: product.currencyCode,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
          amountFontFamily: AppFonts.body,
        ),
        PriceText(
          product.formattedCompareAtPrice,
          currencyCode: product.currencyCode,
          fontSize: 14,
          color: AppColors.secondaryText,
          amountFontFamily: AppFonts.body,
          decoration: TextDecoration.lineThrough,
        ),
      ],
    );
  }
}
