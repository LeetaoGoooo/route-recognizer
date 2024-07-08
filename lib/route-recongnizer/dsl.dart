import 'dart:collection';

abstract class Delegate<THandler> {
  void contextEntered(THandler context, MatchDSL<THandler> route);
  THandler? willAddRoute(THandler? context, THandler route);
}

class Route<THandler> {
  final String path;
  final THandler handler;
  final List<String>? queryParams;

  Route(this.path, this.handler, {this.queryParams});
}

abstract class RouteRecognizer<THandler> {
  Delegate<THandler>? delegate;
  void add(List<Route<THandler>> routes);
}

typedef MatchCallback<THandler> = void Function(MatchDSL<THandler> match);

abstract class MatchDSL<THandler> {
  ToDSL call(String path);
  void callWithCallback(String path, MatchCallback callback);
}

abstract class ToDSL<THandler> {
  void to(THandler name, [MatchCallback<THandler>? callback]);
}

class Target<THandler> implements ToDSL<THandler> {
  final String path;
  final Matcher<THandler> matcher;
  final Delegate<THandler>? delegate;

  Target(this.path, this.matcher, this.delegate);

  @override
  void to(THandler target, [MatchCallback<THandler>? callback]) {
    if (delegate?.willAddRoute != null) {
      target = delegate!.willAddRoute(matcher.target, target) ?? target;
    }

    matcher.add(path, target);

    if (callback != null) {
      if (callback is Function() &&
          callback.toString().split('=>')[0].trim() == '()') {
        throw ArgumentError(
            'You must have an argument in the function passed to `to`');
      }
      matcher.addChild(path, target, callback, delegate);
    }
  }
}

class Matcher<THandler> {
  final Map<String, THandler?> routes = HashMap();
  final Map<String, Matcher<THandler>> children = HashMap();
  THandler? target;

  Matcher([this.target]);

  void add(String path, THandler target) {
    routes[path] = target;
  }

  void addChild(String path, THandler target, MatchCallback<THandler> callback,
      Delegate<THandler>? delegate) {
    final matcher = Matcher<THandler>(target);
    children[path] = matcher;

    final match = generateMatch(path, matcher, delegate);

    delegate?.contextEntered(target, match);

    callback(match);
  }
}

MatchDSL<THandler> generateMatch<THandler>(
  String startingPath,
  Matcher<THandler> matcher,
  Delegate<THandler>? delegate,
) {
  return _Match<THandler>(startingPath, matcher, delegate);
}

class _Match<THandler> implements MatchDSL<THandler> {
  final String startingPath;
  final Matcher<THandler> matcher;
  final Delegate<THandler>? delegate;

  _Match(this.startingPath, this.matcher, this.delegate);

  @override
  ToDSL<THandler> call(String path) {
    return _matchImpl(path);
  }

  @override
  void callWithCallback(String path, MatchCallback<THandler> callback) {
    _matchImpl(path, callback);
  }

  dynamic _matchImpl(String path, [MatchCallback<THandler>? callback]) {
    final fullPath = startingPath + path;
    if (callback != null) {
      callback(generateMatch(fullPath, matcher, delegate));
      return null;
    } else {
      return Target<THandler>(fullPath, matcher, delegate);
    }
  }
}

void addRoute<THandler>(
    List<Route<THandler>> routeArray, String path, THandler handler) {
  int len = routeArray.fold(0, (sum, route) => sum + route.path.length);
  path = path.substring(len);
  final route = Route(path, handler);
  routeArray.add(route);
}

void eachRoute<TThis, THandler>(
    List<Route<THandler>> baseRoute,
    Matcher<THandler> matcher,
    void Function(TThis, List<Route<THandler>>) callback,
    TThis binding) {
  final routes = matcher.routes;
  final paths = routes.keys.toList();
  for (var path in paths) {
    final routeArray = List<Route<THandler>>.from(baseRoute);
    addRoute(routeArray, path, routes[path]);
    final nested = matcher.children[path];
    if (nested != null) {
      eachRoute(routeArray, nested, callback, binding);
    } else {
      callback(binding, routeArray);
    }
  }
}

void map<TRouteRecognizer extends RouteRecognizer<THandler>, THandler>(
    TRouteRecognizer routeRecognizer, MatchCallback<THandler> callback,
    [void Function(TRouteRecognizer, List<Route<THandler>>)?
        addRouteCallback]) {
  final matcher = Matcher<THandler>();

  callback(generateMatch('', matcher, routeRecognizer.delegate));

  eachRoute<TRouteRecognizer, THandler>([], matcher, (binding, routes) {
    if (addRouteCallback != null) {
      addRouteCallback(binding, routes);
    } else {
      binding.add(routes);
    }
  }, routeRecognizer);
}
