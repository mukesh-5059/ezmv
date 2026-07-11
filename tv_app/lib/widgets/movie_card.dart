import 'package:flutter/material.dart';
import '../models/movie.model.dart';
import '../theme.dart';

class MovieCard extends StatefulWidget {
  final Movie movie;
  final VoidCallback onTap;
  final ValueChanged<bool>? onFocusChanged;

  const MovieCard({
    Key? key,
    required this.movie,
    required this.onTap,
    this.onFocusChanged,
  }) : super(key: key);

  @override
  State<MovieCard> createState() => _MovieCardState();
}

class _MovieCardState extends State<MovieCard> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focused) {
        setState(() {
          _isFocused = focused;
        });
        if (widget.onFocusChanged != null) {
          widget.onFocusChanged!(focused);
        }
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isFocused ? 1.06 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeInOut,
          child: Container(
            width: 130,
            margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            decoration: TVTheme.focusDecoration(_isFocused),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: Image.network(
                  widget.movie.posterUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: TVTheme.surface,
                      child: Center(
                        child: Text(
                          widget.movie.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
