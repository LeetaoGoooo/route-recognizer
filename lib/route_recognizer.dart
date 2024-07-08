library route_recognizer;

import 'dart:core';

import 'package:route_recognizer/route-recongnizer/normalizer.dart';

enum CHARS {
  any(-1),
  star(42),
  slash(47),
  colon(58);

  final int value;
  const CHARS(this.value);
}

String getParam(Map<String, dynamic>? params, String key) {
  if (params == null) {
    throw ArgumentError(
        'You must pass a Map as the first argument to `generate`.');
  }

  if (!params.containsKey(key)) {
    throw ArgumentError('You must provide param `$key` to `generate`.');
  }

  final value = params[key];
  final str = value is String ? value : value.toString();

  if (str.isEmpty) {
    throw ArgumentError('You must provide a non-empty param `$key`.');
  }

  return str;
}

enum SegmentType {
  staticType(0),
  dynamicType(1),
  starType(2),
  epsilonType(4);

  final int value;
  const SegmentType(this.value);
}

class SegmentFlags {
  static int staticType = SegmentType.staticType.value;
  static int dynamicType = SegmentType.dynamicType.value;
  static int starType = SegmentType.starType.value;
  static int epsilonType = SegmentType.epsilonType.value;
  static int named = dynamicType | starType;
  static int decoded = dynamicType;
  static int counted = staticType | dynamicType | starType;
}

typedef Counted = int;

final RegExp escapeRegex = RegExp(r'(\/|\.|\*|\+|\?|\||\(|\)|\[|\]|\{|\}|\\)');

typedef StateFunction<THandler> = State<THandler> Function(
    Segment segment, State<THandler> currentState);

class EachChar<THandler> {
  final List<StateFunction<THandler>> functions =
      List.filled(5, (_, state) => state);

  EachChar() {
    functions[SegmentType.starType.value] = (segment, currentState) {
      State<THandler> state = currentState;
      String value = segment.value;
      for (int i = 0; i < value.length; i++) {
        int ch = value.codeUnitAt(i);
        state = state.put(ch, false, false);
      }
      return state;
    };

    functions[SegmentType.dynamicType.value] = (_, currentState) {
      return currentState.put(CHARS.slash.value, true, true);
    };

    functions[SegmentType.starType.value] = (_, currentState) {
      return currentState.put(CHARS.any.value, false, true);
    };

    functions[SegmentType.epsilonType.value] = (_, currentState) {
      return currentState;
    };
  }

  State<THandler> call(Segment segment, State<THandler> currentState) {
    return functions[segment.type.value](segment, currentState);
  }
}

class Segment {
  final SegmentType type;
  final String value;

  Segment(this.type, this.value);
}

// A State has a character specification and (`charSpec`) and a list of possible
// subsequent states (`nextStates`).
//
// If a State is an accepting state, it will also have several additional
// properties:
//
// * `regex`: A regular expression that is used to extract parameters from paths
//   that reached this accepting state.
// * `handlers`: Information on how to convert the list of captures into calls
//   to registered handlers with the specified parameters
// * `types`: How many static, dynamic or star segments in this route. Used to
//   decide which route to use if multiple registered routes match a path.
//
// Currently, State is implemented naively by looping over `nextStates` and
// comparing a character specification against a character. A more efficient
// implementation would use a hash of keys pointing at one or more next states.
class State<THandler> implements CharSpec {
  List<State<THandler>> states;
  int id;
  @override
  bool negate;
  @override
  int char;
  dynamic nextStates; // Can be int, List<int>, or null
  String pattern;
  RegExp? _regex;
  List<Handler<THandler>>? handlers;
  List<int>? types;

  State(this.states, this.id, this.char, this.negate, bool repeat)
      : nextStates = repeat ? id : null,
        pattern = "";

  RegExp regex() {
    return _regex ??= RegExp(pattern);
  }

  State<THandler>? get(int char, bool negate) {
    if (nextStates == null) return null;
    if (nextStates is List<int>) {
      for (int i = 0; i < (nextStates as List<int>).length; i++) {
        final child = states[(nextStates as List<int>)[i]];
        if (isEqualCharSpec(child, char, negate)) {
          return child;
        }
      }
    } else if (nextStates is int) {
      final child = states[nextStates as int];
      if (isEqualCharSpec(child, char, negate)) {
        return child;
      }
    }
    return null;
  }

  State<THandler> put(int char, bool negate, bool repeat) {
    State<THandler>? state = get(char, negate);
    if (state != null) {
      return state;
    }

    state = State(states, states.length, char, negate, repeat);
    states.add(state);

    if (nextStates == null) {
      nextStates = state.id;
    } else if (nextStates is List<int>) {
      (nextStates as List<int>).add(state.id);
    } else {
      nextStates = [nextStates as int, state.id];
    }

    return state;
  }

  List<State<THandler>> match(int ch) {
    if (nextStates == null) return [];

    List<State<THandler>> returned = [];
    if (nextStates is List<int>) {
      for (int i = 0; i < (nextStates as List<int>).length; i++) {
        final child = states[(nextStates as List<int>)[i]];
        if (isMatch(child, ch)) {
          returned.add(child);
        }
      }
    } else if (nextStates is int) {
      final child = states[nextStates as int];
      if (isMatch(child, ch)) {
        returned.add(child);
      }
    }
    return returned;
  }
}

abstract class CharSpec {
  bool get negate;
  int get char;
}

bool isEqualCharSpec(CharSpec spec, int char, bool negate) {
  return spec.char == char && spec.negate == negate;
}

bool isMatch(CharSpec spec, int char) {
  return spec.negate
      ? spec.char != char && spec.char != CHARS.any.value
      : spec.char == char || spec.char == CHARS.any.value;
}

class Handler<THandler> {
  final THandler handler;
  final List<String> names;
  final List<bool> shouldDecodes;

  Handler({
    required this.handler,
    required this.names,
    required this.shouldDecodes,
  });
}

typedef RegexFunction = String Function(Segment segment);

class RegexFunctions {
  final List<RegexFunction> functions = List.filled(5, (_) => '');

  RegexFunctions() {
    functions[SegmentType.starType.value] = (segment) {
      return segment.value.replaceAllMapped(
        escapeRegex,
        (match) => '\\${match.group(0)}',
      );
    };

    functions[SegmentType.dynamicType.value] = (_) => '([^/]+)';

    functions[SegmentType.starType.value] = (_) => '(.+)';

    functions[SegmentType.epsilonType.value] = (_) => '';
  }

  String call(SegmentType type, Segment segment) {
    return functions[type.value](segment);
  }
}

typedef GenerateFunction = String Function(
    Segment segment, Map<String, dynamic>? params, bool shouldEncode);

class GenerateFunctions {
  final List<GenerateFunction> functions = List.filled(5, (_, __, ___) => '');

  GenerateFunctions() {
    functions[SegmentType.starType.value] = (segment, _, __) {
      return segment.value;
    };

    functions[SegmentType.dynamicType.value] = (segment, params, shouldEncode) {
      final value = getParam(params, segment.value);
      if (shouldEncode) {
        return encodePathSegment(value);
      } else {
        return value;
      }
    };

    functions[SegmentType.starType.value] = (segment, params, _) {
      return getParam(params, segment.value);
    };

    functions[SegmentType.epsilonType.value] = (_, __, ___) {
      return '';
    };
  }

  String call(SegmentType type, Segment segment,
      [Map<String, dynamic>? params, bool shouldEncode = false]) {
    return functions[type.value](segment, params, shouldEncode);
  }
}

// This is a somewhat naive strategy, but should work in a lot of cases
// A better strategy would properly resolve /posts/:id/new and /posts/edit/:id.
//
// This strategy generally prefers more static and less dynamic matching.
// Specifically, it
//
//  * prefers fewer stars to more, then
//  * prefers using stars for less of the match to more, then
//  * prefers fewer dynamic segments to more, then
//  * prefers more static segments to more
List<State<THandler>> sortSolutions<THandler>(List<State<THandler>> states) {
  return states
    ..sort((a, b) {
      final aTypes = a.types ?? [0, 0, 0];
      final bTypes = b.types ?? [0, 0, 0];

      final aStatics = aTypes[0];
      final aDynamics = aTypes[1];
      final aStars = aTypes[2];

      final bStatics = bTypes[0];
      final bDynamics = bTypes[1];
      final bStars = bTypes[2];

      if (aStars != bStars) {
        return aStars.compareTo(bStars);
      }

      if (aStars != 0) {
        if (aStatics != bStatics) {
          return bStatics.compareTo(aStatics);
        }
        if (aDynamics != bDynamics) {
          return bDynamics.compareTo(aDynamics);
        }
      }

      if (aDynamics != bDynamics) {
        return aDynamics.compareTo(bDynamics);
      }
      if (aStatics != bStatics) {
        return bStatics.compareTo(aStatics);
      }

      return 0;
    });
}

List<State<THandler>> recognizeChar<THandler>(
  List<State<THandler>> states,
  int ch,
) {
  List<State<THandler>> nextStates = [];

  for (int i = 0; i < states.length; i++) {
    final state = states[i];
    nextStates.addAll(state.match(ch));
  }

  return nextStates;
}
