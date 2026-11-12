import 'package:flutter/material.dart';

/// 値の確定を、Enterまたはフォーカス喪失で行うテキスト入力(3.6-5)。
/// 入力エラーは赤枠とメッセージで示し、確定せず元の値に戻す。
class CommitTextField extends StatefulWidget {
  const CommitTextField({
    super.key,
    required this.value,
    required this.onCommit,
    this.validator,
    this.enabled = true,
    this.label,
    this.multiline = false,
    this.focusNode,
    this.keyboardType,
  });

  final String value;

  /// 値が変わっていて、検証を通ったときだけ呼ばれる。
  final void Function(String value) onCommit;

  /// エラー文言を返す。問題なければnull。
  final String? Function(String value)? validator;
  final bool enabled;
  final String? label;
  final bool multiline;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;

  @override
  State<CommitTextField> createState() => _CommitTextFieldState();
}

class _CommitTextFieldState extends State<CommitTextField> {
  late final TextEditingController _c = TextEditingController(text: widget.value);
  late final FocusNode _focus = widget.focusNode ?? FocusNode();
  String? _error;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant CommitTextField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _c.text != widget.value) {
      _c.text = widget.value;
      _error = null;
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    if (widget.focusNode == null) _focus.dispose();
    _c.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (!_focus.hasFocus) _commit(revertOnError: true);
  }

  void _commit({bool revertOnError = false}) {
    final v = _c.text;
    if (v == widget.value) {
      setState(() => _error = null);
      return;
    }
    final err = widget.validator?.call(v);
    if (err != null) {
      setState(() => _error = err);
      if (revertOnError) {
        _c.text = widget.value;
        // 元の値に戻した後もメッセージは残さない。
        Future.microtask(() {
          if (mounted) setState(() => _error = null);
        });
      }
      return;
    }
    setState(() => _error = null);
    widget.onCommit(v);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      focusNode: _focus,
      enabled: widget.enabled,
      maxLines: widget.multiline ? 4 : 1,
      minLines: widget.multiline ? 2 : 1,
      keyboardType: widget.keyboardType,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: widget.label,
        isDense: true,
        errorText: _error,
        border: const OutlineInputBorder(),
        enabledBorder: _error != null
            ? const OutlineInputBorder(borderSide: BorderSide(color: Colors.red))
            : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      onSubmitted: widget.multiline ? null : (_) => _commit(),
      onEditingComplete: widget.multiline ? null : () => _commit(),
    );
  }
}
