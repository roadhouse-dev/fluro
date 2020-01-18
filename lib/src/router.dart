/*
 * fluro
 * Created by Yakka
 * https://theyakka.com
 *
 * Copyright (c) 2019 Yakka, LLC. All rights reserved.
 * See LICENSE for distribution and usage details.
 */

import 'dart:async';
import 'dart:io';

import 'package:fluro/fluro.dart';
import 'package:fluro/src/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

class Router {
  static final appRouter = new Router();

  /// The tree structure that stores the defined routes
  final RouteTree _routeTree = new RouteTree();

  /// Generic handler for when a route has not been defined
  Handler notFoundHandler;

  /// Creates a [PageRoute] definition for the passed [RouteHandler]. You can optionally provide a default transition type.
  void define(String routePath,
      {@required Handler handler, TransitionType transitionType}) {
    _routeTree.addRoute(
        new AppRoute(routePath, handler, transitionType: transitionType));
  }

  /// Finds a defined [AppRoute] for the path value. If no [AppRoute] definition was found
  /// then function will return null.
  AppRouteMatch match(String path) {
    return _routeTree.matchRoute(path);
  }

  ///
  bool pop<T>(BuildContext context, [dynamic result]) {
    return Navigator.pop(context, result);
  }

  ///
  void popUntil<T>(BuildContext context, RoutePredicate predicate,
      [dynamic result]) {
    Navigator.popUntil(context, (route) {
      if (predicate(route)) {
        (route.settings.arguments as Map<String, dynamic>)['result'] = result;
        return true;
      } else {
        return false;
      }
    });
  }

  ///
  Future navigateTo(BuildContext context, String path,
      {bool replace = false,
      bool clearStack = false,
      TransitionType transition,
      Duration transitionDuration = const Duration(milliseconds: 250),
      RouteTransitionsBuilder transitionBuilder,
      Object arguments}) async {
    final argumentsMap = {
      'arguments': arguments,
    };
    RouteMatch routeMatch = matchRoute(context, path,
        transitionType: transition,
        transitionsBuilder: transitionBuilder,
        transitionDuration: transitionDuration,
        routeSettings: RouteSettings(name: path, arguments: argumentsMap));
    Route<dynamic> route = routeMatch.route;
    Completer completer = new Completer();
    Future future = completer.future;
    if (routeMatch.matchType == RouteMatchType.nonVisual) {
      completer.complete("Non visual route type.");
    } else {
      if (route == null && notFoundHandler != null) {
        route = _notFoundRoute(context, path);
      }
      if (route != null) {
        if (clearStack) {
          future =
              Navigator.pushAndRemoveUntil(context, route, (check) => false);
        } else {
          future = replace
              ? Navigator.pushReplacement(context, route)
              : Navigator.push(context, route);
        }
        completer.complete();
      } else {
        String error = "No registered route was found to handle '$path'.";
        print(error);
        completer.completeError(RouteNotFoundException(error, path));
      }
    }

    //To work around the popUntil not being able to pass back a value we
    //are using a hack which will utalize the arguments of the route to
    //pass back a result.
    final result = await future;
     final argumentMap = ModalRoute.of(context).settings.arguments as Map;

   if (result != null) {
      return result;
    } else if (argumentMap != null) {
      return argumentMap['result'];
    } else {
      return null;
    }
  }

  ///
  Route<Null> _notFoundRoute(BuildContext context, String path) {
    RouteCreator<Null> creator =
        (RouteSettings routeSettings, Map<String, List<String>> parameters) {
      return new MaterialPageRoute<Null>(
          settings: routeSettings,
          builder: (BuildContext context) {
            return notFoundHandler.handlerFunc(context, parameters,
                (routeSettings.arguments as Map<String, dynamic>)['arguments']);
          });
    };
    return creator(new RouteSettings(name: path), null);
  }

  ///
  RouteMatch matchRoute(BuildContext buildContext, String path,
      {RouteSettings routeSettings,
      TransitionType transitionType,
      Duration transitionDuration = const Duration(milliseconds: 250),
      RouteTransitionsBuilder transitionsBuilder}) {
    RouteSettings settingsToUse = routeSettings;
    if (routeSettings == null) {
      settingsToUse = new RouteSettings(name: path);
    }
    AppRouteMatch match = _routeTree.matchRoute(path);
    AppRoute route = match?.route;
    Handler handler = (route != null ? route.handler : notFoundHandler);
    var transition = transitionType;
    if (transitionType == null) {
      transition = route != null ? route.transitionType : TransitionType.native;
    }
    if (route == null && notFoundHandler == null) {
      return new RouteMatch(
          matchType: RouteMatchType.noMatch,
          errorMessage: "No matching route was found");
    }
    Map<String, List<String>> parameters =
        match?.parameters ?? <String, List<String>>{};
    if (handler.type == HandlerType.function) {
      handler.handlerFunc(buildContext, parameters,
          (routeSettings.arguments as Map<String, dynamic>)['arguments']);
      return new RouteMatch(matchType: RouteMatchType.nonVisual);
    }

    RouteCreator creator =
        (RouteSettings routeSettings, Map<String, List<String>> parameters) {
      bool isNativeTransition = (transition == TransitionType.native ||
          transition == TransitionType.nativeModal);
      if (isNativeTransition) {
        if (Platform.isIOS) {
          return new CupertinoPageRoute<dynamic>(
              settings: routeSettings,
              fullscreenDialog: transition == TransitionType.nativeModal,
              builder: (BuildContext context) {
                return handler.handlerFunc(
                    context,
                    parameters,
                    (routeSettings.arguments
                        as Map<String, dynamic>)['arguments']);
              });
        } else if (transition == TransitionType.cupertino ||
            transition == TransitionType.cupertinoFullScreenDialog) {
          return new CupertinoPageRoute<dynamic>(
              settings: routeSettings,
              fullscreenDialog:
                  transition == TransitionType.cupertinoFullScreenDialog,
              builder: (BuildContext context) {
                return handler.handlerFunc(
                    context,
                    parameters,
                    (routeSettings.arguments
                        as Map<String, dynamic>)['arguments']);
              });
        } else {
          return new MaterialPageRoute<dynamic>(
              settings: routeSettings,
              fullscreenDialog: transition == TransitionType.nativeModal,
              builder: (BuildContext context) {
                return handler.handlerFunc(
                    context,
                    parameters,
                    (routeSettings.arguments
                        as Map<String, dynamic>)['arguments']);
              });
        }
      } else {
        var routeTransitionsBuilder;
        if (transition == TransitionType.custom) {
          routeTransitionsBuilder = transitionsBuilder;
        } else {
          routeTransitionsBuilder = _standardTransitionsBuilder(transition);
        }
        return new PageRouteBuilder<dynamic>(
          settings: routeSettings,
          pageBuilder: (BuildContext context, Animation<double> animation,
              Animation<double> secondaryAnimation) {
            return handler.handlerFunc(context, parameters,
                (routeSettings.arguments as Map<String, dynamic>)['arguments']);
          },
          transitionDuration: transitionDuration,
          transitionsBuilder: routeTransitionsBuilder,
        );
      }
    };
    return new RouteMatch(
      matchType: RouteMatchType.visual,
      route: creator(settingsToUse, parameters),
    );
  }

  RouteTransitionsBuilder _standardTransitionsBuilder(
      TransitionType transitionType) {
    return (BuildContext context, Animation<double> animation,
        Animation<double> secondaryAnimation, Widget child) {
      if (transitionType == TransitionType.fadeIn) {
        return new FadeTransition(opacity: animation, child: child);
      } else {
        const Offset topLeft = const Offset(0.0, 0.0);
        const Offset topRight = const Offset(1.0, 0.0);
        const Offset bottomLeft = const Offset(0.0, 1.0);
        Offset startOffset = bottomLeft;
        Offset endOffset = topLeft;
        if (transitionType == TransitionType.inFromLeft) {
          startOffset = const Offset(-1.0, 0.0);
          endOffset = topLeft;
        } else if (transitionType == TransitionType.inFromRight) {
          startOffset = topRight;
          endOffset = topLeft;
        }

        return new SlideTransition(
          position: new Tween<Offset>(
            begin: startOffset,
            end: endOffset,
          ).animate(animation),
          child: child,
        );
      }
    };
  }

  /// Route generation method. This function can be used as a way to create routes on-the-fly
  /// if any defined handler is found. It can also be used with the [MaterialApp.onGenerateRoute]
  /// property as callback to create routes that can be used with the [Navigator] class.
  Route<dynamic> generator(RouteSettings routeSettings) {
    RouteMatch match =
        matchRoute(null, routeSettings.name, routeSettings: routeSettings);
    return match.route;
  }

  /// Prints the route tree so you can analyze it.
  void printTree() {
    _routeTree.printTree();
  }
}
