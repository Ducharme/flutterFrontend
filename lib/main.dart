import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:h3_flutter/h3_flutter.dart' as h3_flutter;
import 'package:h3_dart/h3_dart.dart' as h3_dart;

const latitudeMontreal = 45.50884;
const longitudeMontreal = -73.58781;

const latitudeMax = 89.999999;
const latitudeMin = -latitudeMax;
const longitudeMax = 179.999999;
const longitudeMin = -longitudeMax;
const equatorCtr = 0.0;
const longitudeVeryEast = 128.0;
const longitudeVeryWest = -longitudeVeryEast;

var isMapControllerReady = false;
final mapController = MapController();
final h3 = const h3_flutter.H3Factory().load();

void main() {
  runApp(const MyApp());
}

TextStyle getDefaultTextStyle() {
  return const TextStyle(
    fontSize: 12,
    backgroundColor: Colors.black,
    color: Colors.white,
  );
}

Container buildTextWidget(String word) {
  return Container(alignment: Alignment.center, child: Text(word, textAlign: TextAlign.center, style: getDefaultTextStyle()));
}

Marker buildMarker(LatLng coordinates, String word) {
  return Marker(point: coordinates, width: 100, height: 12, builder: (context) => buildTextWidget(word));
}

List<Polygon> buildPolygons() {
  if (!isMapControllerReady) {
    return [];
  }

  const extraFillArea = 0.2;
  final bounds = mapController.bounds!;
  final zoom = mapController.zoom.toInt();
  final resolution = zoom > 2 ? zoom - 2 : (zoom > 1 ? zoom - 1 : zoom);

  final x1 = math.min(bounds.northWest.longitude, bounds.southEast.longitude);
  final x2 = math.max(bounds.northWest.longitude, bounds.southEast.longitude);
  final y1 = math.min(bounds.northWest.latitude, bounds.southEast.latitude);
  final y2 = math.max(bounds.northWest.latitude, bounds.southEast.latitude);
  final dh = x2 - x1;
  final dv = y2 - y1;

  final x1withBuffer = x1 - dh * extraFillArea;
  final x2withBuffer = x2 + dh * extraFillArea;
  final y1withBuffer = y1 - dv * extraFillArea;
  final y2withBuffer = y2 + dv * extraFillArea;
  //print ("NW[x1:$x1,y1:$y1], SE[x2:$x2,y2:$y2], dh:$dh, dv:$dv, NW[x1b:$x1withBuffer,y1b:$y1withBuffer], SE[x2b:$x2withBuffer,y2b:$y2withBuffer], fullX:$fullX");

  final x1b = x1withBuffer < longitudeMin ? longitudeMin : x1withBuffer;
  final x2b = x2withBuffer > longitudeMax ? longitudeMax : x2withBuffer;
  final y1b = y1withBuffer < latitudeMin ? latitudeMin : y1withBuffer;
  final y2b = y2withBuffer > latitudeMax ? latitudeMax : y2withBuffer;

  List<List<h3_dart.GeoCoord>> listOfCoordinates = [];
  final c0 = h3_dart.GeoCoord(lat: y2b, lon: x1b);
  final c1 = h3_dart.GeoCoord(lat: y2b, lon: x2b);
  final c2 = h3_dart.GeoCoord(lat: y1b, lon: x2b);
  final c3 = h3_dart.GeoCoord(lat: y1b, lon: x1b);
  if (kDebugMode) {
    print([c0, c1, c2, c3].toString());
  }
  listOfCoordinates.add([c0, c1, c2, c3]);

  final h3indices = listOfCoordinates.map((coordinates) => h3.polyfill(coordinates: coordinates, resolution: resolution)).expand((index) => index);
  //print ("h3indices: " + h3indices.length.toString() + " zoom: " + zoom.toString());
  final points = h3indices.map((h) => getLatLngFromGeoCoord(h)).where((ll) => ll.isNotEmpty);
  //print ("h3indices: " + h3indices.length.toString() + " zoom: " + zoom.toString() + " points: " + points.length.toString());
  return points.map((pts) => Polygon(points: pts, color: Colors.blue.withOpacity(0.1), borderStrokeWidth: 1, borderColor: Colors.blue.withOpacity(0.3), isFilled: true)).toList();
}

List<LatLng> getLatLngFromGeoCoord(BigInt h3Index) {
  List<h3_dart.GeoCoord> h = h3.h3ToGeoBoundary(h3Index);
  var center = h3.h3ToGeo(h3Index);

  List<LatLng> latLngs = [];
  final isCenterWest = center.lon < equatorCtr;
  final anyLonVeryWest = h.any((e) => e.lon < longitudeVeryWest);
  final anyLonVeryEast = h.any((e) => e.lon > longitudeVeryEast);
  if (isCenterWest && anyLonVeryEast) {
    return latLngs;
  } else if (!isCenterWest && anyLonVeryWest) {
    return latLngs;
  }

  for (var i = 0; i < h.length; i++) {
    final ll = LatLng(h[i].lat, h[i].lon);
    latLngs.add(ll);
  }
  return latLngs;
}

Future<Map<String, String>?> getAdditionalOptions(BuildContext context) async {
  try {
    String jsonData = await DefaultAssetBundle.of(context).loadString("secrets.json");
    final jsonResult = json.decode(jsonData);
    Map<String, String> m = <String, String>{"userId": jsonResult["userId"], "mapStyleId": jsonResult["mapStyleId"], "accessToken": jsonResult["accessToken"]};
    return m;
  } catch (e) {
    if (kDebugMode) {
      print(e);
    }
    return null;
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<StatefulWidget> createState() {
    return _MyAppState();
  }
}

class _MyAppState extends State<MyApp> {
  List<Polygon> polygons = [];

  @override
  void initState() {
    super.initState();
    polygons = buildPolygons();
  }

  void _updatePolygons() {
    setState(() {
      polygons = buildPolygons();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: FutureBuilder(
          future: getAdditionalOptions(context),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              return FlutterMap(
                mapController: mapController,
                options: MapOptions(
                  minZoom: 2,
                  maxZoom: 18,
                  zoom: 3.2,
                  center: LatLng(latitudeMontreal, longitudeMontreal),
                  interactiveFlags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  onPositionChanged: (MapPosition position, bool hasGesture) {
                    /*var pnw = "${position.bounds?.northWest?.latitude?.toString()},${position?.bounds?.northWest?.longitude?.toString()}";
                    var pse = "${position.bounds?.southEast?.latitude?.toString()},${position?.bounds?.southEast?.longitude?.toString()}";
                    print ("onPositionChanged position(nw,se):[$pnw],[$pse]");*/
                  },
                  onMapReady: () {
                    var bnw = "${mapController.bounds?.northWest.latitude.toString()},${mapController.bounds?.northWest.longitude.toString()}";
                    var bse = "${mapController.bounds?.southEast.latitude.toString()},${mapController.bounds?.southEast.longitude.toString()}";
                    if (kDebugMode) {
                      print("onMapReady bounds(nw,se):[$bnw],[$bse]");
                    }
                    isMapControllerReady = true;
                    _updatePolygons();

                    mapController.mapEventStream.listen((evt) {
                      if (evt.toString() == "Instance of 'MapEventMoveEnd'") {
                        if (kDebugMode) {
                          print("MapEventMoveEnd");
                        }
                        _updatePolygons();
                      }
                    });
                  },
                ),
                nonRotatedChildren: [
                  // To fulfill Mapbox's requirements for attribution see https://docs.mapbox.com/help/getting-started/attribution/
                  AttributionWidget(
                    alignment: Alignment.bottomRight,
                    attributionBuilder: (context) => Row(
                      children: [
                        SvgPicture.asset('assets/images/mapbox_2019.svg', height: 16),
                        const Text(' | © '),
                        InkWell(
                          child: const Text('Mapbox'),
                          onTap: () => launchUrl(Uri.parse('https://www.mapbox.com/about/maps/')),
                        ),
                        const Text(' | © '),
                        InkWell(
                          child: const Text('OpenStreetMap'),
                          onTap: () => launchUrl(Uri.parse('http://www.openstreetmap.org/about/')),
                        ),
                        const Text(' | '),
                        InkWell(
                          child: const Text('Improve this map'),
                          onTap: () => launchUrl(Uri.parse('https://www.mapbox.com/map-feedback/#/-74.5/40/10')),
                        ),
                      ],
                    ),
                  )
                ],
                children: [
                  TileLayer(
                      urlTemplate: "https://api.mapbox.com/styles/v1/{userId}/{mapStyleId}/tiles/256/{z}/{x}/{y}@2x?access_token={accessToken}",
                      additionalOptions: snapshot.data,
                      userAgentPackageName: 'com.lafleet.app'),
                  // Examples from https://dev.to/raphaeldelio/getting-started-with-flutter-map-1p30
                  // Check later API desc from https://docs.stadiamaps.com/native-multiplatform/flutter-map/
                  PolygonLayer(polygonCulling: false, polygons: polygons),
                ], // children
              );
            } else if (snapshot.hasError) {
              return Text("Error: ${snapshot.error}");
            } else {
              // Display progress indicator while data is loading
              return const CircularProgressIndicator();
            }
          },
        ),
      ),
    );
  }
}
