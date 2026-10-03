import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/search_history_service.dart';
import '../services/search_suggestion_service.dart';

/// A search field that shows what the user searched before, plus suggestions
/// scoped to the surface it sits on.
///
/// Drop this in place of a bare `TextField` to get, for free:
///
/// * per-surface history, so "Romans" typed on the Bible screen does not
///   clutter the Members screen, while still being *offered* there labelled
///   "Bible"
/// * curated popular terms per surface, so a cold screen still teaches what
///   can be searched
/// * live candidates supplied by the caller (member names, product titles),
///   which is what makes suggestions feel specific rather than canned
///
/// History is recorded on submit only, never per keystroke, so a half-typed
/// word never pollutes the list.
class SmartSearchField extends StatefulWidget {
  final SearchScope scope;
  final String hint;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final TextEditingController? controller;
  final List<String> entities;
  final bool autofocus;
  final String? emptyLabel;

  const SmartSearchField({
    super.key,
    required this.scope,
    this.hint = 'Search',
    this.onSubmitted,
    this.onChanged,
    this.controller,
    this.entities = const [],
    this.autofocus = false,
    this.emptyLabel,
  });

  @override
  State<SmartSearchField> createState() => _SmartSearchFieldState();
}

class _SmartSearchFieldState extends State<SmartSearchField> {
  late final TextEditingController _controller;
  bool _ownsController = false;
  SearchHistoryService? _history;
  SearchSuggestionService? _suggestions;
  List<SearchSuggestion> _rows = const [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? TextEditingController();
    _controller.addListener(_onTextChanged);
    _bootstrap();
  }

  @override
  void didUpdateWidget(SmartSearchField old) {
    super.didUpdateWidget(old);
    if (old.scope != widget.scope || old.entities != widget.entities) {
      _recompute();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onTextChanged);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      _history = SearchHistoryService(prefs);
      _suggestions = SearchSuggestionService(_history!);
      _recompute();
    } catch (e) {
      debugPrint('[SmartSearchField] history unavailable: $e');
    }
  }

  void _onTextChanged() {
    // Debounced so a fast typist does not re-rank the whole history per letter.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 140), _recompute);
    widget.onChanged?.call(_controller.text);
  }

  void _recompute() {
    final service = _suggestions;
    if (service == null) return;
    final query = _controller.text;
    setState(() {
      _rows = query.trim().isEmpty
          ? service.idleSuggestions(
              widget.scope,
              entities: widget.entities,
            )
          : service.querySuggestions(
              widget.scope,
              query,
              entities: widget.entities,
            );
    });
  }

  Future<void> _submit(String raw) async {
    final query = SearchHistoryService.normalizeQuery(raw);
    if (query.isEmpty) return;
    await _history?.record(widget.scope.id, query);
    if (mounted) _recompute();
    widget.onSubmitted?.call(query);
  }

  void _useSuggestion(SearchSuggestion s) {
    _controller.text = s.text;
    _controller.selection =
        TextSelection.collapsed(offset: s.text.length);
    _submit(s.text);
  }

  Future<void> _removeSuggestion(SearchSuggestion s) async {
    await _history?.remove(widget.scope.id, s.text);
    if (mounted) _recompute();
  }

  Future<void> _clearHistory() async {
    await _history?.clear(scope: widget.scope.id);
    if (mounted) _recompute();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          autofocus: widget.autofocus,
          textInputAction: TextInputAction.search,
          onSubmitted: _submit,
          decoration: InputDecoration(
            hintText: widget.hint,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _controller.clear();
                      _recompute();
                    },
                  ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            filled: true,
          ),
        ),
        if (_rows.isNotEmpty) ...[
          const SizedBox(height: 10),
          _SuggestionGroupHeader(
            label: _controller.text.trim().isEmpty
                ? (widget.emptyLabel ??
                    'RECENT ON ${widget.scope.label.toUpperCase()}')
                : 'SUGGESTIONS',
            onClear: _controller.text.trim().isEmpty ? _clearHistory : null,
          ),
          const SizedBox(height: 4),
          ..._rows.map(
            (s) => _SuggestionTile(
              suggestion: s,
              onTap: () => _useSuggestion(s),
              onRemove: s.kind == SearchSuggestionKind.history ||
                      s.kind == SearchSuggestionKind.crossHistory
                  ? () => _removeSuggestion(s)
                  : null,
              theme: theme,
            ),
          ),
        ],
      ],
    );
  }
}

class _SuggestionGroupHeader extends StatelessWidget {
  final String label;
  final VoidCallback? onClear;

  const _SuggestionGroupHeader({required this.label, this.onClear});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (onClear != null)
          GestureDetector(
            onTap: onClear,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                'CLEAR',
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  final SearchSuggestion suggestion;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  final ThemeData theme;

  const _SuggestionTile({
    required this.suggestion,
    required this.onTap,
    required this.theme,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(suggestion.icon, size: 18),
      title: Text(
        suggestion.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: suggestion.contextLabel == null
          ? null
          : Text(
              suggestion.contextLabel!,
              style: theme.textTheme.labelSmall,
            ),
      trailing: onRemove == null
          ? const Icon(Icons.north_west, size: 16)
          : IconButton(
              icon: const Icon(Icons.close, size: 16),
              onPressed: onRemove,
              tooltip: 'Remove',
            ),
      onTap: onTap,
    );
  }
}